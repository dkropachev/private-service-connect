output "cluster_id" {
  description = "ScyllaDB Cloud cluster ID"
  value       = scylladbcloud_cluster.this.cluster_id
}

output "datacenter" {
  description = "ScyllaDB datacenter name"
  value       = scylladbcloud_cluster.this.datacenter
}

output "node_private_ips" {
  description = "Private IPs of ScyllaDB nodes"
  value       = scylladbcloud_cluster.this.node_private_ips
}

output "cql_username" {
  description = "CQL username"
  value       = data.scylladbcloud_cql_auth.this.username
  sensitive   = true
}

output "cql_password" {
  description = "CQL password"
  value       = data.scylladbcloud_cql_auth.this.password
  sensitive   = true
}
