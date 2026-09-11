# Talos Kubernetes backend — three CX33 nodes, one each in nbg1/fsn1/hel1.
#
# Added during the migration; the legacy ts-hz-ctl/ts-hz-db server + firewall
# declarations in main.tf remain in place until retirement (step 7). Retained
# primary IPs survive node replacement: each server references its primary IP by
# ID, and the IP carries delete_protection + prevent_destroy.
#
# Datacenter names are NOT guessed here: they are resolved by `bin/cluster.py
# preflight` (lowest numeric suitable datacenter ID per location/SKU) and passed
# in through TF_VAR_talos_datacenters / -var-file. An empty map fails at plan
# time, never at validate time.

variable "talos_datacenters" {
  description = "Observed Hetzner datacenter name per location (lowest numeric suitable ID for CX33), resolved by bin/cluster.py preflight."
  type        = map(string)
  default     = {}
}

locals {
  # Order is canonical: nbg1 is the bootstrap/API anchor.
  talos_locations = ["nbg1", "fsn1", "hel1"]
  talos_peer_ips  = [for l in local.talos_locations : hcloud_primary_ip.node[l].ip_address]

  # Talos API (50000) + kube API (6443) + ICMP from the office and the three
  # retained peers; KubeSpan (51820/udp) between peers only.
  talos_admin_sources = concat([var.office_cidr], local.talos_peer_ips)
}

resource "hcloud_primary_ip" "node" {
  for_each          = toset(local.talos_locations)
  name              = "ts-talos-${each.key}"
  type              = "ipv4"
  location          = each.key
  auto_delete       = false
  delete_protection = true
  labels = {
    "managed-by"        = "tofu"
    "timestone-cluster" = "timestone"
  }
  lifecycle {
    prevent_destroy = true
  }
}

resource "hcloud_server" "node" {
  for_each    = toset(local.talos_locations)
  name        = "ts-talos-${each.key}"
  server_type = "cx33"
  datacenter  = var.talos_datacenters[each.key]
  # Ubuntu is only a pre-ISO carrier; Talos is installed from the attached ISO.
  image = "ubuntu-24.04"
  public_net {
    ipv4         = hcloud_primary_ip.node[each.key].id
    ipv4_enabled = true
    ipv6_enabled = false
  }
  labels = {
    "managed-by"        = "tofu"
    "timestone-cluster" = "timestone"
    "location"          = each.key
  }
}

resource "hcloud_firewall" "talos" {
  name = "timestone-talos"

  # Talos API
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "50000"
    source_ips = local.talos_admin_sources
  }
  # Kubernetes API
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "6443"
    source_ips = local.talos_admin_sources
  }
  # KubeSpan (WireGuard) between peers only
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "51820"
    source_ips = local.talos_peer_ips
  }
  # ICMP
  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = local.talos_admin_sources
  }
}

resource "hcloud_firewall_attachment" "talos" {
  for_each    = toset(local.talos_locations)
  firewall_id = hcloud_firewall.talos.id
  server_ids  = [hcloud_server.node[each.key].id]
}

output "talos_nodes" {
  value = {
    for l in local.talos_locations : l => {
      name          = hcloud_server.node[l].name
      ipv4          = hcloud_primary_ip.node[l].ip_address
      primary_ip_id = hcloud_primary_ip.node[l].id
      server_id     = hcloud_server.node[l].id
    }
  }
  sensitive = false
}
