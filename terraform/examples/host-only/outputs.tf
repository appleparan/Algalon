# Host-only deployment outputs

output "grafana_url" {
  description = "URL to access Grafana dashboard"
  value       = module.monitoring_host.grafana_url
}

output "victoria_metrics_url" {
  description = "URL to access VictoriaMetrics"
  value       = module.monitoring_host.victoria_metrics_url
}

output "monitoring_host_external_ip" {
  description = "External IP address of the monitoring host"
  value       = module.monitoring_host.external_ip
}

output "monitoring_host_internal_ip" {
  description = "Internal IP address of the monitoring host"
  value       = module.monitoring_host.internal_ip
}

output "ssh_command" {
  description = "Command to SSH into the monitoring host"
  value       = module.monitoring_host.ssh_command
}

output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    deployment_name   = var.deployment_name
    host_machine_type = var.host_machine_type
    network_name      = var.network_name
    worker_targets    = var.worker_targets != "" ? var.worker_targets : "none (host-only deployment)"
    grafana_url       = module.monitoring_host.grafana_url
  }
}

output "worker_registration_info" {
  description = "Information for manually registering workers"
  value = {
    monitoring_host_ip  = module.monitoring_host.external_ip
    instructions        = "To add workers manually, update the VMAgent targets configuration or use the provided registration script"
    config_location     = "/opt/Algalon/algalon_host/node/targets/all-smi-targets.yml"
    registration_script = "Use scripts/register-worker.sh on the monitoring host"
  }
}