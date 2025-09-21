# Host-only Algalon deployment example
# Creates monitoring host without worker nodes for hybrid/manual worker scenarios

terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "google"
      version = "~> 7.3"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Create network infrastructure
module "network" {
  source = "../../modules/network"

  network_name                     = var.network_name
  region                           = var.region
  subnet_cidr                      = var.subnet_cidr
  grafana_allowed_ips              = var.grafana_allowed_ips
  ssh_allowed_ips                  = var.ssh_allowed_ips
  enable_ssh_access                = var.enable_ssh_access
  enable_external_victoria_metrics = var.enable_external_victoria_metrics
}

# Create monitoring host only
module "monitoring_host" {
  source = "../../modules/algalon-host"

  instance_name = "${var.deployment_name}-monitoring"
  machine_type  = var.host_machine_type
  zone          = var.zones[0]
  network_name  = module.network.network_name
  subnet_name   = module.network.subnet_name

  # Monitoring configuration - empty targets for host-only deployment
  worker_targets   = var.worker_targets # Can be empty or provided manually
  cluster_name     = var.cluster_name
  environment_name = var.environment_name

  # Instance configuration
  boot_disk_size     = var.host_boot_disk_size
  enable_external_ip = var.enable_host_external_ip
  reserve_static_ip  = var.reserve_static_ip

  # Labels
  labels = var.labels
}