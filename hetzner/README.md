# Hetzner leg — Talos Kubernetes backend + legacy k3s nodes

Sovereign EU compute leg. This module now manages **two** things:

1. **Legacy k3s/NixOS nodes** (`ts-hz-ctl` CX23 + `ts-hz-db` CX33, nbg1) — the
   original Phase-1 deployment, scheduled for retirement (step 7 of the Talos
   migration). Declarations remain in `main.tf` until then.
2. **Talos backend** (three CX33 nodes, one each in nbg1/fsn1/hel1) — the
   replacement control plane + workers, declared in `talos.tf`.

Run `tofu plan/apply` in THIS directory. HCLOUD_TOKEN is read from the
environment; `TF_VAR_office_cidr` is required.

## Talos backend — what it creates

`talos.tf` provisions bare hcloud resources and renders Talos machine configs:

- `hcloud_primary_ip` + `hcloud_server` — three CX33 nodes, `location` spread
  across nbg1/fsn1/hel1. Ubuntu 24.04 is only a pre-ISO carrier; Talos installs
  from the factory installer image.
- `hcloud_firewall` `timestone-talos` — Talos API (50000), kube API (6443),
  ICMP from the office + peers; Cilium WireGuard (51871/udp) between peers.
- `talos_machine_secrets` — generated on first apply, or import an existing
  talosctl `gen secrets` bundle (`tofu import talos_machine_secrets.this
  ../.runtime/dummy/secrets.yaml`) to reuse across renders.
- `data.talos_machine_configuration` (controlplane + worker) — rendered by the
  siderolabs/talos provider using the same strategic-merge patch engine as
  talosctl.
- Gated live management (`var.talos_manage`): `talos_machine_configuration_apply`
  (controlplane + workers), `talos_machine_bootstrap`, `talos_cluster`, and
  `talos_cluster_kubeconfig` — all network calls to the live Talos API, planned
  to 0 while `talos_manage = false`.

## Node roles / topology

- **nbg1** = control-plane (bootstrap/API anchor).
- **fsn1 + hel1** = workers (`var.talos_worker_count`, default 2).

No node taints; the control-plane `node-role.kubernetes.io/control-plane`
taint/LB-label are deleted from the control-plane config only (see patches).

## Machine config patches (`patches/`)

Patches are strategic-merge YAML applied via `config_patches`. They are split by
scope because the configpatcher's `deleteForPath` does a strict map-key lookup:

| Patch | Scope | Effect |
|---|---|---|
| `kubelet.yaml` | global | kubeReserved/systemReserved + `cloud-provider: external` |
| `cilium-kubeproxy.yaml` | control-plane | disable kube-proxy (Cilium kube-proxy replacement) |
| `cilium-cni.yaml` | control-plane | delete `KubeFlannelCNIConfig` document |
| `controlplane-taint-labels.yaml` | control-plane | delete `exclude-from-external-load-balancers` label + control-plane taint |
| (inline `yamlencode`) | global | `UnattendedInstallConfig` — install disk + factory installer image |

The install patch uses Talos 1.14's `UnattendedInstallConfig` document (the
legacy `machine.install` block is now incompatible). The factory installer image
carries the `siderolabs/qemu-guest-agent` extension (Hetzner QEMU/KVM graceful
shutdown); re-resolve it at bootstrap — see `../talos/versions.json`.

The control-plane taint/LB-label deletion MUST stay control-plane-scoped: the
worker KubeNodeConfig lacks those keys, and a global delete patch fails with
"lookup failed" during merge.

## Bootstrap / apply runbook

1. **Preflight** — resolve datacenters/locations and generate secrets once:
   ```sh
   ../.tools/talosctl gen secrets -o ../.runtime/dummy/secrets.yaml
   ```
2. **Provision VMs** (needs `HCLOUD_TOKEN`):
   ```sh
   export HCLOUD_TOKEN=… TF_VAR_office_cidr=108.56.153.222/32
   tofu init && tofu apply
   ```
3. **Import secrets into the provider** (reuse the generated bundle):
   ```sh
   tofu import talos_machine_secrets.this ../.runtime/dummy/secrets.yaml
   ```
4. **Render + inspect configs** (offline, no credentials):
   ```sh
   tofu plan   # shows talos_machine_secrets + deferred config renders
   tofu apply  # writes rendered configs as sensitive outputs
   ```
5. **Bring up the cluster** (live, on the operator machine):
   ```sh
   tofu apply -var talos_manage=true
   tofu output -raw talos_kubeconfig > ~/.kube/timestone
   ```

Until step 5 the three hcloud servers exist but are unconfigured Ubuntu hosts —
no Talos API is reachable, so the gated `talos_manage` resources must stay off.

## Key decisions (for the record)

- **OpenTofu 1.12.6**, **talos provider 0.12.0-beta.0** (SDK `v1.14.0-rc.2`,
  matches Talos 1.14.0 GA). Pinned in `../talos/versions.json`.
- **Helm 4.3.0** (not v3) — pinned in versions.json; charts are deployed via
  ArgoCD (sibling `timestone-argo`), the local helm binary is for operator use.
- **hcloud provider 1.68.0** removed the `datacenter` attribute (2026-07-01);
  nodes use `location` and the API auto-assigns the datacenter.
