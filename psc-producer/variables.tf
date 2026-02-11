variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "network" {
  description = "Self-link or name of the ScyllaDB VPC network"
  type        = string
}

variable "subnet" {
  description = "Self-link or name of the ScyllaDB subnet"
  type        = string
}

variable "nat_subnet_cidr" {
  description = "CIDR range for the PSC NAT subnet"
  type        = string
  default     = "10.0.201.0/24"
}

variable "nat_subnet_name" {
  description = "Name for the PSC NAT subnet"
  type        = string
  default     = "psc-nat-portmap"
}

variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "scylla-psc"
}

variable "nodes" {
  description = "List of ScyllaDB nodes with port mappings"
  type = list(object({
    instance_self_link    = string
    client_port           = number
    backend_port          = number
  }))
}

variable "connection_preference" {
  description = "PSC connection preference: ACCEPT_AUTOMATIC or ACCEPT_MANUAL"
  type        = string
  default     = "ACCEPT_AUTOMATIC"
}

variable "consumer_accept_list" {
  description = "List of project IDs to accept connections from (when using ACCEPT_MANUAL)"
  type = list(object({
    project_id       = string
    connection_limit = number
  }))
  default = []
}

variable "firewall_source_cidrs" {
  description = "Source CIDRs to allow through firewall for backend ports (NAT subnet is added automatically)"
  type        = list(string)
  default     = []
}
