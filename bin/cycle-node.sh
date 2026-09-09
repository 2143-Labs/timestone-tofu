#!/usr/bin/env bash
# Rolling NixOS update for one node: drain → rebuild → reboot → ready → uncordon.
# Usage: cycle-node.sh <host> <ip>
#
# NOTE (ts-hz-ctl): the k3s server runs embedded-etcd as a SINGLE member until a
# 3rd server joins, so cycling the control node causes a brief API outage
# (~1-3 min). Accepted and documented in the Phase 1 plan.
#
# Requires: office kubeconfig (kubectl context pointed at the cluster) + ssh root.
set -euo pipefail

host="${1:-}"
ip="${2:-}"
if [ -z "$host" ] || [ -z "$ip" ]; then
  echo "usage: cycle-node.sh <host> <ip>" >&2
  exit 1
fi

cd "$(dirname "$0")/../nixos"

echo "==> drain $host"
kubectl drain "$host" --ignore-daemonsets --delete-emptydir-data

echo "==> nixos-rebuild switch (remote)"
nixos-rebuild switch --flake ".#$host" --target-host "root@$ip"

echo "==> reboot $ip"
ssh "root@$ip" reboot || true
sleep 5

echo "==> wait for node Ready"
for i in $(seq 1 60); do
  ready=$(kubectl get node "$host" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo Unknown)
  if [ "$ready" = "True" ]; then
    break
  fi
  sleep 10
done
kubectl get node "$host"

echo "==> uncordon $host"
kubectl uncordon "$host"
echo "==> $host cycle complete"
