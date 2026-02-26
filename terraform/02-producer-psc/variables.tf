variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-east1"
}

variable "scylla_vpc_name" {
  description = "Name of the existing ScyllaDB Cloud VPC network"
  type        = string
}

variable "scylla_subnet_name" {
  description = "Name of the existing ScyllaDB node subnet (for ILB placement)"
  type        = string
}

variable "node_instances" {
  description = "ScyllaDB node VM instances"
  type = list(object({
    name = string
    zone = string
    ip   = string
  }))
}

variable "cql_port_base" {
  description = "Base port for CQL per-node port mapping (node N maps to cql_port_base + N)"
  type        = number
  default     = 9001
}

variable "ssl_cql_port_base" {
  description = "Base port for SSL CQL per-node port mapping (node N maps to ssl_cql_port_base + N)"
  type        = number
  default     = 9101
}

variable "psc_nat_subnet_cidr" {
  description = "CIDR for the PSC NAT subnet"
  type        = string
  default     = "10.0.201.0/24"
}

variable "dns_domain" {
  description = "DNS domain for the PSC service attachment (e.g. cluster-1.scylladb.com). Requires domain verification in GCP."
  type        = string
  default     = ""
}