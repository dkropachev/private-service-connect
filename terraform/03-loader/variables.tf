variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-east1"
}

variable "zone" {
  description = "GCP zone for loader VM"
  type        = string
  default     = "us-east1-b"
}

variable "consumer_subnet_cidr" {
  description = "CIDR for the consumer subnet"
  type        = string
  default     = "10.1.1.0/24"
}

variable "psc_endpoint_ip" {
  description = "Static IP that will be used for the PSC endpoint (pre-configured in loader)"
  type        = string
  default     = "10.1.1.10"
}

variable "cql_username" {
  description = "CQL username for ScyllaDB"
  type        = string
  sensitive   = true
}

variable "cql_password" {
  description = "CQL password for ScyllaDB"
  type        = string
  sensitive   = true
}

variable "loader_machine_type" {
  description = "Machine type for the loader VM"
  type        = string
  default     = "e2-standard-4"
}

variable "port_base" {
  description = "Base port for per-node port mapping"
  type        = number
  default     = 9001
}

variable "node_private_ips" {
  description = "Private IPs of ScyllaDB nodes (for port mapping reference)"
  type        = list(string)
}
