# Cloudflare edge — c.hero.rehab child zone + wildcard tunnel CNAME

variable "cloudflare_api_token" {
  description = "Cloudflare API token (Zone:DNS:Edit + Zone:Zone:Edit). Never in files."
  type        = string
  sensitive   = true
}

variable "account_id" {
  description = "Cloudflare account id (dashboard overview right rail / API)"
  type        = string
}

variable "zone_name" {
  description = "Child zone delegated from hero.rehab (parent at Porkbun)"
  type        = string
  default     = "c.hero.rehab"
}

variable "tunnel_id" {
  description = "Named Cloudflare tunnel UUID (from `cloudflared tunnel create timestone`)"
  type        = string
}
