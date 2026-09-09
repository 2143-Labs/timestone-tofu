# ArgoCD bootstrap oneshot (server node only)
#
# Adapted from dotfiles/nixos/cluster/modules/k3s-common.nix:62-288, with every
# 9s-specific install stripped (istio, traefik, longhorn, CNPG operator,
# cert-manager, k8gb/coredns arrive via ArgoCD waves instead from
# timestone-argo). Runs once after k3s is up: CRDs → install.yaml → redis
# secret → argocd-cm → restart → root Application.
{
  config,
  lib,
  pkgs,
  ...
}: {
  systemd.services.argocd-bootstrap = {
    description = "Install ArgoCD into k3s cluster";
    after = ["k3s.service"];
    wants = ["k3s.service"];
    wantedBy = ["multi-user.target"];
    path = [pkgs.k3s pkgs.curl pkgs.git pkgs.kubernetes-helm];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
      for i in $(seq 1 30); do
        kubectl get nodes &>/dev/null && break
        sleep 2
      done
      # Idempotent: this oneshot re-runs on every `nixos-rebuild switch`
      # (wantedBy multi-user). If ArgoCD is already installed, do nothing —
      # never re-apply over a live install.
      if kubectl -n argocd get deployment argocd-server &>/dev/null; then
        echo "argocd already installed — skipping bootstrap"
        exit 0
      fi
      # Install CRDs first (--server-side avoids annotation size limits)
      kubectl apply --server-side --force-conflicts \
        -k https://github.com/argoproj/argo-cd/manifests/crds?ref=stable
      kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
      kubectl apply --server-side --force-conflicts -n argocd \
        -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
      # Create redis secret with non-empty password (empty password breaks redis config parsing)
      REDIS_PASS=$(head -c 24 /dev/urandom | base64 | tr -d '+/=' | head -c 24)
      kubectl create secret generic argocd-redis -n argocd \
        --from-literal=auth="$REDIS_PASS" \
        --dry-run=client -o yaml | kubectl apply -f -
      kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=120s || true
      # Apply ArgoCD ConfigMap — health check + resource tracking (inline, not from repo)
      kubectl apply -f - <<'CMEOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
  labels:
    app.kubernetes.io/name: argocd-cm
    app.kubernetes.io/part-of: argocd
data:
  application.resourceTrackingMethod: annotation+label
  resource.customizations.health.argoproj.io_Application: |
    hs = {}
    hs.status = "Healthy"
    hs.message = ""
    if obj.status ~= nil then
      if obj.status.health ~= nil then
        local h = obj.status.health.status
        if h == "Degraded" then
          hs.status = "Degraded"
          if obj.status.health.message ~= nil then
            hs.message = obj.status.health.message
          end
        end
      end
    end
    return hs
CMEOF
      kubectl rollout restart deployment/argocd-server -n argocd || true
      kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=60s || true
      # Apply root Application — wires ArgoCD to the public GitOps repo.
      # Non-fatal: the repo may not be pushed yet on a fresh install; apply it
      # imperatively once the push happens (Stage 4.1):
      #   kubectl -n argocd apply -f https://raw.githubusercontent.com/2143-Labs/timestone-argo/main/argocd/root-app.yaml
      kubectl apply -f https://raw.githubusercontent.com/2143-Labs/timestone-argo/main/argocd/root-app.yaml \
        || echo "root Application deferred — apply after the timestone-argo push (see bootstrap README Stage 4)"
      kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=120s || true
    '';
  };
}
