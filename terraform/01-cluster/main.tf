resource "scylladbcloud_cluster" "this" {
  name               = var.cluster_name
  cloud              = "GCE"
  region             = var.region
  node_count         = var.node_count
  node_type          = var.node_type
  scylla_version     = var.scylla_version
  cidr_block         = var.cidr_block
  enable_vpc_peering = true
  user_api_interface = var.user_api_interface
}

data "scylladbcloud_cql_auth" "this" {
  cluster_id = scylladbcloud_cluster.this.cluster_id
  depends_on = [scylladbcloud_cluster.this]
}
