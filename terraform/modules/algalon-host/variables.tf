variable "instance_name" {
  description = "Name of the monitoring host instance"
  type        = string
  default     = "algalon-monitoring-host"
}

variable "machine_type" {
  description = "Machine type for the monitoring host"
  type        = string
  default     = "n1-standard-2"
}

variable "zone" {
  description = "GCP zone for the instance"
  type        = string
  default     = "us-central1-a"
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "network_name" {
  description = "Name of the VPC network"
  type        = string
}

variable "subnet_name" {
  description = "Name of the subnet"
  type        = string
}

variable "worker_targets" {
  description = "Comma-separated list of worker targets (host:port)"
  type        = string
  default     = "localhost:9090"
}

variable "cluster_name" {
  description = "Name of the cluster for labeling"
  type        = string
  default     = "production"
}

variable "environment_name" {
  description = "Environment name for labeling"
  type        = string
  default     = "gpu-cluster"
}

variable "boot_disk_size" {
  description = "Size of the boot disk in GB"
  type        = number
  default     = 50
}

variable "boot_disk_type" {
  description = "Type of the boot disk"
  type        = string
  default     = "pd-standard"
}

variable "enable_external_ip" {
  description = "Whether to assign an external IP to the instance"
  type        = bool
  default     = true
}

variable "create_static_ip" {
  description = "Whether to create a static external IP"
  type        = bool
  default     = false
}

variable "service_account_email" {
  description = "Service account email for the instance"
  type        = string
  default     = null
}

variable "service_account_scopes" {
  description = "Service account scopes for the instance"
  type        = list(string)
  default = [
    "https://www.googleapis.com/auth/cloud-platform"
  ]
}

variable "labels" {
  description = "Labels to apply to the instance"
  type        = map(string)
  default     = {}
}