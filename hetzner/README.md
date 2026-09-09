# Hetzner leg — ts-hz-ctl + ts-hz-db (Nuremberg, nbg1)

Sovereign EU primary leg: control node (CX23) + DB node (CX33) running CNPG primary,
Temporal, Traefik, cloudflared. Active pricing per `../timestone.md` §3.

Run `tofu plan/apply` in THIS directory after exporting `HCLOUD_TOKEN`.

## Notes

- Prices are as of 2026-09 (Hetzner raised CX/CPX ~30-40% on 2026-06-15); re-check
  the console before committing spend.
- IPv4 is billed extra (€0.50/mo/node) and is included in the node sizing here.
- NixOS image + k3s join happen via `../bootstrap` (nixos-anywhere), NOT here — this
  module only creates the VMs, labels, SSH key, and minimal firewall records.

## Placeholders to fill before first apply

- `hcloud_ssh_key` resource references the public key file for 2143 Labs ops —
  provide path via `TF_VAR_ssh_public_key` (do NOT commit the private key).
- `labels` use `managed-by=tofu`, `leg=hetzner`, `role=ctl|db` for cost tagging
  (feeds the public cost post).

## Firewall (TODO before production)

Default-deny inbound; open only what the tailnet + mesh need (WireGuard/Tailscale
port on gateway nodes, 6443 on control nodes reachable via tailnet only). Cloudflared
needs NO inbound rule (outbound-only egress). Do not open 80/443 to the internet —
all public ingress is via the CF tunnel.
