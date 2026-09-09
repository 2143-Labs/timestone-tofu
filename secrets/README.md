# secrets/ — where secrets live (NOT here, and not as plaintext anywhere)

Rule: no plaintext secret material ever enters git. Two categories:

1. **Provider tokens** — env vars at apply time (HCLOUD_TOKEN,
   CLOUDFLARE_API_TOKEN). Never written to disk by the tooling here.
2. **Node/runtime secrets** — age-encrypted in `../nixos/secrets/`
   (ciphertext committed so the public flake re-evaluates for auto-update);
   injected into Kubernetes by the `k8s-secrets-bootstrap` oneshot.

| Secret | Source of truth | Injected via | Used by |
|---|---|---|---|
| Hetzner API token | Hetzner console (project `timestone`) | env `HCLOUD_TOKEN` | tofu hetzner |
| Cloudflare API token | CF dashboard | env `CLOUDFLARE_API_TOKEN` | tofu cloudflare |
| CF tunnel credentials | `~/.cloudflared/<uuid>.json` | age → Secret `cloudflared-credentials` | cloudflared pods |
| k3s join token | generated at Stage 3 | age `k3s-token.age` → k3s `tokenFile` | k3s join |
| DB app password | generated at bootstrap (random) | Secret `temporal-db-password` (key `password`) | CNPG managed role + Temporal |
| Backup keys (home S3) | rclone config | age `home-s3-rclone.age` | backup CronJob (deferred) |

Do NOT create placeholder K8s Secrets in the GitOps repo — ArgoCD selfHeal would
overwrite runtime-injected values (59s lesson). Manifests reference secrets by
name only.
