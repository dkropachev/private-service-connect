output "service_attachment_id" {
  description = "Self-link of the PSC service attachment"
  value       = google_compute_service_attachment.psc.id
}

output "service_attachment_name" {
  description = "Name of the PSC service attachment"
  value       = google_compute_service_attachment.psc.name
}

output "forwarding_rule_ip" {
  description = "IP address of the producer forwarding rule"
  value       = google_compute_forwarding_rule.portmap.ip_address
}

output "port_mappings" {
  description = "Port mapping summary"
  value = {
    for i, n in var.nodes : "node-${i}" => {
      client_port  = n.client_port
      backend_port = n.backend_port
      instance     = n.instance_self_link
    }
  }
}
