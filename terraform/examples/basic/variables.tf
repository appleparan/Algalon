variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "zones" {
  description = "List of GCP zones"
  type        = list(string)
  default     = ["us-central1-a", "us-central1-b"]
}

variable "deployment_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "algalon"
}

variable "cluster_name" {
  description = "Cluster name for labeling"
  type        = string
  default     = "production"
}

variable "environment_name" {
  description = "Environment name"
  type        = string
  default     = "gpu-cluster"
}

# Network configuration
variable "network_name" {
  description = "Name of the VPC network"
  type        = string
  default     = "algalon-network"
}

variable "subnet_cidr" {
  description = "CIDR block for the subnet"
  type        = string
  default     = "10.1.0.0/16"
}

variable "grafana_allowed_ips" {
  description = "IP ranges allowed to access Grafana"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ssh_allowed_ips" {
  description = "IP ranges allowed SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_ssh_access" {
  description = "Enable SSH access to instances"
  type        = bool
  default     = true
}

variable "enable_external_victoria_metrics" {
  description = "Enable external access to VictoriaMetrics"
  type        = bool
  default     = false
}

# Worker configuration
variable "worker_count" {
  description = "Number of worker instances"
  type        = number
  default     = 2
}

variable "worker_machine_type" {
  description = "Machine type for worker instances"
  type        = string
  default     = "n1-standard-1"
}

variable "gpu_type" {
  description = "GPU type (e.g., nvidia-tesla-t4, nvidia-tesla-v100)"
  type        = string
  default     = "nvidia-tesla-t4"
}

variable "gpu_count" {
  description = "Number of GPUs per worker"
  type        = number
  default     = 1
}

variable "worker_boot_disk_size" {
  description = "Worker boot disk size in GB"
  type        = number
  default     = 30
}

variable "enable_worker_external_ip" {
  description = "Enable external IP for workers"
  type        = bool
  default     = false
}

variable "use_preemptible_workers" {
  description = "Use preemptible instances for workers"
  type        = bool
  default     = false
}

# all-smi configuration
variable "all_smi_version" {
  description = "all-smi version"
  type        = string
  default     = "v0.9.0"
}

variable "all_smi_port" {
  description = "all-smi metrics port"
  type        = number
  default     = 9090
}

variable "all_smi_interval" {
  description = "Metrics collection interval in seconds"
  type        = number
  default     = 5
}

# Host configuration
variable "host_machine_type" {
  description = "Machine type for monitoring host"
  type        = string
  default     = "n1-standard-2"
}

variable "host_boot_disk_size" {
  description = "Host boot disk size in GB"
  type        = number
  default     = 50
}

variable "enable_host_external_ip" {
  description = "Enable external IP for monitoring host"
  type        = bool
  default     = true
}

variable "reserve_static_ip" {
  description = "Reserve static IP for monitoring host"
  type        = bool
  default     = false
}

# Labels
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project    = "algalon"
    managed_by = "terraform"
  }
}