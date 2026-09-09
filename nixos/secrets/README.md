# nixos/secrets/ — agenix files for the Timestone hosts

This directory (plus `secrets.nix` here) is the ONLY secret material in the
repo, and everything in it is **age ciphertext**. Rule: no plaintext secret
value ever enters git — k8s Secrets are injected at bootstrap by the
`k8s-secrets-bootstrap` oneshot from these files.

## Files (created by the operator at Stage 3.1 — see ../bootstrap/README.md)

| Age file | Plaintext it wraps | Source |
|---|---|---|
| `timestone/k3s-token.age` | k3s cluster token (random) | `openssl rand -base64 32` |
| `timestone/cloudflared-tunnel.age` | tunnel credentials JSON | `~/.cloudflared/<uuid>.json` |
| `timestone/home-s3-rclone.age` | home SeaweedFS rclone config | operator (ONLY if backups enabled) |

## Why the ciphertext IS committed

`secrets.nix`'s age files are referenced by the NixOS modules (`age.secrets."…".file`),
so they must exist in the tree whenever the flake is evaluated. The nodes'
daily auto-update re-evaluates this flake from the **public** GitHub repo
(`github:2143-Labs/timestone-tofu?dir=nixos`), so the encrypted blobs must be
tracked. They are unusable without the office age key / node age-identity.

## Ordering requirement

Push the age files immediately after Stage 3.3 (same day as install): the
auto-update timer fires at 04:10 UTC and will fail evaluation until the
encrypted blobs are on `main`.

## Encryption recipients

`secrets.nix` — office age key + the shared `timestone-age-identity` key whose
private half is pushed to both nodes (`/etc/ssh/age-identity`) so agenix can
decrypt at first activation during nixos-anywhere.

## Encrypt/re-encrypt (office)

```sh
cd nixos && nix develop
# edit plaintext → encrypt for all recipients:
agenix -e secrets/timestone/k3s-token.age        # edits; re-encrypts on save
agenix -r                                         # re-encrypt all per secrets.nix
```
