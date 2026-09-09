# Hetzner leg — ts-hz-ctl + ts-hz-db (Nuremberg, nbg1)

Sovereign EU primary leg: control node (CX23) + DB node (CX33) running CNPG
primary, Temporal, Traefik, cloudflared. Active pricing per `../timestone.md`
§3 (CX23 ≈ $6.47/mo, CX33 ≈ $9.17/mo as of 2026-09 — re-check the console
before committing spend; IPv4 is billed extra and included here).

Run `tofu plan/apply` in THIS directory after exporting `HCLOUD_TOKEN` +
`TF_VAR_office_cidr` + `TF_VAR_ssh_public_key` (or use `../bin/apply-nodes.sh`).

## What this module creates

- `hcloud_ssh_key` — the 2143 Labs ops public key (path via `TF_VAR_ssh_public_key`).
- `hcloud_server` ts-hz-ctl (CX23) + ts-hz-db (CX33), Ubuntu 24.04 placeholder
  image — NixOS arrives via nixos-anywhere (`../bin/install-nixos.sh`).
- `hcloud_firewall` `timestone` — inbound allow rules for the operator
  (SSH 22 + kube API 6443 + ICMP) and the k3s peer ports, attached to both
  servers. Defense in depth: the NixOS OS firewall (nixos `k3s-timestone.nix`)
  enforces the same source restriction (office IP + peer node IP) even if the
  Hetzner edge rules were ever permissive.

## Node labels / placement

- `ts-hz-db` registers `--node-label timestone.io/workload=primary` at k3s join —
  the CNPG Cluster's `nodeSelector` pins the postgres instance to the CX33.
- `ts-hz-ctl` registers `timestone.io/controlplane=true` (server).

No taints on either node this phase. cloudflared needs NO inbound rule
(outbound-only egress); 80/443 are never opened to the internet — public ingress
is exclusively via the CF tunnel.
