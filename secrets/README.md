# secrets/ — where secrets live (NOT here, and not as plaintext anywhere)

Rule: no plaintext secret material ever enters git. Two categories:

1. **Provider tokens** — env vars at apply time (HCLOUD_TOKEN,
   CLOUDFLARE_API_TOKEN, TUNNEL_SECRET). Stored encrypted at rest in the
   office age file `~/.config/timestone/providers.env.age` (see below); never
   written to disk in plaintext by the tooling here.
2. **Node/runtime secrets** — age-encrypted in `../nixos/secrets/`
   (ciphertext committed so the public flake re-evaluates for auto-update);
   injected into Kubernetes by the `k8s-secrets-bootstrap` oneshot.

### Office env file (~/.config/timestone/providers.env.age)

```sh
age -e -R ~/.ssh/age.pub \
  -o ~/.config/timestone/providers.env.age ~/.config/timestone/providers.env
rm ~/.config/timestone/providers.env           # plaintext gone
# decrypt into the shell when needed:
eval "$(age -d -i ~/.ssh/age ~/.config/timestone/providers.env.age | sed 's/^/export /')"
```

Contents: `HCLOUD_TOKEN`, `CLOUDFLARE_API_TOKEN`, `TF_VAR_account_id`,
`TUNNEL_SECRET` (32-byte base64, shared with the tunnel credentials JSON).

| Secret | Source of truth | Injected via | Used by |
|---|---|---|---|
| Hetzner API token | Hetzner console (project `timestone`) | env `HCLOUD_TOKEN` | tofu hetzner |
| Cloudflare API token | CF dashboard | env `CLOUDFLARE_API_TOKEN` | tofu cloudflare |
| CF tunnel credentials | assembled at Stage 3.1: `tofu output tunnel_id` + `TF_VAR_account_id` + `TUNNEL_SECRET` → credentials JSON | age `cloudflared-tunnel.age` → Secret `cloudflared-credentials` | cloudflared pods |
| k3s join token | generated at Stage 3 | age `k3s-token.age` → k3s `tokenFile` | k3s join |
| DB app password | generated at bootstrap (random) | Secret `temporal-db-password` (key `password`) | CNPG managed role + Temporal |
| Backup keys (home S3) | rclone config | age `home-s3-rclone.age` | backup CronJob (deferred) |

Do NOT create placeholder K8s Secrets in the GitOps repo — ArgoCD selfHeal would
overwrite runtime-injected values (59s lesson). Manifests reference secrets by
name only.
