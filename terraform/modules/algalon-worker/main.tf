# Algalon Worker module
# Creates worker instances with GPU support for hardware metrics collection

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
  family  = "cos-stable"
  project = "cos-cloud"
}

# Cloud-init configuration for worker instances
locals {
  # Calculate required number of instances based on total GPU count
  instance_count = ceil(var.total_gpu_count / var.gpus_per_instance)

  cloud_init_config = templatefile("${path.module}/cloud-init-worker.yml.tpl", {
    all_smi_version  = var.all_smi_version
    all_smi_port     = var.all_smi_port
    all_smi_interval = var.all_smi_interval
  })

  common_metadata = {
    user-data                 = local.cloud_init_config
    google-logging-enabled    = "true"
    google-monitoring-enabled = "true"
  }

  common_labels = merge(var.labels, {
    component   = "algalon-worker"
    environment = var.environment_name
    cluster     = var.cluster_name
  })

  common_tags = ["algalon-worker"]

  network_interface_config = {
    network    = var.network_name
    subnetwork = var.subnet_name
  }

  scheduling_config = {
    on_host_maintenance = var.gpu_type != null ? "TERMINATE" : "MIGRATE"
    preemptible         = var.preemptible
  }

  service_account_config = {
    email  = var.service_account_email
    scopes = var.service_account_scopes
  }
}

# checkov:skip=CKV_GCP_32:Worker instances need project-wide SSH keys for automated management
resource "google_compute_instance" "algalon_worker" {
  count        = local.instance_count
  name         = "${var.instance_name_prefix}-${count.index + 1}"
  machine_type = var.machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = data.google_compute_image.cos_image.self_link
      size  = var.boot_disk_size
      type  = var.boot_disk_type
    }
  }

  # GPU configuration
  dynamic "guest_accelerator" {
    for_each = var.gpu_type != null ? [1] : []
    content {
      type  = var.gpu_type
      count = var.gpus_per_instance
    }
  }

  # GPU instances must use TERMINATE scheduling
  scheduling {
    on_host_maintenance = var.gpu_type != null ? "TERMINATE" : "MIGRATE"
    preemptible         = var.preemptible
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

  metadata = local.common_metadata
  tags     = local.common_tags

  labels = merge(var.labels, {
    component    = "algalon-worker"
    environment  = var.environment_name
    cluster      = var.cluster_name
    worker_index = tostring(count.index + 1)
  })

  service_account {
    email  = var.service_account_email
    scopes = var.service_account_scopes
  }

  lifecycle {
    create_before_destroy = true
  }
}

