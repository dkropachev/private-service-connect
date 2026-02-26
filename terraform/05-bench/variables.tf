variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-west1"
}

variable "zone" {
  description = "GCP zone for bench VM"
  type        = string
  default     = "us-west1-b"
}

variable "network" {
  description = "VPC network name"
  type        = string
  default     = "default"
}

variable "subnet" {
  description = "Subnet name"
  type        = string
  default     = "default"
}

variable "machine_type" {
  description = "Machine type for the bench VM"
  type        = string
  default     = "e2-small"
}

variable "dns_domain" {
  description = "PSC DNS domain (e.g. dk-test.duckdns.org)"
  type        = string
}

variable "psc_endpoint_name" {
  description = "Name of the PSC endpoint forwarding rule (used as DNS subdomain)"
  type        = string
  default     = "scylladb-psc-endpoint"
}

variable "cql_ports" {
  description = "List of CQL ports to test connectivity on"
  type        = list(number)
  default     = [9001, 9002, 9003]
}

variable "owner" {
  description = "Owner label (required by org policy)"
  type        = string
  default     = "dmitry-kropachev"
}
