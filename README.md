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
eval "$(age -d -i ~/.ssh/age ~/.config/timestone/providers.env.age | sed 's/^/export /')"  # office tokens
bin/apply-nodes.sh                        # Stage 2 — HCLOUD_TOKEN + TF_VAR_office_cidr…
bin/install-nixos.sh ts-hz-ctl <ip>       # Stage 3 — server first, then ts-hz-db
bin/cycle-node.sh <host> <ip>             # rolling OS update (drain→rebuild→reboot)
```

Full checklist: [`bootstrap/README.md`](bootstrap/README.md).

## CI / multi-user (GitHub Actions)

Deploys are NOT office-machine-only. `.github/workflows/`:

| Workflow | Trigger | Needs secrets | Effect |
|---|---|---|---|
| `tofu-validate.yml` | PR + push to main (tofu paths) | none | `fmt -check` + `tofu validate` on hetzner/ + cloudflare/ |
| `tofu-apply.yml` | push to main (tofu paths) + manual | yes | `tofu apply` cloudflare → hetzner |
| `nixos-check.yml` | PR + push (nixos paths) | none | flake eval of both host configs (skipped until Stage 3.1 age files are committed) |

Apply runs on the `timestone` GitHub **environment**, so an approval rule can
gate it (repo Settings → Environments). Anyone with 2143-Labs repo access who
can run the workflow inherits deploy capability — no machine/key setup.

### GitHub Actions secrets (set once after the repos exist)

Repo (or org) secrets on `2143-Labs/timestone-tofu` — plaintext never enters the
repo:

| Secret | Value |
|---|---|
| `HCLOUD_TOKEN` | Hetzner project-scoped R/W token |
| `CLOUDFLARE_API_TOKEN` | CF token (Zone:DNS:Edit, Zone:Zone:Edit, Tunnel:Edit) |
| `CF_ACCOUNT_ID` | Cloudflare account id |
| `TUNNEL_SECRET` | the 32-byte base64 tunnel secret (same as the office env file) |
| `OFFICE_CIDR` | office public IPv4 `/32` (update if the office egress IP changes) |

```sh
gh secret set HCLOUD_TOKEN --repo 2143-Labs/timestone-tofu
# … repeat for the other four
```

The office age env file (`~/.config/timestone/providers.env.age`) remains the
canonical store for local runs and for one-time Stage 3 installs (see
`secrets/README.md`); the GitHub secrets mirror it for CI.

## Phase 1 nodes (live — 2026-09-09, Hetzner nbg1)

| Host | IPv4 | k3s role | Node label | Workloads |
|---|---|---|---|---|
| ts-hz-ctl | `46.224.91.55` | server (`--cluster-init`, embedded etcd) | `timestone.io/controlplane=true` | ArgoCD, Traefik, cloudflared |
| ts-hz-db | `178.104.247.194` | agent | `timestone.io/workload=primary` | CNPG primary, Temporal |

SSH + kube API (6443) are open to the office IP only (`108.56.153.222/32`),
enforced by the hcloud firewall and the NixOS OS firewall. Rolling update:
`bin/cycle-node.sh ts-hz-ctl 46.224.91.55`.
