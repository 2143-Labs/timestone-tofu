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
    workload   = "argocd-traefik-cloudflared"
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
    workload   = "cnpg-temporal"
  }
}

# Kube API + SSH reachable ONLY from the office public IP (sovereignty admin
# model), plus the k3s peer-node traffic between the two servers. hcloud
# firewalls are inbound-only — cloudflared needs no inbound rule (outbound
# tunnel egress); do NOT open 80/443 to the internet.
# The NixOS OS firewall mirrors these rules source-for-source (defense in depth
# even if the edge semantics were ever permissive).
locals {
  peer_ips = [
    hcloud_server.ts_hz_ctl.ipv4_address,
    hcloud_server.ts_hz_db.ipv4_address,
  ]
}

resource "hcloud_firewall" "timestone" {
  name = "timestone"

  # operator: SSH + kube API + ICMP, office IP only
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22" # SSH (nixos-anywhere, operator)
    source_ips = [var.office_cidr]
  }
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "6443"                                    # kube API
    source_ips = concat([var.office_cidr], local.peer_ips) # agent → apiserver
  }
  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = [var.office_cidr]
  }

  # k3s cluster ports between the two peers (flannel VXLAN + supervisor/kubelet)
  dynamic "rule" {
    for_each = toset(["179", "7946", "10250"])
    content {
      direction  = "in"
      protocol   = "tcp"
      port       = rule.value
      source_ips = local.peer_ips
    }
  }
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "8472"
    source_ips = local.peer_ips
  }
}

resource "hcloud_firewall_attachment" "timestone_ctl" {
  firewall_id = hcloud_firewall.timestone.id
  server_ids  = [hcloud_server.ts_hz_ctl.id]
}

resource "hcloud_firewall_attachment" "timestone_db" {
  firewall_id = hcloud_firewall.timestone.id
  server_ids  = [hcloud_server.ts_hz_db.id]
}

output "nodes" {
  value = {
    ctl = { name = hcloud_server.ts_hz_ctl.name, ipv4 = hcloud_server.ts_hz_ctl.ipv4_address }
    db  = { name = hcloud_server.ts_hz_db.name, ipv4 = hcloud_server.ts_hz_db.ipv4_address }
  }
}
