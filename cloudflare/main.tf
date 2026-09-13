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

# ── Two-layer exposure model ────────────────────────────────────────────────
# PUBLIC: hostnames listed in the cloudflared tunnel ingress (e.g.
#   whoami.hero-rehab.xyz) reach Traefik directly.
# PRIVATE: everything under *.int.hero-rehab.xyz is gated by Cloudflare Zero
#   Trust Access BEFORE any request reaches the cluster (e.g.
#   temporal.int.hero-rehab.xyz). Workloads never use this path — they talk to
#   ClusterIP services in-cluster (temporal-frontend.default.svc:7233).
#
# WARP-only hardening (optional, later): add a device-posture requirement
# (`require = [{ device_posture = [<warp posture rule id>] }]`) so access
# requires an enrolled WARP client, not just an authenticated identity.
# The Kubernetes API is routed through the named tunnel only after this
# application exists. Keep this unconditional: unlike browser-facing internal
# services, operator API access is part of the cluster's steady state.
resource "cloudflare_zero_trust_access_application" "k8s_api" {
  account_id       = var.account_id
  name             = "Timestone Kubernetes API (k8s.hero-rehab.xyz)"
  domain           = "k8s.hero-rehab.xyz"
  type             = "self_hosted"
  session_duration = "24h"

  policies = [{
    name       = "timestone-operators"
    decision   = "allow"
    precedence = 1
    include    = [for e in var.access_emails : { email = { email = e } }]
  }]
}

resource "cloudflare_zero_trust_access_application" "internal" {
  # Disabled by default: internal services are fully internal (ClusterIP only,
  # no tunnel ingress). Flip `enable_internal_access` to true (and add the
  # hostname to the cloudflared ingress + an HTTPRoute) when a service needs
  # Zero Trust browser access. Requires the CF token to carry
  # "Access: Apps and Policies: Edit".
  count            = var.enable_internal_access ? 1 : 0
  account_id       = var.account_id
  name             = "Timestone internal (int.hero-rehab.xyz)"
  domain           = "*.int.hero-rehab.xyz"
  type             = "self_hosted"
  session_duration = "24h"

  policies = [{
    name     = "timestone-operators"
    decision = "allow"
    include  = [for e in var.access_emails : { email = { email = e } }]
  }]
}
