terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  backend_ports = distinct([for n in var.nodes : n.backend_port])
}

# --- PSC NAT Subnet ---

resource "google_compute_subnetwork" "psc_nat" {
  name          = var.nat_subnet_name
  ip_cidr_range = var.nat_subnet_cidr
  region        = var.region
  network       = var.network
  purpose       = "PRIVATE_SERVICE_CONNECT"
}

# --- Port Mapping NEG ---

resource "google_compute_region_network_endpoint_group" "portmap" {
  name                  = "${var.name_prefix}-portmap-neg"
  region                = var.region
  network               = var.network
  subnetwork            = var.subnet
  network_endpoint_type = "GCE_VM_IP_PORTMAP"
}

resource "google_compute_region_network_endpoint" "node" {
  count = length(var.nodes)

  region                        = var.region
  region_network_endpoint_group = google_compute_region_network_endpoint_group.portmap.name
  instance                      = var.nodes[count.index].instance_self_link
  port                          = var.nodes[count.index].backend_port
  client_destination_port       = var.nodes[count.index].client_port
}

# --- Backend Service ---

resource "google_compute_region_backend_service" "portmap" {
  name                  = "${var.name_prefix}-backend"
  region                = var.region
  protocol              = "TCP"
  load_balancing_scheme = "INTERNAL"

  backend {
    group = google_compute_region_network_endpoint_group.portmap.id
  }
}

# --- Forwarding Rule ---

resource "google_compute_forwarding_rule" "portmap" {
  name                  = "${var.name_prefix}-fr"
  region                = var.region
  load_balancing_scheme = "INTERNAL"
  network               = var.network
  subnetwork            = var.subnet
  ip_protocol           = "TCP"
  all_ports             = true
  backend_service       = google_compute_region_backend_service.portmap.id
}

# --- PSC Service Attachment ---

resource "google_compute_service_attachment" "psc" {
  name                  = "${var.name_prefix}-sa"
  region                = var.region
  connection_preference = var.connection_preference

  target_service = google_compute_forwarding_rule.portmap.id

  nat_subnets = [google_compute_subnetwork.psc_nat.id]

  dynamic "consumer_accept_lists" {
    for_each = var.consumer_accept_list
    content {
      project_id_or_num = consumer_accept_lists.value.project_id
      connection_limit  = consumer_accept_lists.value.connection_limit
    }
  }
}

# --- Firewall Rules ---

resource "google_compute_firewall" "allow_backend_ports" {
  for_each = toset([for p in local.backend_ports : tostring(p)])

  name    = "${var.name_prefix}-allow-${each.value}"
  network = var.network

  direction = "INGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
    ports    = [each.value]
  }

  source_ranges = concat(
    [var.nat_subnet_cidr],
    var.firewall_source_cidrs,
  )
}
