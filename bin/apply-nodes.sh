#!/usr/bin/env bash
# Apply the Hetzner node Terraform state (ts-hz-ctl + ts-hz-db).
# Requires HCLOUD_TOKEN + TF_VAR_office_cidr + TF_VAR_ssh_public_key.
set -euo pipefail

if [ -z "${HCLOUD_TOKEN:-}" ]; then
  echo "HCLOUD_TOKEN is not set — export the project-scoped Hetzner token first." >&2
  exit 1
fi

cd "$(dirname "$0")/../hetzner"
tofu init
tofu apply
echo
echo "Node IPs:"
tofu output nodes
