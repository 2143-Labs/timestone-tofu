# Hetzner nodes — ts-hz-ctl / ts-hz-db (nbg1)

variable "hcloud_token" {
  description = "Hetzner project-scoped API token (project: timestone)"
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "Path to the 2143 Labs ops public key (never commit the private key)"
  type        = string
}

variable "ssh_key_name" {
  description = "Name to register the key under in Hetzner"
  type        = string
  default     = "timestone-ops"
}

variable "location" {
  description = "Hetzner EU location (sovereignty: EU only)"
  type        = string
  default     = "nbg1" # Nuremberg. Alternatives: fsn1 (Falkenstein), hel1 (Helsinki)
}
