# Talos Kubernetes backend — three CX33 nodes, one each in nbg1/fsn1/hel1.
#
# Added during the migration; the legacy ts-hz-ctl/ts-hz-db server + firewall
# declarations in main.tf remain in place until retirement (step 7). Retained
# primary IPs survive node replacement: each server references its primary IP by
# ID, and the IP carries delete_protection + prevent_destroy.
#
# Nodes are spread across three EU locations (nbg1/fsn1/hel1) via the `location`
# attribute. Hetzner removed per-datacenter pinning (2026-07-01), so the exact
# datacenter within each location is auto-assigned by the API.


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
  # Protect the maintenance API from the moment the server is created.
  firewall_ids = [hcloud_firewall.talos.id]
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
      primary_ip_id = hcloud_primary_ip.node[l].id
      server_id     = hcloud_server.node[l].id
    }
  }
  sensitive = false
}

# --- Talos provider layer: config generation + cluster bootstrap ---
#
# The siderolabs/talos provider renders machine configs using the same
# strategic-merge patch engine as talosctl (configpatcher.LoadPatches) and, once
# the hcloud servers above exist, drives bootstrap/kubeconfig against the live
# Talos API. Config generation is offline and safe to validate/plan without
# HCLOUD_TOKEN; the apply/bootstrap/cluster/kubeconfig resources make live
# network calls and are gated behind var.talos_manage (default false).

# Talos machine secrets — generated on first apply, or import an existing
# talosctl 'gen secrets' bundle to reuse it across renders:
#   tofu import talos_machine_secrets.this ../.runtime/dummy/secrets.yaml
resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

locals {
  # Global patches applied to every node type: kubelet reservations
  # (cloud-provider external) + KubeSpan. No install patch: the snapshot image
  # already contains Talos installed to /dev/sda.
  talos_global_patches = [
    file("${path.module}/patches/kubelet.yaml"),
    file("${path.module}/patches/kubespan.yaml"),
  ]

  # Control-plane-only patches: flannel CNI (only valid on control-plane
  # configs) + taint/LB-label deletion. Workers lack those KubeNodeConfig keys,
  # so the deletion patch would fail the strategic-merge "lookup" if applied
  # globally — keep it scoped to the control-plane.
  talos_controlplane_patches = concat(
    local.talos_global_patches,
    [
      file("${path.module}/patches/flannel.yaml"),
      file("${path.module}/patches/controlplane-taint-labels.yaml"),
    ],
  )

  # nbg1 is the control-plane anchor; the remaining locations are workers.
  talos_worker_locations = slice(local.talos_locations, 1, 1 + var.talos_worker_count)
}

# Control-plane machine config (bootstrap/API anchor, nbg1).
data "talos_machine_configuration" "controlplane" {
  cluster_name       = var.talos_cluster_name
  machine_type       = "controlplane"
  cluster_endpoint   = var.talos_cluster_endpoint
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.talos_kubernetes_version
  config_patches     = local.talos_controlplane_patches
}

# Worker machine config (fsn1 + hel1).
data "talos_machine_configuration" "worker" {
  cluster_name       = var.talos_cluster_name
  machine_type       = "worker"
  cluster_endpoint   = var.talos_cluster_endpoint
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.talos_kubernetes_version
  config_patches     = local.talos_global_patches
}

# --- Live-cluster management (gated behind var.talos_manage) ---
#
# These make network calls to the Talos nodes; enable only at apply with a
# reachable cluster + HCLOUD_TOKEN. With talos_manage = false they plan to 0.

resource "talos_machine_configuration_apply" "controlplane" {
  count = var.talos_manage ? 1 : 0

  node                        = hcloud_primary_ip.node["nbg1"].ip_address
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
}

resource "talos_machine_configuration_apply" "worker" {
  for_each = var.talos_manage ? toset(local.talos_worker_locations) : toset([])

  node                        = hcloud_primary_ip.node[each.key].ip_address
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
}

resource "talos_machine_bootstrap" "controlplane" {
  count = var.talos_manage ? 1 : 0

  node                 = hcloud_primary_ip.node["nbg1"].ip_address
  client_configuration = talos_machine_secrets.this.client_configuration

  depends_on = [talos_machine_configuration_apply.controlplane]
}

resource "talos_cluster" "this" {
  count = var.talos_manage ? 1 : 0

  node                 = hcloud_primary_ip.node["nbg1"].ip_address
  client_configuration = talos_machine_secrets.this.client_configuration
  kubernetes_version   = var.talos_kubernetes_version

  depends_on = [talos_machine_bootstrap.controlplane]
}

resource "talos_cluster_kubeconfig" "this" {
  count = var.talos_manage ? 1 : 0

  node                 = hcloud_primary_ip.node["nbg1"].ip_address
  client_configuration = talos_machine_secrets.this.client_configuration

  depends_on = [talos_cluster.this]
}

# --- Talos outputs (sensitive: rendered configs + kubeconfig carry secrets) ---

output "talos_controlplane_config" {
  description = "Rendered control-plane machine config (sensitive)."
  value       = data.talos_machine_configuration.controlplane.machine_configuration
  sensitive   = true
}

output "talos_worker_config" {
  description = "Rendered worker machine config (sensitive)."
  value       = data.talos_machine_configuration.worker.machine_configuration
  sensitive   = true
}
output "talos_kubeconfig" {
  description = "Raw kubeconfig for the Talos cluster (populated only when talos_manage = true)."
  value       = var.talos_manage ? talos_cluster_kubeconfig.this[0].kubeconfig_raw : null
  sensitive   = true
}
