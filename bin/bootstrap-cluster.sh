#!/usr/bin/env bash
# Bootstrap a freshly built Timestone Talos cluster, end to end:
#   CNI -> ArgoCD -> bootstrap Secrets -> root Application.
#
# Talos nodes are immutable and run no NixOS units, so
# nixos/modules/argocd-bootstrap.nix cannot be reused here: it is bound to
# pkgs.k3s and /etc/rancher/k3s/k3s.yaml. This script is the Talos equivalent.
#
# ORDER MATTERS. hetzner/patches/cilium-cni.yaml deletes Talos's built-in
# flannel manifest, so a new node has NO CNI: every pod sandbox fails, ArgoCD
# included — and an ArgoCD that cannot run can never sync the Cilium
# Application that would have given it networking. Cilium is therefore
# installed here, BEFORE ArgoCD, from the same values the GitOps Application
# uses, so there is exactly one source of truth for the datapath.
#
# Cilium's chart deliberately ships no CRDs (operator.skipCRDCreation defaults
# to false): cilium-operator creates them at runtime, so there is nothing to
# preload. `--include-crds` is passed anyway because it is harmless and keeps
# the command correct if upstream ever moves them back into crds/.
#
# Idempotent: safe to re-run. Credentials are read from the environment ONLY —
# this script never reads a credentials file, and never prints a secret.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOFU="$REPO_ROOT/.tools/tofu"
GITOPS_RAW="https://raw.githubusercontent.com/2143-Labs/timestone-argo/main"
ARGOCD_VERSION="v3.5.2"          # must match the running cluster
CILIUM_CHART_VERSION="1.20.1"
CILIUM_NAMESPACE="kube-system"
CILIUM_APP_URL="$GITOPS_RAW/argocd/wave-0/cilium.yaml"

KUBECONFIG_IN="${KUBECONFIG:-$HOME/.kube/timestone.yaml}"
RUNTIME_DIR="$REPO_ROOT/.runtime"
BOOTSTRAP_KUBECONFIG="$RUNTIME_DIR/bootstrap-kubeconfig"

log()  { printf '\n=== %s\n' "$*"; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found on PATH — $2"; }

# --- Preconditions ---------------------------------------------------------
need kubectl "install kubectl"
need curl    "install curl"
need python3 "install python3 (used to read tofu output)"
need helm    "run: nix shell nixpkgs#kubernetes-helm -c bash bin/bootstrap-cluster.sh"

for var in HCLOUD_TOKEN CLOUDFLARE_TUNNEL_TOKEN CLOUDFLARE_API_TOKEN; do
  [ -n "${!var:-}" ] || die "$var is not set. Export it in your shell (never from a file) and re-run."
done

[ -f "$KUBECONFIG_IN" ] || die "kubeconfig not found: $KUBECONFIG_IN
  Produce it with:
    (cd $REPO_ROOT/hetzner && ../.tools/tofu output -raw talos_kubeconfig) > ~/.kube/timestone.yaml
    chmod 600 ~/.kube/timestone.yaml"

# --- 1. A bootstrap-mode kubeconfig ---------------------------------------
# During bootstrap the API is reachable only on the control-plane node's public
# address: the office cannot route 10.26.0.0/24, and the Access-gated tunnel is
# deployed by Argo much later. Rewrite a COPY so the operator's steady-state
# kubeconfig (which points at the tunnel) is left intact.
log "Preparing the bootstrap kubeconfig"
mkdir -p "$RUNTIME_DIR"
chmod 700 "$RUNTIME_DIR"
umask 077
cp "$KUBECONFIG_IN" "$BOOTSTRAP_KUBECONFIG"
export KUBECONFIG="$BOOTSTRAP_KUBECONFIG"

NBG1_IP="${NBG1_PUBLIC_IP:-}"
if [ -z "$NBG1_IP" ]; then
  NBG1_IP="$(cd "$REPO_ROOT/hetzner" && "$TOFU" output -json talos_nodes \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["nbg1"]["ipv4"])')"
fi
[ -n "$NBG1_IP" ] || die "could not determine the nbg1 public IP; set NBG1_PUBLIC_IP"

CLUSTER_NAME="$(kubectl config view -o jsonpath='{.clusters[0].name}')"
[ -n "$CLUSTER_NAME" ] || die "no cluster entry in $KUBECONFIG_IN"
kubectl config set-cluster "$CLUSTER_NAME" --server="https://$NBG1_IP:6443" >/dev/null
printf '    API  https://%s:6443 (bootstrap path; the tunnel takes over later)\n' "$NBG1_IP"

log "Waiting for the API server (up to 120s)"
for _ in $(seq 1 60); do
  kubectl get nodes >/dev/null 2>&1 && break
  sleep 2
done
kubectl get nodes >/dev/null 2>&1 || die "API server unreachable at https://$NBG1_IP:6443
  Check that the firewall gate is open: TF_VAR_talos_bootstrap_access=true, applied."

# --- 2. CNI first: nothing schedules without it ---------------------------
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

log "Installing Cilium $CILIUM_CHART_VERSION (the CNI must exist before ArgoCD)"
curl -fsSL "$CILIUM_APP_URL" -o "$WORK/cilium-app.yaml" \
  || die "could not fetch $CILIUM_APP_URL — is the timestone-argo push done?"

# The values are a YAML literal block under spec.source.helm.values. Take the
# block and de-indent it by 8 spaces so helm can consume it directly. This
# keeps the GitOps Application the single source of truth instead of copying
# the datapath settings into this script where they would silently drift.
awk '
  /^      values: \|$/          { inblock = 1; next }
  inblock && /^[[:space:]]*$/   { print ""; next }
  inblock && /^ {8}/            { sub(/^ {8}/, ""); print; next }
  inblock                       { exit }
' "$WORK/cilium-app.yaml" > "$WORK/cilium-values.yaml"

grep -q '^routingMode:'          "$WORK/cilium-values.yaml" || die "extracted Cilium values look wrong (no routingMode)"
grep -q '^kubeProxyReplacement:' "$WORK/cilium-values.yaml" || die "extracted Cilium values look wrong (no kubeProxyReplacement)"

helm template cilium cilium \
  --version "$CILIUM_CHART_VERSION" \
  --repo https://helm.cilium.io \
  --namespace "$CILIUM_NAMESPACE" \
  --include-crds \
  -f "$WORK/cilium-values.yaml" \
  | kubectl apply --server-side --force-conflicts -f - >/dev/null

log "Waiting for nodes to become Ready (up to 300s)"
kubectl wait --for=condition=Ready nodes --all --timeout=300s

# With cloud-provider=external every node starts tainted
# node.cloudprovider.kubernetes.io/uninitialized. Cilium tolerates it, but
# upstream ArgoCD does not. Start the CCM from the same GitOps manifests before
# installing ArgoCD so it can assign provider IDs and remove that taint.
log "Initializing nodes with hcloud-cloud-controller-manager"
kubectl create secret generic hcloud -n kube-system \
  --from-literal=token="$HCLOUD_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
for manifest in serviceaccount clusterrole clusterrolebinding deployment; do
  curl -fsSL "$GITOPS_RAW/base/hcloud-ccm/${manifest}.yaml" \
    | kubectl apply --server-side --force-conflicts -f - >/dev/null
done
kubectl wait --for=condition=available deployment/hcloud-cloud-controller-manager \
  -n kube-system --timeout=180s
for _ in $(seq 1 60); do
  if ! kubectl get nodes -o jsonpath='{range .items[*]}{.spec.taints[*].key}{"\n"}{end}' \
      | grep -q '^node.cloudprovider.kubernetes.io/uninitialized$'; then
    break
  fi
  sleep 2
done
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.providerID}{"\n"}{end}' \
  | grep -q 'hcloud://' || die "hcloud CCM did not initialize the nodes"

# --- 3. ArgoCD ------------------------------------------------------------
if kubectl -n argocd get deployment argocd-server >/dev/null 2>&1; then
  log "ArgoCD is already installed — skipping"
else
  log "Installing ArgoCD $ARGOCD_VERSION"
  # Pinned ref, never ref=stable: the cluster's version must be reproducible.
  kubectl apply --server-side --force-conflicts -k \
    "https://github.com/argoproj/argo-cd/manifests/crds?ref=${ARGOCD_VERSION}"
  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl apply --server-side --force-conflicts -n argocd \
    -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
fi

# Redis refuses to start with an empty password, so set a real one.
log "Configuring ArgoCD"
REDIS_PASS="$(head -c 24 /dev/urandom | base64 | tr -d '+/=' | head -c 24)"
kubectl create secret generic argocd-redis -n argocd \
  --from-literal=auth="$REDIS_PASS" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

kubectl apply -f - >/dev/null <<'CMEOF'
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
    hs.status = "Progressing"
    hs.message = "Waiting for child Application health status"
    if obj.status ~= nil and obj.status.health ~= nil and obj.status.health.status ~= nil then
      hs.status = obj.status.health.status
      if obj.status.health.message ~= nil then
        hs.message = obj.status.health.message
      else
        hs.message = ""
      end
    end
    return hs
CMEOF

kubectl rollout restart deployment/argocd-server -n argocd >/dev/null
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=180s

# --- 4. Secrets nothing in Git creates ------------------------------------
# Created only if absent: a re-run must NEVER rotate a live database password.
# These are deliberately not in the GitOps repo, because ArgoCD's selfHeal
# would revert an injected value.
ensure_secret() {
  ns="$1"; name="$2"; shift 2
  kubectl get namespace "$ns" >/dev/null 2>&1 \
    || kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  if kubectl get secret "$name" -n "$ns" >/dev/null 2>&1; then
    echo "    $ns/$name exists — skipping (no rotation)"
  else
    kubectl create secret generic "$name" -n "$ns" "$@" \
      --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    echo "    $ns/$name created"
  fi
}

log "Creating the bootstrap Secrets"
# hcloud lives in kube-system: both consumers are Deployments there and neither
# sets a namespace on its secretKeyRef, so the name resolves locally.
ensure_secret kube-system  hcloud                   --from-literal=token="$HCLOUD_TOKEN"
# Key `token` is what base/cloudflared/deployment.yaml reads (TUNNEL_TOKEN).
ensure_secret default      cloudflared-tunnel-token --from-literal=token="$CLOUDFLARE_TUNNEL_TOKEN"
# CNPG 1.30's managed.roles[].passwordSecret requires BOTH keys, and the value
# of `username` must equal the role name. A password-only Secret cannot be
# restored — the same defect that broke spire-db-password.
ensure_secret default      temporal-db-password \
  --from-literal=username=temporal \
  --from-literal=password="$(head -c 32 /dev/urandom | base64 | tr -d '\n')"
# Required by the wave-5 UMVC3 Application; create once and never rotate.
ensure_secret default      umvc3-app \
  --from-literal=JWT_SECRET="$(head -c 48 /dev/urandom | base64 | tr -d '\n')"
# Required by the wave-4 pocket-id Application; create once and never rotate
# (PocketID encrypts its stored data with this key).
ensure_secret default      pocket-id-secrets \
  --from-literal=ENCRYPTION_KEY="$(head -c 32 /dev/urandom | base64 | tr -d '\n')"
# Consumed by the timestone DNS-01 ClusterIssuer created in the hardening phase.
ensure_secret cert-manager cloudflare-api-token     --from-literal=token="$CLOUDFLARE_API_TOKEN"

# --- 5. Hand over to GitOps ------------------------------------------------
log "Applying the root Application"
kubectl apply -f "$GITOPS_RAW/argocd/root-app.yaml"

cat <<EOF

Bootstrap complete. Watch the waves with:
  KUBECONFIG=$BOOTSTRAP_KUBECONFIG kubectl -n argocd get applications -w

Expected while the owner-run OpenBao step is still pending:
  openbao-secret-sync  Progressing   (SPIRE must issue a JWT-SVID first)
  hello-openbao        Degraded      (Secret openbao-secret-sync writes)

The steady-state kubeconfig at $KUBECONFIG_IN was NOT modified.
EOF
