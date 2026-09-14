# Talos Kubernetes backend — three schedulable control-plane nodes, one each in
# nbg1/fsn1/hel1. Three etcd voters tolerate one node or location failure while
# retaining quorum; every node also carries workloads because this is a compact
# three-machine cluster.
#
# The hcloud Image Factory snapshot is a clean Talos disk image. Machine
# configuration is generated here for deterministic bootstrap/recovery, but
# network calls such as apply-config, bootstrap and OS/Kubernetes upgrades are
# deliberately guarded operator procedures rather than ordinary tofu resources.
# That separation keeps a normal tofu plan/apply independent of Talos API
# reachability and prevents a one-time bootstrap call from recurring.


locals {
  # Order is canonical for maintenance procedures and static private addresses.
  talos_locations = ["nbg1", "fsn1", "hel1"]

  # Hetzner private network: one static internal IP per node, derived from its
  # position (nbg1 = .10 control-plane anchor). The CIDR must match the
  # validSubnets in patches/private-network.yaml.
  talos_private_cidr = var.talos_private_subnet
  talos_private_ips = {
    for i, l in local.talos_locations : l => cidrhost(local.talos_private_cidr, 10 + i)
  }

  # Private L4 load balancer used by all nodes for the Kubernetes API. Keep this
  # value aligned with hcloud_load_balancer_network.talos_api in network.tf.
  talos_cluster_endpoint = "https://${var.talos_api_private_ip}:6443"
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


# Golden snapshot: factory hcloud-platform disk image -> Hetzner snapshot image.
# Must be the hcloud platform (not metal): the metal image yields providerID
# talos://metal/... which breaks hcloud-cloud-controller-manager route creation
# (see terraform-hcloud-talos issue #417).
data "talos_image_factory_urls" "hcloud_amd64" {
  talos_version = var.talos_version
  schematic_id  = var.talos_schematic
  platform      = "hcloud"
  architecture  = "amd64"
}

resource "imager_image" "talos" {
  image_url    = data.talos_image_factory_urls.hcloud_amd64.urls.disk_image
  architecture = "x86"

  labels = {
    version = var.talos_version
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "hcloud_server" "node" {
  for_each    = toset(local.talos_locations)
  name        = "ts-talos-${each.key}"
  server_type = "cx33"
  location    = each.key
  # Boot from the pinned Talos snapshot (disk already contains Talos).
  image = imager_image.talos.image_id
  # Public IPv4 is egress-only: no inbound is opened on it (see firewall).
  firewall_ids = [hcloud_firewall.talos.id]
  public_net {
    ipv4         = hcloud_primary_ip.node[each.key].id
    ipv4_enabled = true
    ipv6_enabled = false
  }
  # Attach to the private network; the internal IP carries all cluster traffic.
  network {
    network_id = hcloud_network.talos.id
    ip         = local.talos_private_ips[each.key]
  }
  labels = {
    "managed-by"        = "tofu"
    "timestone-cluster" = "timestone"
    "location"          = each.key
  }
}

resource "hcloud_firewall" "talos" {
  name = "timestone-talos"

  # Steady state: NO inbound TCP on the public interface — all cluster traffic
  # runs over the private network and operator access is via Cloudflare tunnel
  # + SSO only. The two bootstrap rules below exist ONLY while
  # var.talos_bootstrap_access is true so tofu can apply configs and bootstrap
  # the cluster from the office; flip back to false after the tunnel is live.

  dynamic "rule" {
    for_each = var.talos_bootstrap_access ? [1] : []
    content {
      direction  = "in"
      protocol   = "tcp"
      port       = "50000"
      source_ips = [var.office_cidr]
    }
  }

  dynamic "rule" {
    for_each = var.talos_bootstrap_access ? [1] : []
    content {
      direction  = "in"
      protocol   = "tcp"
      port       = "6443"
      source_ips = [var.office_cidr]
    }
  }

  # ICMP from the office for diagnostics (ping only; no service surface).
  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = [var.office_cidr]
  }
}

# Attachment resources own the entire firewall's server set. Forget the old
# per-node owners without detaching anything; each server now owns its binding.
removed {
  from = hcloud_firewall_attachment.talos
  lifecycle {
    destroy = false
  }
}

output "talos_nodes" {
  value = {
    for l in local.talos_locations : l => {
      name          = hcloud_server.node[l].name
      ipv4          = hcloud_primary_ip.node[l].ip_address
      ipv4_private  = local.talos_private_ips[l]
      primary_ip_id = hcloud_primary_ip.node[l].id
      server_id     = hcloud_server.node[l].id
    }
  }
  sensitive = false
}

# --- Talos provider layer: config generation + cluster bootstrap ---
#
# The provider renders a complete, secret-bearing machine configuration for
# bootstrap/recovery. Tofu does not apply it automatically: day-two machine
# changes and upgrades must use the guarded one-node-at-a-time runbook.

# Talos machine secrets — generated on first apply, or import an existing
# talosctl 'gen secrets' bundle to reuse it across renders:
#   tofu import talos_machine_secrets.this ../.runtime/dummy/secrets.yaml
resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

locals {
  # Global patches applied to every node. Talos 1.14 has split the old
  # v1alpha1 machine tree into focused documents, so node IP and kubelet
  # settings are separate patches and never double-own the same field.
  talos_global_patches = [
    file("${path.module}/patches/private-network.yaml"),
    file("${path.module}/patches/kubelet.yaml"),
  ]

  # Every node is a schedulable control plane. The same CNI, API SAN and taint
  # policy must therefore be present on all three nodes.
  talos_controlplane_patches = concat(
    local.talos_global_patches,
    [
      file("${path.module}/patches/cilium-kubeproxy.yaml"),
      file("${path.module}/patches/cilium-cni.yaml"),
      file("${path.module}/patches/api-san.yaml"),
      file("${path.module}/patches/controlplane-taint-labels.yaml"),
    ],
  )
}

# Shared control-plane machine config for nbg1, fsn1 and hel1. Node-specific
# hostnames and addresses come from Talos/Hetzner at runtime; every node selects
# its 10.26.0.0/24 address through KubeNodeConfig.
data "talos_machine_configuration" "controlplane" {
  cluster_name       = var.talos_cluster_name
  machine_type       = "controlplane"
  cluster_endpoint   = local.talos_cluster_endpoint
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.talos_kubernetes_version
  config_patches     = local.talos_controlplane_patches
}

data "talos_client_configuration" "this" {
  cluster_name         = var.talos_cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = values(local.talos_private_ips)
  nodes                = values(local.talos_private_ips)
}

# Bootstrap/action resources previously occupied this state. Their provider
# delete operations are no-ops unless reset=true, so remove their state records
# without touching the live nodes. Bootstrap, apply-config and upgrades now live
# in the guarded operator runbook rather than normal infrastructure convergence.
removed {
  from = talos_machine_configuration_apply.controlplane
  lifecycle { destroy = false }
}

removed {
  from = talos_machine_configuration_apply.worker
  lifecycle { destroy = false }
}

removed {
  from = talos_machine_bootstrap.controlplane
  lifecycle { destroy = false }
}

# Normal tofu plan/apply stops here. It owns durable cloud infrastructure,
# cluster secrets and deterministic offline renders; it never calls a live Talos
# or Kubernetes endpoint.

# --- Talos outputs (sensitive: rendered configs + kubeconfig carry secrets) ---

output "talos_controlplane_config" {
  description = "Rendered control-plane machine config used by all three nodes (sensitive)."
  value       = data.talos_machine_configuration.controlplane.machine_configuration
  sensitive   = true
}

output "talosconfig" {
  description = "Raw Talos client config for lifecycle operations (sensitive)."
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
}
