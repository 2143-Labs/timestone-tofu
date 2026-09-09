output "zone_ns" {
  description = "The two Cloudflare nameservers to publish at the hero-rehab.xyz registrar"
  value       = cloudflare_zone.timestone.name_servers
}

output "zone_id" {
  value = cloudflare_zone.timestone.id
}

output "tunnel_id" {
  description = "Named tunnel UUID (goes into the cloudflared ConfigMap + credentials JSON)"
  value       = cloudflare_zero_trust_tunnel_cloudflared.timestone.id
}

output "tunnel_target" {
  description = "Wildcard CNAME target (used by the tunnel config / docs)"
  value       = "${cloudflare_zero_trust_tunnel_cloudflared.timestone.id}.cfargotunnel.com"
}
