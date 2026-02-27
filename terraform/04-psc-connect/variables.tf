variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-east1"
}

variable "service_attachment_self_link" {
  description = "Self link of the PSC service attachment (from stage 02)"
  type        = string
}

variable "consumer_vpc_id" {
  description = "ID of the consumer VPC (from stage 03)"
  type        = string
}

variable "consumer_subnet_id" {
  description = "ID of the consumer subnet (from stage 03)"
  type        = string
}

variable "psc_endpoint_name" {
  description = "Name of the PSC endpoint forwarding rule (becomes the DNS subdomain)"
  type        = string
  default     = "scylladb-psc-endpoint"
}

variable "psc_endpoint_ip" {
  description = "Static IP for the PSC endpoint"
  type        = string
  default     = "10.1.1.10"
}

variable "port_base" {
  description = "Base port for per-node port mapping"
  type        = number
  default     = 9001
}

variable "node_private_ips" {
  description = "Private IPs of ScyllaDB nodes (for port mapping output)"
  type        = list(string)
}
