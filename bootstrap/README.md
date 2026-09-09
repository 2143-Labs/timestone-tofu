# Bootstrap — nixos-anywhere → k3s → ArgoCD

Order of operations to bring a fresh VM from "provider console" to "ArgoCD-synced
k3s node". Not runnable yet — NixOS host modules are not authored (see `../nixos/`).

## Per host

```sh
# 1. Provision VM (Hetzner: tofu in ../hetzner; OVH: console — see ../ovh)
# 2. Install NixOS (when ../nixos/hosts/<host>.nix exists):
nixos-anywhere --flake "path:../nixos#<host>" root@<ip>
# 3. Join k3s: control nodes init with --cluster-init + fixed token from agenix;
#    db/app nodes join via the tailnet registration URL.
# 4. Install ArgoCD + apply root Application (from timestone-argo/argocd/root-app.yaml)
# 5. Wave sync: cnpg-operator → clusters → temporal → traefik → apps → cloudflared
```

## Node plan

| Host | Provider | Role |
|---|---|---|
| ts-hz-ctl | Hetzner nbg1 | k3s control, ArgoCD, Traefik, cloudflared |
| ts-hz-db | Hetzner nbg1 | k3s, CNPG primary, Temporal |
| ts-ov-ctl | OVH GRA | k3s control, Traefik, cloudflared |
| ts-ov-db | OVH GRA | k3s, CNPG replica, apps, Temporal standby |

## Secrets at bootstrap

Tokens/secrets are injected on the host by the agenix oneshot (`k8s-secrets-bootstrap`,
59s pattern) — never present in these repos.
