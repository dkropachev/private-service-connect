# --- Consumer VPC ---

resource "google_compute_network" "consumer" {
  name                    = "consumer-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "consumer" {
  name          = "consumer-subnet"
  ip_cidr_range = var.consumer_subnet_cidr
  region        = var.region
  network       = google_compute_network.consumer.id
}

# --- Firewall Rules ---

resource "google_compute_firewall" "consumer_iap_ssh" {
  name    = "consumer-allow-iap-ssh"
  network = google_compute_network.consumer.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
}

resource "google_compute_firewall" "consumer_internal" {
  name    = "consumer-allow-internal"
  network = google_compute_network.consumer.id

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [var.consumer_subnet_cidr]
}

# --- Cloud NAT (for docker pull) ---

resource "google_compute_router" "consumer" {
  name    = "consumer-router"
  network = google_compute_network.consumer.id
  region  = var.region
}

resource "google_compute_router_nat" "consumer" {
  name                               = "consumer-nat"
  router                             = google_compute_router.consumer.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# --- Loader VM ---

locals {
  workload_content = file("${path.module}/../../workloads/basic_read_write.rn")

  loader_startup_script = templatefile("${path.module}/templates/loader-startup.sh.tpl", {
    cql_username     = var.cql_username
    cql_password     = var.cql_password
    psc_endpoint_ip  = var.psc_endpoint_ip
    port_base        = var.port_base
    node_private_ips = var.node_private_ips
    workload_content = local.workload_content
  })
}

resource "google_compute_instance" "loader" {
  name         = "latte-loader"
  machine_type = var.loader_machine_type
  zone         = var.zone

  tags = ["loader"]

  labels = {
    owner = "psc-poc"
  }

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 30
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.consumer.self_link
    access_config {}
  }

  metadata_startup_script = local.loader_startup_script

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
  }
}
