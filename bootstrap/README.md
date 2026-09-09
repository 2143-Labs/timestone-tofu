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

## Stage 3 — age prep → NixOS install → k3s + ArgoCD

### 3.1 age secrets (office; keeps the shared node identity)

```sh
# shared age identity for BOTH nodes (private pushed at install):
age-keygen -o age-identity
age-keygen -y age-identity          # → paste into nixos/secrets/secrets.nix
                                    #   (replace age1PLACEHOLDER… for nodeAgeIdentity)
mkdir -p nixos/.nixos-anywhere-extra/etc/ssh
install -m 600 age-identity nixos/.nixos-anywhere-extra/etc/ssh/age-identity

# tunnel credentials JSON ← tofu outputs + the env file (never a plaintext file):
python3 - <<'EOF'
import json, os
creds = {
  "AccountTag": os.environ["TF_VAR_account_id"],
  "TunnelID": os.environ["TUNNEL_ID"],          # tofu -chdir=cloudflare output tunnel_id
  "TunnelSecret": os.environ["TUNNEL_SECRET"],  # same value given to the tunnel resource
}
open("/tmp/timestone-tunnel.json", "w").write(json.dumps(creds))
EOF
cd nixos && nix develop
# encrypt k3s token + tunnel creds for office + nodeAgeIdentity:
echo -n "<k3s-token: python3 -c 'import secrets;print(secrets.token_urlsafe(32))'>" > /tmp/k3s-token
agenix -e secrets/timestone/k3s-token.age          # paste token, save → re-encrypts
agenix -e secrets/timestone/cloudflared-tunnel.age # paste JSON from /tmp/timestone-tunnel.json
rm /tmp/k3s-token /tmp/timestone-tunnel.json
# age files ARE committed (ciphertext only) — required for the remote-flake
# auto-update + one-shot bootstraps to re-evaluate from the public repo.
# Fill <TUNNEL_ID> in ../timestone-argo/base/cloudflared/configmap.yaml too.
```

### 3.2 install (server FIRST)

```sh
cd nixos && nix develop        # provides nixos-anywhere (devShell)
../bin/install-nixos.sh ts-hz-ctl <ctl-ip>   # then:
../bin/install-nixos.sh ts-hz-db  <db-ip>
```

### 3.3 verify (on ts-hz-ctl)

k3s active (`systemctl status k3s`); `kubectl get nodes` shows **both Ready**
(ctl + db); `argocd-bootstrap` + `k8s-secrets-bootstrap` exit 0;
`argocd-server` Running; Secrets `temporal-db-password` +
`cloudflared-credentials` exist in ns default. Then COMMIT + push the age files
same day (the 04:10 auto-update timer needs them on the remote branch to
evaluate).

### 3.4 office kubeconfig (Stages 4–5 run from here, not the node)

```sh
ssh root@<ctl-ip> 'sed "s/127.0.0.1/<ctl-ip>/" /etc/rancher/k3s/k3s.yaml' \
  > ~/.kube/timestone.yaml
chmod 600 ~/.kube/timestone.yaml
export KUBECONFIG=~/.kube/timestone.yaml    # context `default`
kubectl get nodes                             # both Ready, from the office
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
