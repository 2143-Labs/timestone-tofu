# OVH leg — ts-ov-ctl + ts-ov-db (Gravelines / GRA)

Sovereign EU secondary leg: VPS-1 control node + VPS-2 DB/replica node (CNPG replica,
app mirrors, Temporal standby). Active pricing per `../timestone.md` §3.

## IMPORTANT: OVH VPS is not Terraform-manageable

The OVH Terraform provider has **no resource for VPS** (only Public Cloud instances
via OpenStack — hourly billed, ~7× Hetzner's hourly rate and unbundled disk/IP from
Oct 2026). The budget model (§3) uses prepaid **VPS-1 / VPS-2**. Therefore:

1. Create the two VPS in the OVH console (region **Gravelines / GRA**; image
   Ubuntu 24.04 placeholder — NixOS arrives via nixos-anywhere in `../bootstrap`).
2. Add the 2143 Labs ops SSH key in the console.
3. Record the instances here for reference (ids/IPs) and manage their OS/join via
   the bootstrap tooling, same as Hetzner.

The OVH API tokens (`OVH_*`) are still created and scoped (IAM: compute-read,
network-read, billing-read) — used later for cost API pulls that feed the public
cost post, and for DNS/records if needed.

## Manual checklist (console)

- [ ] NIC created under the business entity (EU; e.g., a 2143 Labs account)
- [ ] Payment method set per Public Cloud project (separate billing per project)
- [ ] Project `timestone` created (region GRA)
- [ ] IAM user + restricted token (read compute/network/billing for cost reporting)
- [ ] VPS-1 `ts-ov-ctl` (2v/4GB) + VPS-2 `ts-ov-db` (4v/8GB) created, SSH key added
- [ ] Daily automatic backups: ON (included with VPS)

## Placeholders

- Instance IDs/IPs → fill `instances.tf` (data sources or tfvars) once created.
