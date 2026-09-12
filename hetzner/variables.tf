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

variable "talos_worker_count" {
  description = "Number of Talos worker nodes. The control plane is the nbg1 anchor; the remaining talos_locations become workers."
  type        = number
  default     = 2
}

variable "talos_cluster_endpoint" {
  description = "Kubernetes API endpoint URL (https://<LB-or-CP-ip>:6443). Placeholder for offline validate/plan; set the real LB/CP address at apply."
  type        = string
  default     = "https://talos-api.invalid:6443"
}

variable "talos_manage" {
  description = "When true, apply machine configs, bootstrap etcd, and fetch kubeconfig from live nodes (network + HCLOUD_TOKEN). Keep false for offline validate/plan."
  type        = bool
  default     = false
}
