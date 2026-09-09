# Cloudflare edge — c.hero.rehab child zone, tunnel, Access

Edge-only by sovereignty rule (§ timestone.md §4): DNS + tunnel + Access at Cloudflare,
EU compute/data at rest only. Nothing sensitive terminates here.

## Precondition: NS delegation (manual, one-time)

`hero.rehab` is authoritative at Porkbun. `c.hero.rehab` must become its own
Cloudflare **child zone**:

1. In Cloudflare: Add site `c.hero.rehab` (Free plan) → note the two assigned
   nameservers (e.g. `xxx.ns.cloudflare.com`).
2. In Porkbun (parent zone `hero.rehab`): add NS records
   `c.hero.rehab → <cf-ns-1>, <cf-ns-2>`.
3. Cloudflare child zone becomes active → Universal SSL covers `*.c.hero.rehab`
   automatically (first-level wildcard of the delegated zone).
4. Only then can this directory's resources be applied.

## Planned resources (fill after delegation)

- `cloudflare_zone` — `c.hero.rehab`
- `cloudflare_tunnel` — named tunnel `timestone`; the tunnel token is exported as a
  K8s Secret into EVERY leg (Hetzner/OVH/home) so each runs its own `cloudflared`
  replicas pointing at the same tunnel
- `cloudflare_access_application` + policies — admin/tooling under `*.c.hero.rehab`
- DNS `*` CNAME → `<tunnel-id>.cfargotunnel.com` (proxied)

No tunnel resources are applied yet — DNS is still at Porkbun.
