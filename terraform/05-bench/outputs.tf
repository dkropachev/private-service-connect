output "bench_vm_name" {
  description = "Name of the bench VM"
  value       = google_compute_instance.bench.name
}

output "bench_vm_zone" {
  description = "Zone of the bench VM"
  value       = google_compute_instance.bench.zone
}

output "test_fqdn" {
  description = "FQDN used for DNS and CQL tests"
  value       = "${var.psc_endpoint_name}.${var.dns_domain}"
}
