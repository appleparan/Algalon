variable "network_name" {
  description = "Name of the VPC network"
  type        = string
  default     = "algalon-network"
}

variable "region" {
  description = "GCP region for the subnet"
  type        = string
  default     = "us-central1"
}

variable "subnet_cidr" {
  description = "CIDR block for the subnet"
  type        = string
  default     = "10.1.0.0/16"
}

variable "grafana_allowed_ips" {
  description = "List of IP ranges allowed to access Grafana"
  type        = list(string)
  default     = ["35.235.240.0/20"]
  validation {
    condition = alltrue([
      for cidr in var.grafana_allowed_ips :
      !(cidr == "0.0.0.0/0" || cidr == "::/0")
    ])
    error_message = "grafana_allowed_ips must not include 0.0.0.0/0 or ::/0."
  }
}

variable "victoria_metrics_allowed_ips" {
  description = "List of IP ranges allowed to access VictoriaMetrics"
  type        = list(string)
  default     = ["35.235.240.0/20"]
  validation {
    condition = alltrue([
      for cidr in var.victoria_metrics_allowed_ips :
      !(cidr == "0.0.0.0/0" || cidr == "::/0")
    ])
    error_message = "victoria_metrics_allowed_ips must not include 0.0.0.0/0 or ::/0."
  }
}

variable "ssh_allowed_ips" {
  description = "List of IP ranges allowed SSH access"
  type        = list(string)
  default     = ["35.235.240.0/20"]
  validation {
    condition = alltrue([
      for cidr in var.ssh_allowed_ips :
      !(cidr == "0.0.0.0/0" || cidr == "::/0")
    ])
    error_message = "ssh_allowed_ips must not include 0.0.0.0/0 or ::/0."
  }
}

variable "worker_ports" {
  description = "List of ports used by worker nodes for metrics"
  type        = list(string)
  default     = ["9090"]
}

variable "enable_external_victoria_metrics" {
  description = "Whether to allow external access to VictoriaMetrics"
  type        = bool
  default     = false
}

variable "enable_ssh_access" {
  description = "Whether to allow SSH access to instances"
  type        = bool
  default     = true
}