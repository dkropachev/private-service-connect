# --- PSC Endpoint ---

resource "google_compute_address" "psc_endpoint" {
  name         = "psc-endpoint-ip"
  region       = var.region
  subnetwork   = var.consumer_subnet_id
  address_type = "INTERNAL"
  address      = var.psc_endpoint_ip
  purpose      = "GCE_ENDPOINT"
}

resource "google_compute_forwarding_rule" "psc_endpoint" {
  name                  = "psc-endpoint"
  region                = var.region
  load_balancing_scheme = ""
  target                = var.service_attachment_self_link
  ip_address            = google_compute_address.psc_endpoint.id
  network               = var.consumer_vpc_id
}
