# Algalon Host (Monitoring) module
# Creates monitoring host with Grafana, VictoriaMetrics, and VMAgent

# Data source for Container-Optimized OS image
data "google_compute_image" "cos_image" {
  family  = "cos-stable"
  project = "cos-cloud"
}

# Cloud-init configuration for monitoring host
locals {
  cloud_init_config = templatefile("${path.module}/cloud-init-host.yml.tpl", {
    algalon_targets     = var.worker_targets
    algalon_cluster     = var.cluster_name
    algalon_environment = var.environment_name
  })
}

resource "google_compute_instance" "algalon_host" {
  name         = var.instance_name
  machine_type = var.machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = data.google_compute_image.cos_image.self_link
      size  = var.boot_disk_size
      type  = var.boot_disk_type
    }
  }

  network_interface {
    network    = var.network_name
    subnetwork = var.subnet_name

    dynamic "access_config" {
      for_each = var.enable_external_ip ? [1] : []
      content {
        # Ephemeral external IP
      }
    }
  }

  metadata = {
    user-data                 = local.cloud_init_config
    google-logging-enabled    = "true"
    google-monitoring-enabled = "true"
  }

  tags = ["algalon-monitoring"]

  labels = merge(var.labels, {
    component   = "algalon-host"
    environment = var.environment_name
    cluster     = var.cluster_name
  })

  service_account {
    email  = var.service_account_email
    scopes = var.service_account_scopes
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Optional: Create a static external IP
resource "google_compute_address" "algalon_host_ip" {
  count  = var.create_static_ip ? 1 : 0
  name   = "${var.instance_name}-ip"
  region = var.region
}

# Attach static IP if created
resource "google_compute_instance" "algalon_host_with_static_ip" {
  count        = var.create_static_ip ? 1 : 0
  name         = "${var.instance_name}-static"
  machine_type = var.machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = data.google_compute_image.cos_image.self_link
      size  = var.boot_disk_size
      type  = var.boot_disk_type
    }
  }

  network_interface {
    network    = var.network_name
    subnetwork = var.subnet_name

    access_config {
      nat_ip = google_compute_address.algalon_host_ip[0].address
    }
  }

  metadata = {
    user-data                 = local.cloud_init_config
    google-logging-enabled    = "true"
    google-monitoring-enabled = "true"
  }

  tags = ["algalon-monitoring"]

  labels = merge(var.labels, {
    component   = "algalon-host"
    environment = var.environment_name
    cluster     = var.cluster_name
  })

  service_account {
    email  = var.service_account_email
    scopes = var.service_account_scopes
  }

  depends_on = [google_compute_instance.algalon_host]

  lifecycle {
    create_before_destroy = true
    replace_triggered_by = [
      google_compute_instance.algalon_host
    ]
  }
}