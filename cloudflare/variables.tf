# Cloudflare edge — hero-rehab.xyz apex zone + named tunnel + wildcard CNAME

variable "cloudflare_api_token" {
  description = "Cloudflare API token (Zone:DNS:Edit, Zone:Zone:Edit, Account:Cloudflare Tunnel:Edit, Account:Access: Apps and Policies:Edit). Never in files."
  type        = string
  sensitive   = true
}

variable "account_id" {
  description = "Cloudflare account id (dashboard overview right rail / API)"
  type        = string
}

variable "zone_name" {
  description = "Apex zone hero-rehab.xyz (registered for Timestone)"
  type        = string
  default     = "hero-rehab.xyz"
}

variable "tunnel_secret" {
  description = "32-byte base64 secret for the named tunnel — keep identical to the value used to build the cloudflared credentials JSON at Stage 3.1 (office age-encrypted env file)"
  type        = string
  sensitive   = true
}

variable "access_emails" {
  description = "Emails allowed through Cloudflare Access: the gated Kubernetes API (k8s.hero-rehab.xyz) and, when enabled, the private layer (*.int.hero-rehab.xyz)."
  type        = list(string)
  default     = ["timestone@2143.me"]
}

variable "enable_internal_access" {
  description = "Create the Cloudflare Zero Trust Access app for the PRIVATE layer (*.int.hero-rehab.xyz). Keep false while internal services are fully internal."
  type        = bool
  default     = false
}
