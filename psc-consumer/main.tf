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
  dns_zone_name = replace(var.dns_domain, ".", "-")
  dns_networks  = length(var.dns_networks) > 0 ? var.dns_networks : [var.network]
}

# --- Static IP for PSC Endpoint ---

resource "google_compute_address" "psc_endpoint" {
  name         = "${var.name_prefix}-endpoint-ip"
  region       = var.region
  subnetwork   = var.subnet
  address_type = "INTERNAL"
  purpose      = "GCE_ENDPOINT"
}

# --- PSC Consumer Endpoint ---

resource "google_compute_forwarding_rule" "psc_endpoint" {
  name                  = "${var.name_prefix}-endpoint"
  region                = var.region
  network               = var.network
  ip_address            = google_compute_address.psc_endpoint.id
  load_balancing_scheme = ""

  target = var.service_attachment_id
}

# --- Private DNS Zone ---

resource "google_dns_managed_zone" "cluster" {
  name        = local.dns_zone_name
  dns_name    = "${var.dns_domain}."
  description = "Private DNS for ScyllaDB PSC endpoints"
  visibility  = "private"

  dynamic "private_visibility_config" {
    for_each = [1]
    content {
      dynamic "networks" {
        for_each = local.dns_networks
        content {
          network_url = networks.value
        }
      }
    }
  }
}

# --- DNS A Record: root domain ---

resource "google_dns_record_set" "cluster_root" {
  managed_zone = google_dns_managed_zone.cluster.name
  name         = "${var.dns_domain}."
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_address.psc_endpoint.address]
}

# --- DNS A Records: per-node ---

resource "google_dns_record_set" "node" {
  count = length(var.nodes)

  managed_zone = google_dns_managed_zone.cluster.name
  name         = "${var.nodes[count.index].name}.${var.dns_domain}."
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_address.psc_endpoint.address]
}
