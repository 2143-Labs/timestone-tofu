# Hetzner leg — Talos Kubernetes backend

Sovereign EU compute for Timestone. OpenTofu owns durable Hetzner resources and
offline Talos configuration generation. Kubernetes content remains in the
sibling `timestone-argo` GitOps repository.

## Topology

- Three CX33 nodes, one each in nbg1/fsn1/hel1.
- All three are schedulable Talos control-plane nodes and etcd voters.
- Static private addresses: nbg1 `.10`, fsn1 `.11`, hel1 `.12`.
- Private Hetzner LB `10.26.0.20:6443` is the stable in-cluster Kubernetes API
  endpoint and health-checks all three API servers.
- Public 6443/50000 remain closed except while the explicit
  `talos_bootstrap_access` break-glass gate is enabled from the office `/32`.
- Operator Kubernetes access remains Cloudflare Access at
  `k8s.hero-rehab.xyz`; the private LB is never public.

Three etcd members require two votes, so the cluster tolerates one failed node
or location. Two failed members stop control-plane progress by design. Running
pods may continue during loss of quorum, but scheduling, reconciliation and CSI
operations cannot.

## Ownership boundary

A normal `tofu plan/apply` owns:

- primary IPs, servers, firewall, private network/subnet;
- private Kubernetes API load balancer, targets and health check;
- clean version-pinned Talos Image Factory snapshot;
- `talos_machine_secrets` and offline control-plane config rendering.

It does **not** call a live Talos or Kubernetes API. `apply-config`, the one-time
etcd bootstrap, kubeconfig retrieval, snapshots and upgrades are lifecycle
actions with quorum/health gates; they are intentionally operator procedures.
This avoids the old `talos_manage=false` defect, where a normal plan proposed
destroying live action resources, and `talos_manage=true`, where a plan could
attempt to bootstrap an existing cluster.

State remains local and secret-bearing. Never print or commit state, rendered
machine configs, talosconfig, kubeconfig or snapshots. Remote encrypted state is
still required before multi-operator/CI apply is safe.

## Normal infrastructure maintenance

```sh
cd hetzner
export TF_VAR_office_cidr=<office-ip>/32
../.tools/tofu init
../.tools/tofu plan -out=../.runtime/hetzner.tfplan
../.tools/tofu apply ../.runtime/hetzner.tfplan
```

Steady state is a no-op. Expected changes must never include server replacement,
primary-IP destruction, Talos bootstrap, machine reset or public API exposure.

## Talos configuration documents

| Patch | Scope | Effect |
|---|---|---|
| `private-network.yaml` | all nodes | `KubeNodeConfig.nodeIP` selects `10.26.0.0/24` |
| `kubelet.yaml` | all nodes | kube/system reservations and external cloud provider |
| `cilium-kubeproxy.yaml` | all nodes | disables kube-proxy for Cilium replacement |
| `cilium-cni.yaml` | all nodes | removes built-in Flannel |
| `api-san.yaml` | all nodes | Access listener/public API hostname SANs |
| `controlplane-taint-labels.yaml` | all nodes | makes compact control planes schedulable |

Talos 1.14 split node and component settings into focused documents. Do not
restore deprecated `machine.kubelet.nodeIP` or `cluster.apiServer.certSANs`;
combining old and new ownership causes the misleading “already set” merge error.

## Routine health and backups

Use `bin/maintain-talos.sh` with a protected `TALOSCONFIG` and a private/WARP
path to the Talos API. The script refuses unknown nodes and checks Kubernetes,
three-member etcd health and alarms before and after disruptive actions.

```sh
TALOSCONFIG=~/.talos/timestone bin/maintain-talos.sh health
TALOSCONFIG=~/.talos/timestone bin/maintain-talos.sh snapshot /secure/off-cluster/etcd-$(date +%F).snapshot
```

Snapshots must leave the cluster and be retention-managed. Also verify CNPG
backup/restore separately: three control planes do not make a single-instance,
location-bound database volume highly available.

## Upgrade order

1. Verify all three etcd members, nodes, Cilium and Argo Applications are healthy.
2. Export a fresh off-cluster etcd snapshot and verify the application database
   backup.
3. Upgrade Talos on **one node only**; wait for etcd, API, Cilium and node health
   before the next. Upgrade a non-leader first where practical.
4. Upgrade Kubernetes separately with `upgrade-k8s`; do not combine it with a
   Talos or Cilium minor upgrade.
5. Update the pinned versions/config only after the live operation succeeds, then
   require a clean normal Tofu plan.

Example Talos node operation:

```sh
TALOSCONFIG=~/.talos/timestone \
  bin/maintain-talos.sh upgrade-node 10.26.0.11 \
  factory.talos.dev/metal-installer/<schematic>:<version>
```

Never reset or upgrade two control-plane nodes concurrently. With one node down,
there is no remaining failure margin.

## Upkeep backlog

- Move local OpenTofu state to encrypted remote storage with locking.
- Provide an independent private/WARP Talos API route; an in-cluster Cloudflare
  connector cannot repair a completely dead cluster. The office `/32` firewall
  gate remains break-glass until that exists.
- Automate encrypted off-cluster etcd snapshots and perform restore drills.
- Increase critical stateless replicas and add PDB/topology spread. Cloudflared
  and the Cilium operator are the first hardened components.
- Make CNPG multi-instance with backups in another location before claiming
  workload/data HA.
- Monitor etcd alarms, DB size/fragmentation, fsync/peer RTT, certificate expiry,
  node capacity, PVC location, tunnel health and pinned upstream releases.
