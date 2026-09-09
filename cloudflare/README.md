# Cloudflare edge — c.hero.rehab child zone + tunnel wildcard CNAME

Edge-only by sovereignty rule (§ timestone.md §4): DNS + tunnel at Cloudflare; EU
compute/data at rest only. Nothing sensitive terminates here. Tunnel *connectors*
(cloudflared pods) run in the Hetzner cluster and open outbound-only egress.

## What this directory provisions

- `cloudflare_zone` — full child zone `c.hero.rehab` (CF-authoritative)
- `cloudflare_record` — proxied wildcard `*` CNAME → `<tunnel-id>.cfargotunnel.com`
  (one record for every hostname the tunnel ingress routes)

Cloudflare Access (SSO) is deferred to a later phase — the Free-plan ≤50-user
limit is respected when it arrives.

## Runbook (Stage 1)

1. Create the named tunnel first (browser login, one time):
   ```sh
   cloudflared tunnel login
   cloudflared tunnel create timestone     # prints the UUID → TF_VAR_tunnel_id
   ```
2. Delegate the child zone at the parent before/while applying:
   - Cloudflare dashboard → add site `c.hero.rehab` (Free) → note the two
     assigned nameservers.
   - Porkbun (parent zone `hero.rehab`) → NS records
     `c.hero.rehab → <cf-ns-1>, <cf-ns-2>`.
   - Zone becomes Active (usually seconds–minutes). Universal SSL then covers
     `*.c.hero.rehab`.
3. Apply (idempotent — safe to re-run until Active):
   ```sh
   CLOUDFLARE_API_TOKEN=… TF_VAR_tunnel_id=<uuid> TF_VAR_account_id=… \
     tofu -chdir=cloudflare init && tofu -chdir=cloudflare apply
   ```
   `tofu output zone_ns` lists the two nameservers if you need them for the
   Porkbun step.

## Secrets

`cloudflare_api_token` comes from the environment only (never files).
The tunnel credentials JSON lives in `~/.cloudflared/<uuid>.json` locally and is
age-encrypted into `../nixos/secrets/timestone/cloudflared-tunnel.age` for the
cluster's cloudflared pods (never plaintext in a repo).
