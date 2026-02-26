output "psc_endpoint_ip" {
  description = "IP address of the PSC endpoint"
  value       = google_compute_address.psc_endpoint.address
}

output "port_mapping" {
  description = "Port mapping: PSC_VIP:client_port -> node_ip:9042"
  value = {
    for idx, ip in var.node_private_ips :
    "${google_compute_address.psc_endpoint.address}:${var.port_base + idx}" => "${ip}:9042"
  }
}
