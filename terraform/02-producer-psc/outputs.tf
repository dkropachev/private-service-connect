output "service_attachment_self_link" {
  description = "Self link of the PSC service attachment"
  value       = google_compute_service_attachment.this.self_link
}

output "ilb_ip" {
  description = "IP address of the internal load balancer"
  value       = google_compute_forwarding_rule.ilb.ip_address
}

output "port_mapping" {
  description = "Port mapping: client_port -> node_ip:backend_port"
  value = merge(
    {
      for idx, inst in var.node_instances :
      tostring(var.cql_port_base + idx) => "${inst.ip}:9042"
    },
    {
      for idx, inst in var.node_instances :
      tostring(var.ssl_cql_port_base + idx) => "${inst.ip}:9142"
    }
  )
}
