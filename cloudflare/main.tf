# Cloudflare edge resources for Timestone (sovereignty: edge/DNS/tunnel ONLY —
# nothing sensitive terminates here; EU compute holds the data).
#
# Apply once CLOUDFLARE_API_TOKEN (Zone:DNS:Edit + Zone:Zone:Edit +
# Account:Cloudflare Tunnel:Edit) and TF_VAR_account_id + TF_VAR_tunnel_secret
# are set. The apex zone goes pending until NS is delegated at the
# hero-rehab.xyz registrar (tofu is idempotent — safe to re-run).
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

# Full apex zone hero-rehab.xyz — CF becomes authoritative (v5 resource: full
# setup, `account` = account id). Universal SSL covers *.hero-rehab.xyz
# automatically. PENDING until the parent publishes our nameservers.
resource "cloudflare_zone" "timestone" {
  account = { id = var.account_id }
  name    = var.zone_name
}

# Named tunnel `timestone` — created via the API (no interactive cloudflared
# browser login). `tunnel_secret` is supplied by the operator (kept in the
# office age-encrypted env file) and is the same value the cloudflared
# credentials JSON wraps at Stage 3.1.
resource "cloudflare_zero_trust_tunnel_cloudflared" "timestone" {
  account_id    = var.account_id
  name          = "timestone"
  tunnel_secret = var.tunnel_secret
}


# Proxied wildcard CNAME → the tunnel. Cloudflare accepts a bare "*" record and
# auto-proxies it (verified 2026-09); one record covers every hostname the
# tunnel ingress routes, so new *.hero-rehab.xyz services need no DNS change.
resource "cloudflare_dns_record" "wildcard_tunnel" {
  zone_id = cloudflare_zone.timestone.id
  name    = "*"
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.timestone.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1 # proxied records ignore TTL; 1 = auto
  comment = "Timestone tunnel wildcard — all *.hero-rehab.xyz hostnames"
}
