# Hetzner private network — all cluster traffic (kube API, etcd, node-to-node,
# pod SDN) runs here. Each node keeps a public IPv4 purely for egress
# (cloudflared reaches Cloudflare outbound; no inbound is ever opened on it).
# Operator access is exclusively via the Cloudflare tunnel + SSO.
resource "hcloud_network" "talos" {
  name     = "timestone-net"
  ip_range = "10.26.0.0/16"

  labels = {
    "managed-by"        = "tofu"
    "timestone-cluster" = "timestone"
  }
}

# One subnet covers all three EU locations (fsn1/nbg1/hel1 are all eu-central).
resource "hcloud_network_subnet" "talos" {
  network_id   = hcloud_network.talos.id
  type         = "cloud"
  network_zone = "eu-central"
  ip_range     = var.talos_private_subnet
}