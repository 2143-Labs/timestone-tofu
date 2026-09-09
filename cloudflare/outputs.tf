output "zone_ns" {
  description = "The two Cloudflare nameservers to publish at the parent (Porkbun)"
  value       = cloudflare_zone.timestone.name_servers
}

output "zone_id" {
  value = cloudflare_zone.timestone.id
}

output "tunnel_target" {
  description = "Wildcard CNAME target (used by the tunnel config / docs)"
  value       = "${var.tunnel_id}.cfargotunnel.com"
}
