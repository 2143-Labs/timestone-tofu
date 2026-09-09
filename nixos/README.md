# nixos/ — NixOS host modules (PLANNED, not yet authored)

Node OS configs for the four cloud hosts live here (org-owned business infra —
deliberately NOT in the personal `dotfiles` repo, per §5 of `../timestone.md`).

## Planned layout (mirrors the dotfiles `nixos/hetzner` pattern)

```
flake.nix                     # own inputs/lock; includes ../nixos shared modules
modules/timestone-k3s.nix     # k3s server/agent + Cilium wiring + tailscale
modules/cloudflared.nix       # outbound-only CF tunnel connector (no inbound rules)
hosts/ts-hz-ctl.nix           # control node
hosts/ts-hz-db.nix            # db node
hosts/ts-ov-ctl.nix
hosts/ts-ov-db.nix
secrets/                      # agenix .age files — REFERENCED here, files live outside git
```

## Not yet done — first implementation task when this phase opens

- Shared `timestone-k3s` module (adapted from the home/dotfiles k3s modules)
- Cilium CNI + tailnet join (Headscale already self-hosted)
- Firewall: default-deny inbound; only tailnet/WireGuard peers
- Cloudflared systemd unit using the tunnel token from agenix
