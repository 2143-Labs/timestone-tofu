#!/usr/bin/env bash
# Install NixOS on a provisioned Hetzner VM via nixos-anywhere.
# Usage: install-nixos.sh <host> <ip>     (host = ts-hz-ctl | ts-hz-db)
# Call order: ts-hz-ctl FIRST (k3s server), then ts-hz-db (agent).
# Run from inside `nix develop` of ../nixos (provides nixos-anywhere).
#
# Pushes ../nixos/.nixos-anywhere-extra/etc/ssh/age-identity onto the node so
# agenix can decrypt the .age secrets at FIRST activation (see secrets/README).
set -euo pipefail

host="${1:-}"
ip="${2:-}"
if [ -z "$host" ] || [ -z "$ip" ]; then
  echo "usage: install-nixos.sh <host> <ip>" >&2
  exit 1
fi

cd "$(dirname "$0")/../nixos"

extra=".nixos-anywhere-extra"
if [ ! -f "$extra/etc/ssh/age-identity" ]; then
  echo "missing $extra/etc/ssh/age-identity — generate at Stage 3.1 (age-keygen)" >&2
  exit 1
fi
chmod 600 "$extra/etc/ssh/age-identity" 2>/dev/null || true

echo "==> nixos-anywhere $host ($ip)"
nixos-anywhere \
  --flake ".#$host" \
  --extra-files "$extra" \
  "root@$ip"
