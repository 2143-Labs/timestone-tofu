# timestone-tofu — Timestone IaC (OpenTofu + NixOS)

Sovereign EU infrastructure for Timestone: Hetzner compute leg, Cloudflare edge
glue, NixOS host provisioning. Deploy-time cluster content lives in
[`timestone-argo`](../timestone-argo/) — this repo is *what accounts/VMs look
like* and how they boot. Canonical architecture & cost:
[`../timestone.md`](../timestone.md).

## Layout

```
hetzner/      # hcloud: ts-hz-ctl (CX23) + ts-hz-db (CX33), Nuremberg; firewall
              #   (SSH + kube API from the office IP only)
cloudflare/   # c.hero.rehab child zone + wildcard tunnel CNAME (apply after tunnel)
bootstrap/    # Stage 1→5 operator runbook (nixos-anywhere → k3s → ArgoCD)
nixos/        # NixOS sub-flake for the hosts (flake.nix, modules/, hosts/, secrets/)
bin/          # apply-nodes.sh · install-nixos.sh · cycle-node.sh
ovh/          # OVH leg (phase 2). VPS is NOT terraform-manageable → manual console
secrets/      # WHERE secrets live — never plaintext in this repo (see README)
```

## State & secrets (READ FIRST)

Provider credentials are read from the environment at apply time — never files in
this repo:

| Tool | Env var | Where created |
|---|---|---|
| Hetzner | `HCLOUD_TOKEN` | Hetzner Console → project `timestone` → API token (project-scoped R/W) |
| Cloudflare | `CLOUDFLARE_API_TOKEN` | CF dashboard → API token (Zone:DNS:Edit, Zone:Zone:Edit) |
| SSH/age | `~/.ssh/id_ed25519`, `~/.ssh/age` | office machine (nodes trust these) |

Terraform state is local-only for now (`*.tfstate` gitignored); a remote
backend lands once the home S3 endpoint is wired.

Node-level secrets (k3s token, tunnel credentials, optional rclone config) are
**age-encrypted** under `nixos/secrets/` (see its README) — never plaintext.

## Run

```sh
gh auth status                            # prerequisite: 2143-Labs org access
cloudflared tunnel create timestone       # Stage 1 — prints the tunnel UUID
bin/apply-nodes.sh                        # Stage 2 — HCLOUD_TOKEN + TF_VAR_office_cidr…
bin/install-nixos.sh ts-hz-ctl <ip>       # Stage 3 — server first, then ts-hz-db
bin/cycle-node.sh <host> <ip>             # rolling OS update (drain→rebuild→reboot)
```

Full checklist: [`bootstrap/README.md`](bootstrap/README.md).
