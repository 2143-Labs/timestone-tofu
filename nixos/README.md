# nixos/ — Timestone host configs (sub-flake)

NixOS for the Phase 1 Hetzner hosts. Org-owned (NOT in the personal dotfiles
repo, per §5 of ../timestone.md). Reference from the repo root as
`github:2143-Labs/timestone-tofu?dir=nixos#<host>`.

## Layout

```
flake.nix                     # inputs pinned (nixpkgs/disko/agenix revs), 2 hosts, dev shell
modules/disko.nix             # disk layout (copy of the dotfiles cluster module; /dev/sda UEFI)
modules/ssh.nix               # root authorized keys (office/arch) + agenix identities
modules/k3s-timestone.nix     # k3s server/agent module (etcd/HA-ready server flags, node labels,
                              #   source-restrictive OS firewall: office + peer node only)
modules/argocd-bootstrap.nix  # [ctl] one-shot ArgoCD install from upstream install.yaml (NOT self-managed)
modules/k8s-secrets-bootstrap.nix # [ctl] one-shot agenix → k8s Secrets (idempotent, never rotates)
modules/auto-update.nix       # daily `nixos-rebuild switch` from the public flake (no auto reboot)
hosts/ts-hz-ctl.nix           # k3s server — IPs are placeholders until Stage 2.2
hosts/ts-hz-db.nix            # k3s agent — IPs are placeholders until Stage 2.2
secrets/secrets.nix           # agenix recipient map (office + node age-identity)
secrets/timestone/*.age       # encrypted blobs — committed ciphertext (see secrets/README.md)
```

## Hosts

| Host | k3s role | Node labels | Extra modules |
|---|---|---|---|
| ts-hz-ctl | server (`--cluster-init` etcd, HA-ready) | `timestone.io/controlplane=true` | argocd-bootstrap, k8s-secrets-bootstrap, auto-update |
| ts-hz-db | agent | `timestone.io/workload=primary` (CNPG pin) | auto-update |

## Workflow

```sh
cd nixos
nix develop                                  # nixos-anywhere + age
nixos-anywhere --flake ".#ts-hz-ctl" --extra-files .nixos-anywhere-extra root@<ip>   # server first
nixos-anywhere --flake ".#ts-hz-db"  --extra-files .nixos-anywhere-extra root@<ip>
# rebuild a live node (drain→rebuild→reboot→uncordon): ../bin/cycle-node.sh <host> <ip>
```

See `../bootstrap/README.md` for the full Stage 1→5 runbook.
