# Hetzner leg resources

terraform {
  required_version = ">= 1.6"
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.48"
    }
  }
  # Remote state backend TBD (home SeaweedFS S3). Local-only until then.
}

provider "hcloud" {
  token = var.hcloud_token
}

resource "hcloud_ssh_key" "timestone_ops" {
  name       = var.ssh_key_name
  public_key = file(var.ssh_public_key)
}

# ts-hz-ctl — k3s control plane + ingress + ArgoCD (CX23: 2vCPU/4GB/40GB)
resource "hcloud_server" "ts_hz_ctl" {
  name        = "ts-hz-ctl"
  server_type = "cx23"
  location    = var.location
  image       = "ubuntu-24.04" # placeholder — NixOS image arrives via nixos-anywhere bootstrap
  ssh_keys    = [hcloud_ssh_key.timestone_ops.id]
  labels = {
    managed-by = "tofu"
    leg        = "hetzner"
    role       = "control-plane"
    workload   = "argocd,traefik,cloudflared"
  }
}

# ts-hz-db — CNPG primary + Temporal (CX33: 4vCPU/8GB/80GB)
resource "hcloud_server" "ts_hz_db" {
  name        = "ts-hz-db"
  server_type = "cx33"
  location    = var.location
  image       = "ubuntu-24.04" # placeholder — NixOS via bootstrap
  ssh_keys    = [hcloud_ssh_key.timestone_ops.id]
  labels = {
    managed-by = "tofu"
    leg        = "hetzner"
    role       = "database"
    workload   = "cnpg-primary,temporal"
  }
}

output "nodes" {
  value = {
    ctl = { name = hcloud_server.ts_hz_ctl.name, ipv4 = hcloud_server.ts_hz_ctl.ipv4_address }
    db  = { name = hcloud_server.ts_hz_db.name,  ipv4 = hcloud_server.ts_hz_db.ipv4_address }
  }
}
