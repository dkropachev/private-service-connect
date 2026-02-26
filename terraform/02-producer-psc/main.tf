# --- Reference existing ScyllaDB VPC and subnet ---

data "google_compute_network" "scylla" {
  name = var.scylla_vpc_name
}

data "google_compute_subnetwork" "scylla" {
  name   = var.scylla_subnet_name
  region = var.region
}

# --- PSC NAT Subnet ---

resource "google_compute_subnetwork" "psc_nat" {
  name          = "psc-nat-subnet"
  ip_cidr_range = var.psc_nat_subnet_cidr
  region        = var.region
  network       = data.google_compute_network.scylla.id
  purpose       = "PRIVATE_SERVICE_CONNECT"
}

# --- Firewall Rules ---

resource "google_compute_firewall" "health_check" {
  name    = "psc-allow-health-check"
  network = data.google_compute_network.scylla.id

  allow {
    protocol = "tcp"
    ports    = ["9042", "9142"]
  }

  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
}

resource "google_compute_firewall" "psc_nat" {
  name    = "psc-allow-nat-to-nodes"
  network = data.google_compute_network.scylla.id

  allow {
    protocol = "tcp"
    ports    = ["9042", "9142"]
  }

  source_ranges = [var.psc_nat_subnet_cidr]
}

# --- Port Mapping NEG ---

resource "google_compute_region_network_endpoint_group" "port_mapping" {
  provider              = google-beta
  name                  = "scylladb-port-mapping-neg"
  region                = var.region
  network               = data.google_compute_network.scylla.self_link
  subnetwork            = data.google_compute_subnetwork.scylla.self_link
  network_endpoint_type = "GCE_VM_IP_PORTMAP"
}

# CQL endpoints: client_port = cql_port_base + node_index
resource "google_compute_region_network_endpoint" "cql" {
  provider = google-beta

  for_each = { for idx, inst in var.node_instances : idx => inst }

  region_network_endpoint_group = google_compute_region_network_endpoint_group.port_mapping.name
  region                        = var.region

  instance                = "projects/${var.gcp_project_id}/zones/${each.value.zone}/instances/${each.value.name}"
  ip_address              = each.value.ip
  port                    = 9042
  client_destination_port = var.cql_port_base + each.key
}

# SSL CQL endpoints: client_port = ssl_cql_port_base + node_index
resource "google_compute_region_network_endpoint" "ssl_cql" {
  provider = google-beta

  for_each = { for idx, inst in var.node_instances : idx => inst }

  region_network_endpoint_group = google_compute_region_network_endpoint_group.port_mapping.name
  region                        = var.region

  instance                = "projects/${var.gcp_project_id}/zones/${each.value.zone}/instances/${each.value.name}"
  ip_address              = each.value.ip
  port                    = 9142
  client_destination_port = var.ssl_cql_port_base + each.key
}

# --- Internal Backend Service (no health check, matches production PSC) ---

resource "google_compute_region_backend_service" "scylla" {
  name                  = "scylladb-backend"
  region                = var.region
  protocol              = "TCP"
  load_balancing_scheme = "INTERNAL"
  network               = data.google_compute_network.scylla.self_link

  backend {
    group          = google_compute_region_network_endpoint_group.port_mapping.self_link
    balancing_mode = "CONNECTION"
  }
}

# --- Internal Forwarding Rule (ILB) ---

resource "google_compute_forwarding_rule" "ilb" {
  name                  = "scylladb-ilb"
  region                = var.region
  load_balancing_scheme = "INTERNAL"
  backend_service       = google_compute_region_backend_service.scylla.id
  ip_protocol           = "TCP"
  all_ports             = true
  network               = data.google_compute_network.scylla.self_link
  subnetwork            = data.google_compute_subnetwork.scylla.self_link
}

# --- PSC Service Attachment ---

resource "google_compute_service_attachment" "this" {
  name        = "scylladb-psc-attachment"
  region      = var.region
  description = "PSC service attachment for ScyllaDB per-node port mapping"

  enable_proxy_protocol    = false
  connection_preference    = "ACCEPT_AUTOMATIC"
  reconcile_connections    = false

  domain_names = var.dns_domain != "" ? ["${trimsuffix(var.dns_domain, ".")}."] : []

  target_service = google_compute_forwarding_rule.ilb.id

  nat_subnets = [google_compute_subnetwork.psc_nat.id]
}
