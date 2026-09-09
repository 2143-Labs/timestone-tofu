# timestone-tofu — Timestone IaC (OpenTofu)

Sovereign EU infrastructure for Timestone: Hetzner + OVH compute legs, Cloudflare
edge glue, NixOS host provisioning. Deploy-time cluster content lives in
[`timestone-argo`](../timestone-argo/) — this repo is *what accounts/VMs look like*.

Canonical architecture & cost: [`../timestone.md`](../timestone.md).

## Layout

```
hetzner/      # hcloud provider: ts-hz-ctl (CX23), ts-hz-db (CX33), Nuremberg
ovh/          # OVH leg. VPS is NOT terraform-manageable → manual console steps here
cloudflare/   # c.hero.rehab child zone, named tunnel, Access — needs NS delegation first
bootstrap/    # nixos-anywhere + k3s + ArgoCD bootstrap order
nixos/        # NixOS host modules (planned — not yet authored)
secrets/      # WHAT lives where — tokens are NEVER committed (see README)
```

## State & secrets (READ FIRST)

Provider credentials are read from the environment at apply time — never files in
this repo:

| Tool | Env var | Where created |
|---|---|---|
| Hetzner | `HCLOUD_TOKEN` | Hetzner Console → project `timestone` → API token (project-scoped R/W) |
| OVH | `OVH_ENDPOINT`, `OVH_APPLICATION_KEY`, `OVH_APPLICATION_SECRET`, `OVH_CONSUMER_KEY` | OVH account → API tokens (IAM-restricted) |
| Cloudflare | `CLOUDFLARE_API_TOKEN` | CF dashboard → API token (Zone:DNS:Edit on `c.hero.rehab`, Tunnel:Edit) |

Terraform state backends are NOT yet configured — per-provider remote state will land
on home SeaweedFS S3 (`files.john2143.com`) once the home endpoint is wired. Until
then, local state only and `.gitignore` keeps it out of git.

## Bootstrap order

1. Create Hetzner project `timestone` + token; OVH Public Cloud project + IAM user;
   CF token. (Two cloud accounts already exist.)
2. Delegate `c.hero.rehab` at Porkbun → CF nameservers, then `tofu` in `cloudflare/`.
3. `tofu` in `hetzner/` → nodes up.
4. Create OVH VPS in console (see `ovh/README.md`) → same NixOS image as Hetzner.
5. `bootstrap/` → nixos-anywhere → k3s → ArgoCD root app (from timestone-argo).

Nothing in this repo is applied yet. All plans are local-only.
