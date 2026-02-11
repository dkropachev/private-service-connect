variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "network" {
  description = "Self-link or name of the consumer VPC network"
  type        = string
}

variable "subnet" {
  description = "Self-link or name of the consumer subnet"
  type        = string
}

variable "service_attachment_id" {
  description = "Self-link of the producer PSC service attachment"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "scylla-psc"
}

variable "dns_domain" {
  description = "Private DNS domain for the cluster (e.g. cluster-1.scylladb.com)"
  type        = string
}

variable "dns_networks" {
  description = "List of network self-links that can resolve the private DNS zone"
  type        = list(string)
  default     = []
}

variable "nodes" {
  description = "Node DNS entries — each node gets a DNS record pointing to the shared PSC IP"
  type = list(object({
    name = string
    port = number
  }))
}
