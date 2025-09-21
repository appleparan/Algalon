# Algalon Host (Monitoring) module
# Creates monitoring host with Grafana, VictoriaMetrics, and VMAgent

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.3"
    }
  }
}

# Data source for Container-Optimized OS image
data "google_compute_image" "cos_image" {
  family  = "cos-arm64-121-lts"
  project = "cos-cloud"
}

# Optional: Reserve a static external IP (only if explicitly requested)
resource "google_compute_address" "algalon_host_ip" {
  count  = var.reserve_static_ip ? 1 : 0
  name   = "${var.instance_name}-ip"
  region = var.region
}

# Cloud-init configuration for monitoring host
locals {
  cloud_init_config = templatefile("${path.module}/cloud-init-host.yml.tpl", {
    algalon_targets     = var.worker_targets
    algalon_cluster     = var.cluster_name
    algalon_environment = var.environment_name
  })
}

# checkov:enforce=CKV_GCP_32:Host instances must block project-wide SSH keys for security
resource "google_compute_instance" "algalon_host" {
  #   count = length(data.google_compute_zones.available.names)
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

    # Setup access_config only if external IP is enabled
    dynamic "access_config" {
      for_each = var.enable_external_ip ? [1] : []
      content {
        # Use only if static IP is reserved; otherwise, GCP will assign an ephemeral IP
        nat_ip = var.reserve_static_ip ? google_compute_address.algalon_host_ip[0].address : null
      }
    }
  }

  metadata = {
    user-data                 = local.cloud_init_config
    google-logging-enabled    = "true"
    google-monitoring-enabled = "true"
    block-project-ssh-keys    = true
  }

  tags = concat(
    ["algalon-monitoring", "observability"],
    var.reserve_static_ip ? ["reserved-ip"] : ["auto-ip"]
  )

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
