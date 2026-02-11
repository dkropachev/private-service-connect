output "psc_endpoint_ip" {
  description = "IP address of the PSC consumer endpoint"
  value       = google_compute_address.psc_endpoint.address
}

output "psc_endpoint_name" {
  description = "Name of the PSC consumer forwarding rule"
  value       = google_compute_forwarding_rule.psc_endpoint.name
}

output "dns_zone_name" {
  description = "Name of the private DNS zone"
  value       = google_dns_managed_zone.cluster.name
}

output "dns_records" {
  description = "DNS records created"
  value = merge(
    { (var.dns_domain) = google_compute_address.psc_endpoint.address },
    {
      for i, n in var.nodes :
      "${n.name}.${var.dns_domain}" => {
        ip   = google_compute_address.psc_endpoint.address
        port = n.port
      }
    }
  )
}
