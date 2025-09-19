variable "instance_name_prefix" {
  description = "Prefix for worker instance names"
  type        = string
  default     = "algalon-worker"
}

variable "instance_count" {
  description = "Number of worker instances to create"
  type        = number
  default     = 1
}

variable "machine_type" {
  description = "Machine type for worker instances"
  type        = string
  default     = "n1-standard-1"
}

variable "zones" {
  description = "List of GCP zones for worker instances"
  type        = list(string)
  default     = ["us-central1-a"]
}

variable "network_name" {
  description = "Name of the VPC network"
  type        = string
}

variable "subnet_name" {
  description = "Name of the subnet"
  type        = string
}

variable "gpu_type" {
  description = "Type of GPU to attach (e.g., nvidia-tesla-t4, nvidia-tesla-v100)"
  type        = string
  default     = null
}

variable "gpu_count" {
  description = "Number of GPUs to attach per instance"
  type        = number
  default     = 1
}

variable "all_smi_version" {
  description = "Version of all-smi to install"
  type        = string
  default     = "v0.9.0"
}

variable "all_smi_port" {
  description = "Port for all-smi metrics endpoint"
  type        = number
  default     = 9090
}

variable "all_smi_interval" {
  description = "Metrics collection interval in seconds"
  type        = number
  default     = 5
}

variable "boot_disk_size" {
  description = "Size of the boot disk in GB"
  type        = number
  default     = 30
}

variable "boot_disk_type" {
  description = "Type of the boot disk"
  type        = string
  default     = "pd-standard"
}

variable "enable_external_ip" {
  description = "Whether to assign external IP to instances"
  type        = bool
  default     = false
}

variable "preemptible" {
  description = "Whether to create preemptible instances"
  type        = bool
  default     = false
}

variable "service_account_email" {
  description = "Service account email for instances"
  type        = string
  default     = null
}

variable "service_account_scopes" {
  description = "Service account scopes for instances"
  type        = list(string)
  default = [
    "https://www.googleapis.com/auth/cloud-platform"
  ]
}

variable "labels" {
  description = "Labels to apply to instances"
  type        = map(string)
  default     = {}
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

# Managed Instance Group variables
variable "create_instance_group" {
  description = "Whether to create a managed instance group"
  type        = bool
  default     = false
}

variable "instance_group_size" {
  description = "Target size for the managed instance group"
  type        = number
  default     = 3
}

variable "enable_autoscaling" {
  description = "Whether to enable autoscaling for the instance group"
  type        = bool
  default     = false
}

variable "autoscaling_min_replicas" {
  description = "Minimum number of replicas for autoscaling"
  type        = number
  default     = 1
}

variable "autoscaling_max_replicas" {
  description = "Maximum number of replicas for autoscaling"
  type        = number
  default     = 10
}

variable "autoscaling_cooldown" {
  description = "Cooldown period for autoscaling in seconds"
  type        = number
  default     = 300
}

variable "autoscaling_cpu_target" {
  description = "Target CPU utilization for autoscaling"
  type        = number
  default     = 0.8
}