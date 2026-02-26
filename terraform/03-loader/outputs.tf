output "consumer_vpc_id" {
  description = "ID of the consumer VPC"
  value       = google_compute_network.consumer.id
}

output "consumer_subnet_id" {
  description = "ID of the consumer subnet"
  value       = google_compute_subnetwork.consumer.id
}

output "loader_vm_name" {
  description = "Name of the loader VM"
  value       = google_compute_instance.loader.name
}

output "loader_vm_zone" {
  description = "Zone of the loader VM"
  value       = google_compute_instance.loader.zone
}
