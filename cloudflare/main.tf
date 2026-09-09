# Cloudflare edge resources for Timestone (sovereignty: edge/DNS/tunnel ONLY —
# nothing sensitive terminates here; EU compute holds the data).
#
# Apply AFTER creating the tunnel (`cloudflared tunnel create timestone`) and
# AFTER the parent-zone NS delegation at Porkbun has propagated, otherwise the
# zone stays pending (tofu is idempotent — safe to re-run).
terraform {
  required_version = ">= 1.6"
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# Full child zone c.hero.rehab — CF becomes authoritative (type "full" = our NS
# are published at the parent). Universal SSL covers *.c.hero.rehab automatically.
resource "cloudflare_zone" "timestone" {
  zone       = var.zone_name
  account_id = var.account_id
  type       = "full"
}

# Proxied wildcard CNAME → the tunnel. Cloudflare accepts a bare "*" record and
# auto-proxies it (verified 2026-09); one record covers every hostname the
# tunnel ingress routes, so new *.c.hero.rehab services need no DNS change.
resource "cloudflare_record" "wildcard_tunnel" {
  zone_id = cloudflare_zone.timestone.id
  name    = "*"
  type    = "CNAME"
  content = "${var.tunnel_id}.cfargotunnel.com"
  proxied = true
  comment = "Timestone tunnel wildcard — all *.c.hero.rehab hostnames"
}
