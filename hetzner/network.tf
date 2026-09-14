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

# Stable in-cluster control-plane endpoint. The Load Balancer has no public
# interface: nodes and cloudflared reach it over timestone-net only. All three
# nodes become control planes; TCP health checks remove a rebooting API server
# before forwarding new connections.
resource "hcloud_load_balancer" "talos_api" {
  name               = "timestone-kubernetes-api"
  load_balancer_type = "lb11"
  network_zone       = "eu-central"
  delete_protection  = true

  algorithm {
    type = "round_robin"
  }

  labels = {
    "managed-by"        = "tofu"
    "timestone-cluster" = "timestone"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "hcloud_load_balancer_network" "talos_api" {
  load_balancer_id        = hcloud_load_balancer.talos_api.id
  subnet_id               = hcloud_network_subnet.talos.id
  ip                      = var.talos_api_private_ip
  enable_public_interface = false
}

resource "hcloud_load_balancer_target" "talos_api" {
  for_each = hcloud_server.node

  type             = "server"
  load_balancer_id = hcloud_load_balancer.talos_api.id
  server_id        = each.value.id
  use_private_ip   = true

  depends_on = [hcloud_load_balancer_network.talos_api]
}

resource "hcloud_load_balancer_service" "talos_api" {
  load_balancer_id = hcloud_load_balancer.talos_api.id
  protocol         = "tcp"
  listen_port      = 6443
  destination_port = 6443

  health_check {
    protocol = "tcp"
    port     = 6443
    interval = 10
    timeout  = 5
    retries  = 3
  }
}

output "talos_api_endpoint" {
  description = "Private HA Kubernetes API endpoint used by every Talos node."
  value       = "https://${hcloud_load_balancer_network.talos_api.ip}:6443"
}