# Bootstrap — Stage 1→5 runbook (operator checklist)

Bring the Timestone Talos cluster (Hetzner, EU) from zero to a GitOps-managed
cluster: `https://whoami.hero-rehab.xyz` plus a working SPIRE identity plane.

Stage 1 is one-time. Stages 2–5 are per-bring-up. Talos nodes are immutable, so
there is no SSH and no NixOS install: nodes are created by OpenTofu from a
Talos Image Factory image, and everything above the OS is applied by
`bin/bootstrap-cluster.sh` and then by ArgoCD.

## Prerequisites (all must hold — else STOP and report which one)

- [ ] `HCLOUD_TOKEN` exported (Hetzner project-scoped R/W token)
- [ ] Office public IPv4 known (this machine's egress IP; find it with
      `curl -4 ifconfig.me`) → `TF_VAR_office_cidr=<ip>/32`
- [ ] `TF_VAR_talos_manage=true` (without it Tofu builds nodes but creates no
      cluster and no kubeconfig)
- [ ] `TF_VAR_talos_cluster_endpoint=https://k8s.hero-rehab.xyz:6443`
- [ ] `CLOUDFLARE_TUNNEL_TOKEN` and `CLOUDFLARE_API_TOKEN` exported
- [ ] `kubectl`, `curl`, `python3` on PATH, and `helm`
      (`nix shell nixpkgs#kubernetes-helm`)
- [ ] Vendored tools present: `.tools/tofu`, `.tools/talosctl`

Credentials are read from the environment ONLY. No script in this repo reads a
credentials file, and the operator kubeconfig is never echoed.

## Stage 1 — Cloudflare zone + tunnel (API, no browser); GitHub push PAUSED

```sh
# Secrets: decrypt the office age env file into the shell (never into files):
eval "$(age -d -i ~/.ssh/age ~/.config/timestone/providers.env.age | sed 's/^/export /')"
export TF_VAR_tunnel_secret="$TUNNEL_SECRET"   # from providers.env.age
tofu -chdir=cloudflare init && tofu -chdir=cloudflare apply
# → zone hero-rehab.xyz (PENDING until delegated) + tunnel `timestone` + wildcard CNAME
tofu -chdir=cloudflare output zone_ns          # → registrar NS records (manual, browser)
# re-apply until the zone is Active; then:
tofu -chdir=cloudflare output tunnel_id        # → fill <TUNNEL_ID> in timestone-argo
                                               #   base/cloudflared/configmap.yaml
```

Stage 1 also creates the Cloudflare **Zero Trust Access application** for
`k8s.hero-rehab.xyz`. That application must exist **before** any cloudflared
ingress rule names that hostname: DNS carries a proxied wildcard `*` CNAME to
the tunnel, so an ingress rule with no Access application in front of it would
publish an unauthenticated Kubernetes API to the internet.

## Stage 2 — Private network + Talos nodes

The private network `timestone-net` (`10.26.0.0/16`, subnet `10.26.0.0/24`) is
created first, and the node `network` block references it so `eth1` exists from
first boot. There is no live renumbering step.

```sh
cd hetzner
../.tools/tofu init
../.tools/tofu apply                     # network + 3 nodes (1 control plane, 2 workers)
../.tools/tofu output talos_nodes        # node names + public IPs
```

Private addresses are fixed by `local.talos_private_ips`: nbg1 `.10`
(control plane anchor), fsn1 `.11`, hel1 `.12`.

**Open the bootstrap firewall gate for the duration of Stages 3–4:**

```sh
export TF_VAR_talos_bootstrap_access=true
../.tools/tofu apply
```

That opens 6443 and 50000 from `TF_VAR_office_cidr` alone. It is required
because the office cannot route `10.26.0.0/24` and the tunnel is deployed by
Argo much later, in Stage 4.

## Stage 3 — Bootstrap the cluster

Produce the kubeconfig, then run the bootstrap script.

```sh
cd ..
( cd hetzner && ../.tools/tofu output -raw talos_kubeconfig ) > ~/.kube/timestone.yaml
chmod 600 ~/.kube/timestone.yaml

export KUBECONFIG=~/.kube/timestone.yaml
bin/bootstrap-cluster.sh
```

What the script does, in order:

1. Writes a **copy** of the kubeconfig under `.runtime/` with `server:` pointed
   at the nbg1 public IP for the bootstrap run — your steady-state kubeconfig is
   left untouched.
2. Waits for the API server.
3. **Installs Cilium before ArgoCD.** `hetzner/patches/cilium-cni.yaml` deletes
   Talos's built-in flannel manifest, so a new node has no CNI and every pod
   sandbox fails — ArgoCD included. An ArgoCD that cannot run can never sync the
   Cilium Application that would give it networking, so Cilium is applied here,
   using the **same values as the GitOps Application** (fetched from
   `argocd/wave-0/cilium.yaml`, so the datapath has one source of truth).
4. Installs ArgoCD pinned to the version the cluster runs, sets a non-empty
   `argocd-redis` password, and applies `argocd-cm`.
5. Creates the four bootstrap Secrets (below), each only if absent.
6. Applies the root Application, handing everything else to GitOps.

Cilium's chart ships no CRDs on purpose (`operator.skipCRDCreation` defaults to
false) — `cilium-operator` creates them at runtime, so nothing is preloaded.

## Stage 4 — Watch the ArgoCD waves

```sh
kubectl -n argocd get applications -w
kubectl -n default logs deploy/cloudflared     # "Registered tunnel connection" ×2
```

Expected non-green Applications until the owner-run OpenBao step (Phase 8.4) is
applied:

| Application | State | Why |
|---|---|---|
| `openbao-secret-sync` | `Progressing` | needs a JWT-SVID from SPIRE; logs login failures by design |
| `hello-openbao` | `Degraded` | consumes Secret `openbao-steam`, which only the sync loop writes |

These are the documented exception to "everything Synced+Healthy"; do not treat
them as a failed bring-up.

## Stage 5 — Steady state and end-to-end verification

Reach the API through the Access-gated tunnel:

```sh
cloudflared access tcp --hostname k8s.hero-rehab.xyz --url 127.0.0.1:6443 &
kubectl --context admin@timestone get nodes     # kubeconfig server: https://127.0.0.1:6443
```

The first invocation opens a browser for the Access SSO login. `127.0.0.1` is
already a certificate SAN, so nothing needs reissuing.

Once that path is verified, **close the firewall gate** — this is the step that
makes the public IPs egress-only:

```sh
cd hetzner
export TF_VAR_talos_bootstrap_access=false
../.tools/tofu apply
```

Then verify from the office machine (not node-local): `eth1` carries
`10.26.0.1{0,1,2}/24` and `kubectl get nodes -o wide` shows those as
`INTERNAL-IP`; `kubectl logs`/`exec` work for pods on *other* nodes; the
cloudflared hostnames resolve; unknown hostnames return 404; and
`nc -z -w3 <public-ip> 6443` fails.

## Secrets at bootstrap

Created by `bin/bootstrap-cluster.sh`, only if absent — a re-run never rotates a
live password. They are deliberately **not** in the GitOps repo, because
ArgoCD's `selfHeal` would revert an injected value.

| Secret | Namespace | Keys | Consumer |
|---|---|---|---|
| `hcloud` | `kube-system` | `token` | hcloud-ccm Deployment + hcloud-csi |
| `cloudflared-tunnel-token` | `default` | `token` | `base/cloudflared/deployment.yaml` |
| `temporal-db-password` | `default` | `username`, `password` | `base/cnpg/cluster.yaml` |
| `cloudflare-api-token` | `cert-manager` | `token` | the timestone DNS-01 ClusterIssuer |

`hcloud` lives in `kube-system` because both consumers are Deployments there and
neither sets a namespace on its `secretKeyRef`, so the name resolves locally.

`temporal-db-password` requires **both** keys: CNPG 1.30's
`managed.roles[].passwordSecret` needs `username` as well as `password`, and the
username must equal the role name (`temporal`). A password-only Secret cannot
survive a restore. The retired k3s path in
`nixos/modules/k8s-secrets-bootstrap.nix` carries the same fix so the two paths
cannot diverge.
