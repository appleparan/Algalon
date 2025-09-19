# Algalon Worker module
# Creates worker instances with GPU support for hardware metrics collection

# Data source for Container-Optimized OS image
data "google_compute_image" "cos_image" {
  family  = "cos-stable"
  project = "cos-cloud"
}

# Cloud-init configuration for worker instances
locals {
  cloud_init_config = templatefile("${path.module}/cloud-init-worker.yml.tpl", {
    all_smi_version  = var.all_smi_version
    all_smi_port     = var.all_smi_port
    all_smi_interval = var.all_smi_interval
  })
}

resource "google_compute_instance" "algalon_worker" {
  count        = var.instance_count
  name         = "${var.instance_name_prefix}-${count.index + 1}"
  machine_type = var.machine_type
  zone         = var.zones[count.index % length(var.zones)]

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
      count = var.gpu_count
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

  metadata = {
    user-data                 = local.cloud_init_config
    google-logging-enabled    = "true"
    google-monitoring-enabled = "true"
  }

  tags = ["algalon-worker"]

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

# Optional: Create managed instance group for auto-scaling
resource "google_compute_instance_template" "algalon_worker_template" {
  count        = var.create_instance_group ? 1 : 0
  name_prefix  = "${var.instance_name_prefix}-template-"
  machine_type = var.machine_type

  disk {
    source_image = data.google_compute_image.cos_image.self_link
    auto_delete  = true
    boot         = true
    disk_size_gb = var.boot_disk_size
    type         = var.boot_disk_type
  }

  # GPU configuration for template
  dynamic "guest_accelerator" {
    for_each = var.gpu_type != null ? [1] : []
    content {
      type  = var.gpu_type
      count = var.gpu_count
    }
  }

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

  metadata = {
    user-data                 = local.cloud_init_config
    google-logging-enabled    = "true"
    google-monitoring-enabled = "true"
  }

  tags = ["algalon-worker"]

  labels = merge(var.labels, {
    component   = "algalon-worker"
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

resource "google_compute_instance_group_manager" "algalon_worker_group" {
  count              = var.create_instance_group ? 1 : 0
  name               = "${var.instance_name_prefix}-group"
  base_instance_name = var.instance_name_prefix
  zone               = var.zones[0]

  version {
    instance_template = google_compute_instance_template.algalon_worker_template[0].id
  }

  target_size = var.instance_group_size

  named_port {
    name = "metrics"
    port = var.all_smi_port
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.algalon_worker_health[0].id
    initial_delay_sec = 300
  }
}

# Health check for managed instance group
resource "google_compute_health_check" "algalon_worker_health" {
  count               = var.create_instance_group ? 1 : 0
  name                = "${var.instance_name_prefix}-health"
  check_interval_sec  = 30
  timeout_sec         = 10
  healthy_threshold   = 2
  unhealthy_threshold = 3

  http_health_check {
    port         = var.all_smi_port
    request_path = "/metrics"
  }
}

# Autoscaler for managed instance group
resource "google_compute_autoscaler" "algalon_worker_autoscaler" {
  count  = var.create_instance_group && var.enable_autoscaling ? 1 : 0
  name   = "${var.instance_name_prefix}-autoscaler"
  zone   = var.zones[0]
  target = google_compute_instance_group_manager.algalon_worker_group[0].id

  autoscaling_policy {
    max_replicas    = var.autoscaling_max_replicas
    min_replicas    = var.autoscaling_min_replicas
    cooldown_period = var.autoscaling_cooldown

    cpu_utilization {
      target = var.autoscaling_cpu_target
    }
  }
}