# Host-only deployment variables

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "zones" {
  description = "List of zones for deployment"
  type        = list(string)
  default     = ["us-central1-a"]
}

variable "deployment_name" {
  description = "Name prefix for deployed resources"
  type        = string
  default     = "algalon-host-only"
}

# Network configuration
variable "network_name" {
  description = "Name of the VPC network"
  type        = string
  default     = "algalon-host-network"
}

variable "subnet_cidr" {
  description = "CIDR range for the subnet"
  type        = string
  default     = "10.0.0.0/24"
}

# Security configuration
variable "grafana_allowed_ips" {
  description = "List of IP ranges allowed to access Grafana"
  type        = list(string)
  default     = ["35.235.240.0/20"] # Restrict in production
}

variable "ssh_allowed_ips" {
  description = "List of IP ranges allowed for SSH access"
  type        = list(string)
  default     = ["35.235.240.0/20"] # Restrict in production
}

variable "enable_ssh_access" {
  description = "Whether to enable SSH access to instances"
  type        = bool
  default     = true
}

variable "enable_external_victoria_metrics" {
  description = "Whether to allow external access to VictoriaMetrics"
  type        = bool
  default     = false
}

# Host configuration
variable "host_machine_type" {
  description = "Machine type for the monitoring host"
  type        = string
  default     = "c4a-standard-8"
}

variable "host_boot_disk_size" {
  description = "Size of the host boot disk in GB"
  type        = number
  default     = 50
}

variable "enable_host_external_ip" {
  description = "Whether to assign an external IP to the host"
  type        = bool
  default     = true
}

variable "reserve_static_ip" {
  description = "Whether to reserve a static external IP for the host"
  type        = bool
  default     = true # Recommended for production host-only deployments
}

# Worker targets (optional for manual worker registration)
variable "worker_targets" {
  description = "Comma-separated list of worker targets (host:port). Leave empty for host-only deployment, add manually later"
  type        = string
  default     = ""
}

# Cluster configuration
variable "cluster_name" {
  description = "Name of the cluster for labeling"
  type        = string
  default     = "production"
}

variable "environment_name" {
  description = "Environment name for labeling"
  type        = string
  default     = "host-only"
}

# Labels
variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default = {
    component  = "algalon-host"
    deployment = "host-only"
    managed-by = "terraform"
  }
}