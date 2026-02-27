data "google_compute_network" "this" {
  name = var.network
}

data "google_compute_subnetwork" "this" {
  name   = var.subnet
  region = var.region
}

resource "google_compute_instance" "bench" {
  name         = "scylla-bench"
  machine_type = var.machine_type
  zone         = var.zone

  tags   = ["bench"]
  labels = {
    owner = var.owner
  }

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
    }
  }

  network_interface {
    subnetwork = data.google_compute_subnetwork.this.self_link
    access_config {}
  }

  metadata_startup_script = templatefile("${path.module}/templates/bench-startup.sh.tpl", {
    psc_endpoint_name = var.psc_endpoint_name
    dns_domain        = var.dns_domain
    cql_ports         = var.cql_ports
  })

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
  }
}
