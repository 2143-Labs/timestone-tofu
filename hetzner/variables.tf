# Hetzner variables.

# HCLOUD_TOKEN is read from the environment (provider fallback); it is no longer
# a required variable/provider argument.

variable "location" {
  description = "Hetzner EU location for the LEGACY nodes (sovereignty: EU only). Talos nodes use per-location datacenters from talos.tf."
  type        = string
  default     = "nbg1" # Nuremberg. Alternatives: fsn1 (Falkenstein), hel1 (Helsinki)
}

variable "office_cidr" {
  description = "Office public IPv4 /32 — the ONLY source allowed SSH + kube API access (no default: tofu fails loudly if unset)"
  type        = string
}
