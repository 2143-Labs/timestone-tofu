# Cloudflare edge — hero-rehab.xyz apex zone + tunnel + wildcard CNAME

Edge-only by sovereignty rule (§ timestone.md §4): DNS + tunnel at Cloudflare; EU
compute/data at rest only. Nothing sensitive terminates here. Tunnel *connectors*
(cloudflared pods) run in the Hetzner cluster and open outbound-only egress.

## What this directory provisions

- `cloudflare_zone` — full apex zone `hero-rehab.xyz` (CF-authoritative)
- `cloudflare_zero_trust_tunnel_cloudflared` — named tunnel `timestone`
  (created via the API — no interactive `cloudflared tunnel login` needed)
- `cloudflare_record` — proxied wildcard `*` CNAME → `<tunnel-id>.cfargotunnel.com`

Cloudflare Access (SSO) is deferred to a later phase — the Free-plan ≤50-user
limit is respected when it arrives.

## Runbook (Stage 1)

Secrets come from the office age-encrypted env file (`~/.config/timestone/
providers.env.age`) — decrypt into the shell, never into files:

```sh
eval "$(age -d -i ~/.ssh/age ~/.config/timestone/providers.env.age | sed 's/^/export /')"
```

Env vars required:
- `CLOUDFLARE_API_TOKEN` — Zone:DNS:Edit + Zone:Zone:Edit +
  **Account:Cloudflare Tunnel:Edit** (the tunnel resource needs it)
- `TF_VAR_account_id`
- `TF_VAR_tunnel_secret` — 32-byte base64 WITHOUT `=` padding:
  `python3 -c "import secrets,base64;print(base64.b64encode(secrets.token_bytes(32)).decode().rstrip('='))"`
  (keep the same value for the Stage 3.1 credentials JSON!)

Then:

```sh
tofu -chdir=cloudflare init && tofu -chdir=cloudflare apply
# zone is PENDING until the registrar nameservers are set (hero-rehab.xyz):
#   NS hero-rehab.xyz → the two nameservers from `tofu output zone_ns`
# re-run tofu apply until the zone is active; Universal SSL covers *.hero-rehab.xyz.
tofu -chdir=cloudflare output tunnel_id        # → fill timestone-argo ConfigMap + creds JSON
```

## Secrets

`cloudflare_api_token` + `tunnel_secret` come from the environment only. The
tunnel credentials JSON for the cluster (`{"AccountTag":…,"TunnelID":…,
"TunnelSecret":…}`) is assembled at Stage 3.1 from `tunnel_id` +
`TF_VAR_account_id` + `tunnel_secret` and age-encrypted into
`../nixos/secrets/timestone/cloudflared-tunnel.age` (never plaintext in a repo).
