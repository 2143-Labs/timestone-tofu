#!/usr/bin/env bash
# Guarded Timestone Talos maintenance helpers.
#
# This script never bootstraps or resets a cluster. It keeps routine health,
# snapshot and rolling-upgrade operations explicit and one node at a time.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TALOSCTL="$REPO_ROOT/.tools/talosctl"
KUBECTL="${KUBECTL:-kubectl}"
TALOSCONFIG="${TALOSCONFIG:-$HOME/.talos/timestone}"
KUBE_CONTEXT="${KUBE_CONTEXT:-admin@timestone}"
CONTROL_PLANES=(10.26.0.10 10.26.0.11 10.26.0.12)

usage() {
  cat >&2 <<'USAGE'
usage:
  maintain-talos.sh health
  maintain-talos.sh snapshot <off-cluster-output-file>
  maintain-talos.sh upgrade-node <10.26.0.10|10.26.0.11|10.26.0.12> <installer-image>
  maintain-talos.sh upgrade-k8s <version>

Requirements:
  - TALOSCONFIG points to the protected timestone Talos client configuration
  - a private/WARP route reaches 10.26.0.0/24, or TALOS_ENDPOINTS provides a
    reachable Talos API endpoint that can proxy the requested private node
  - kubectl context admin@timestone reaches the Access TCP listener
USAGE
  exit 2
}

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found"; }

[ -x "$TALOSCTL" ] || die "missing $TALOSCTL"
need "$KUBECTL"
[ -f "$TALOSCONFIG" ] || die "TALOSCONFIG not found: $TALOSCONFIG"

TALOS_ARGS=(--talosconfig "$TALOSCONFIG")
if [ -n "${TALOS_ENDPOINTS:-}" ]; then
  TALOS_ARGS+=(--endpoints "$TALOS_ENDPOINTS")
fi

is_control_plane() {
  local candidate="$1"
  local node
  for node in "${CONTROL_PLANES[@]}"; do
    [ "$candidate" = "$node" ] && return 0
  done
  return 1
}

preflight() {
  "$KUBECTL" --context "$KUBE_CONTEXT" get --raw=/readyz >/dev/null
  "$KUBECTL" --context "$KUBE_CONTEXT" wait --for=condition=Ready nodes --all --timeout=60s >/dev/null
  "$TALOSCTL" "${TALOS_ARGS[@]}" --nodes "${CONTROL_PLANES[0]}" etcd members
  "$TALOSCTL" "${TALOS_ARGS[@]}" --nodes "${CONTROL_PLANES[0]},${CONTROL_PLANES[1]},${CONTROL_PLANES[2]}" etcd status
  "$TALOSCTL" "${TALOS_ARGS[@]}" --nodes "${CONTROL_PLANES[0]},${CONTROL_PLANES[1]},${CONTROL_PLANES[2]}" etcd alarm list
}

cmd="${1:-}"
case "$cmd" in
  health)
    preflight
    "$KUBECTL" --context "$KUBE_CONTEXT" get nodes -o wide
    "$KUBECTL" --context "$KUBE_CONTEXT" -n argocd get applications \
      -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status
    ;;
  snapshot)
    output="${2:-}"
    [ -n "$output" ] || usage
    [ ! -e "$output" ] || die "refusing to overwrite snapshot: $output"
    preflight
    umask 077
    "$TALOSCTL" "${TALOS_ARGS[@]}" --nodes "${CONTROL_PLANES[0]}" etcd snapshot "$output"
    ;;
  upgrade-node)
    node="${2:-}"
    image="${3:-}"
    [ -n "$node" ] && [ -n "$image" ] || usage
    is_control_plane "$node" || die "node must be one of: ${CONTROL_PLANES[*]}"
    preflight
    printf 'Upgrading exactly one node: %s\n' "$node"
    "$TALOSCTL" "${TALOS_ARGS[@]}" --nodes "$node" upgrade --image "$image" --wait
    preflight
    ;;
  upgrade-k8s)
    version="${2:-}"
    [ -n "$version" ] || usage
    preflight
    "$TALOSCTL" "${TALOS_ARGS[@]}" --nodes "${CONTROL_PLANES[0]}" upgrade-k8s --to "$version"
    preflight
    ;;
  *) usage ;;
esac
