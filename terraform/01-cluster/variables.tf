variable "cluster_name" {
  description = "Name of the ScyllaDB cluster"
  type        = string
  default     = "psc-benchmark-cluster"
}

variable "scylla_version" {
  description = "ScyllaDB version to deploy"
  type        = string
  default     = "2024.2"
}

variable "region" {
  description = "GCP region for the cluster"
  type        = string
  default     = "us-east1"
}

variable "node_count" {
  description = "Number of ScyllaDB nodes"
  type        = number
  default     = 3
}

variable "node_type" {
  description = "Instance type for ScyllaDB nodes"
  type        = string
  default     = "n2-highmem-4"
}

variable "cidr_block" {
  description = "CIDR block for VPC peering"
  type        = string
  default     = "10.0.0.0/16"
}

variable "user_api_interface" {
  description = "API interface for CQL credentials"
  type        = string
  default     = "CQL"
}
