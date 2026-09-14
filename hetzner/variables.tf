# Hetzner variables.

# HCLOUD_TOKEN is read from the environment (provider fallback); it is no longer
# a required variable/provider argument.


variable "office_cidr" {
  description = "Office public IPv4 /32 — the ONLY source allowed SSH + kube API access (no default: tofu fails loudly if unset)"
  type        = string
}

# --- Talos backend (three CX33 nodes; see talos.tf) ---

variable "talos_cluster_name" {
  description = "Talos cluster name (baked into certs, SANs, and discovery)."
  type        = string
  default     = "timestone"
}

variable "talos_version" {
  description = "Talos version contract for config generation (matches talos/versions.json core.talos)."
  type        = string
  default     = "1.14.0"
}

variable "talos_kubernetes_version" {
  description = "Kubernetes version for the Talos cluster (matches talos/versions.json core.kubernetes)."
  type        = string
  default     = "1.35.8"
}

variable "talos_schematic" {
  description = "Talos Image Factory schematic ID for the node disk image (talos/versions.json talos_installer.schematic). Content-addressed; includes siderolabs/qemu-guest-agent."
  type        = string
  default     = "ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515"
}

variable "talos_api_private_ip" {
  description = "Stable private address assigned to the Hetzner Kubernetes API load balancer."
  type        = string
  default     = "10.26.0.20"
}

variable "talos_cluster_endpoint" {
  description = "Deprecated compatibility input. The cluster endpoint is the private HA load balancer; leave null."
  type        = string
  default     = null
  nullable    = true
}

variable "talos_private_subnet" {
  description = "Hetzner private subnet CIDR for node internal IPs (nbg1=.10 control-plane anchor). Must match patches/private-network.yaml and the subnet in network.tf."
  type        = string
  default     = "10.26.0.0/24"
}

variable "talos_bootstrap_access" {
  description = "When true, open office->50000/6443 on the public firewall so tofu can apply configs and bootstrap. Flip back to false after the tunnel+SSO path is verified."
  type        = bool
  default     = false
}

# Live Talos lifecycle actions are intentionally not OpenTofu resources. A
# normal apply owns cloud infrastructure only; bootstrap and upgrades use the
# guarded one-node-at-a-time operator runbook.
