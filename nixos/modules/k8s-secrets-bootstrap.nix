# agenix → Kubernetes Secrets injection (server node only)
#
# Adapted from dotfiles/nixos/cluster/modules/k3s-common.nix:302-364. Decrypts
# agenix files and creates the two Kubernetes Secrets ArgoCD manifests consume
# by name. Runs after argocd-bootstrap.
#
# IDEMPOTENT: every create is wrapped in a `kubectl get secret … ||` guard so a
# re-run NEVER rotates an existing value — the CNPG/Temporal DB password must
# stay stable across rebuilds. Secrets are NEVER mirrored as placeholders in
# the GitOps repo (ArgoCD selfHeal would overwrite injected values).
{
  config,
  lib,
  pkgs,
  ...
}: {
  age.secrets."timestone/cloudflared-tunnel" = {
    file = ../secrets/timestone/cloudflared-tunnel.age;
    mode = "0400";
    owner = "root";
    group = "root";
  };

  systemd.services.k8s-secrets-bootstrap = {
    description = "Inject agenix secrets into Kubernetes Secrets";
    after = ["k3s.service" "argocd-bootstrap.service"];
    wants = ["k3s.service"];
    wantedBy = ["multi-user.target"];
    path = [pkgs.k3s];
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

      # Create only if absent — never rotate.
      ensure_secret() {
        name=$1
        shift
        if kubectl get secret "$name" -n default >/dev/null 2>&1; then
          echo "secret $name exists — skipping (no rotation)"
        else
          kubectl create secret generic "$name" -n default "$@" \
            --dry-run=client -o yaml | kubectl apply -f -
        fi
      }

      # Temporal DB password. CNPG 1.30's managed.roles[].passwordSecret
      # requires BOTH keys and the value of `username` must equal the role
      # name; a password-only Secret cannot survive a restore. This is the
      # same defect that broke spire-db-password.
      ensure_secret temporal-db-password \
        --from-literal=username=temporal \
        --from-literal=password="$(head -c 32 /dev/urandom | base64 | tr -d '\n')"

      # cloudflared tunnel credentials — the <uuid>.json from Stage 1
      # (cloudflared tunnel create timestone). Stored under key credentials.json;
      # the cloudflared Deployment mounts it as /etc/cloudflared/creds.json.
      ensure_secret cloudflared-credentials \
        --from-literal=credentials.json="$(cat ${config.age.secrets."timestone/cloudflared-tunnel".path})"

      # Do NOT create an ArgoCD admin password — upstream install.yaml does.
    '';
  };
}
