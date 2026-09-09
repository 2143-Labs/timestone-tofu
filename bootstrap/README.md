# Bootstrap — Stage 1→5 runbook (operator checklist)

Bring Timestone Phase 1 (Hetzner-only) from zero to
`https://whoami.c.hero.rehab` + `https://temporal.c.hero.rehab` returning 200.

The plan this implements: `timestone-phase1-hetzner-plan.md` (approved). Stages 0
(commit) and 1 (zone/push) are one-time; 2–5 are per-bring-up. Rollback is clean
at every stage (see plan §Assumptions).

## Prerequisites (all must hold — else STOP and report which one)

- [ ] `gh auth status` works (org 2143-Labs)
- [ ] Hetzner project `timestone` exists; project-scoped R/W token ready
      (export `HCLOUD_TOKEN`)
- [ ] Office public IPv4 known (this machine's egress IP) → `TF_VAR_office_cidr=<ip>/32`
- [ ] Cloudflare API token (Zone:DNS:Edit + Zone:Zone:Edit) + account id; `hero.rehab`
      at Porkbun (NS edits manual)
- [ ] (optional) Home SeaweedFS S3 creds for `timestone-backups` → skip backups
      this phase if absent (documented omission)

## Stage 1 — Cloudflare zone + tunnel (API, no browser); GitHub push PAUSED

```sh
# Secrets: decrypt the office age env file into the shell (never into files):
eval "$(age -d -i ~/.ssh/age ~/.config/timestone/providers.env.age | sed 's/^/export /')"
export TF_VAR_tunnel_secret="$TUNNEL_SECRET"   # from providers.env.age
tofu -chdir=cloudflare init && tofu -chdir=cloudflare apply
# → zone c.hero.rehab (PENDING until delegated) + tunnel `timestone` + wildcard CNAME
tofu -chdir=cloudflare output zone_ns          # → Porkbun NS records (manual, browser)
# re-apply until the zone is Active; then:
tofu -chdir=cloudflare output tunnel_id        # → fill <TUNNEL_ID> in timestone-argo
                                               #   base/cloudflared/configmap.yaml + creds JSON
```

The GitHub push (create 2143-Labs/timestone-{argo,tofu} --public --push) is
**paused pending operator review** — repos stay local-only until told otherwise.

## Stage 2 — Hetzner nodes

```sh
HCLOUD_TOKEN=… TF_VAR_office_cidr=<office-ip>/32 TF_VAR_ssh_public_key=<key.pub> \
  tofu -chdir=hetzner init && tofu -chdir=hetzner apply
ssh -o StrictHostKeyChecking=accept-new root@<ip> true   # both output IPs
# Fill node IPs into ../nixos/hosts/*.nix (ownIp/peerIp/serverAddr) NOW.
```

## Stage 3 — NixOS + k3s + ArgoCD

```sh
# (office) one shared age identity for the nodes:
age-keygen -o age-identity   # keep private on office; pub → secrets/secrets.nix
# encrypt the .age files (office age key + the node age-identity pub):
#   secrets/timestone/k3s-token.age            (openssl rand -base64 32)
#   secrets/timestone/cloudflared-tunnel.age   (contents of ~/.cloudflared/<uuid>.json)
#   secrets/timestone/home-s3-rclone.age       (only if backups wanted)
# age files ARE committed (ciphertext only) — the remote-flake auto-update and
# the one-shot bootstraps must be able to re-evaluate from the public repo.
cd ../nixos && nix develop
bin/install-nixos.sh ts-hz-ctl <ctl-ip>   # server first, then:
bin/install-nixos.sh ts-hz-db  <db-ip>
# verify on ts-hz-ctl: k3s active, 2 nodes Ready, argocd-bootstrap +
# k8s-secrets-bootstrap exited 0, argocd-server Running, both Secrets exist.
```

## Stage 4 — ArgoCD wave sync

```sh
kubectl -n argocd get application root        # → Synced/Healthy
kubectl get applications -n argocd -w         # all Synced+Healthy
kubectl -n default logs deploy/cloudflared    # "Registered tunnel connection" ×2
kubectl -n default get svc                    # timestone-rw + temporal services
```

## Stage 5 — End-to-end verification

External checks from the office machine (NOT node-local): dig/curl the two
hostnames, Gateway `Programmed=True`, 404 on unknown hostnames, in-cluster
`select 1`, ArgoCD UI healthy, rolling `nixos-rebuild switch` on both nodes,
`systemctl list-timers` shows the daily update.

## Secrets at bootstrap

Secrets are injected on the host by the agenix oneshot (`k8s-secrets-bootstrap`,
59s pattern) — never present as plaintext in these repos. `k8s-secrets-bootstrap`
is idempotent: it never rotates an existing Secret (DB password stability under
CNPG/Temporal).
