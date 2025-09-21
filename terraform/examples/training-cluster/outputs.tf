output "grafana_url" {
  description = "URL to access Grafana dashboard"
  value       = module.monitoring_host.grafana_url
}

output "victoria_metrics_url" {
  description = "URL to access VictoriaMetrics"
  value       = module.monitoring_host.victoria_metrics_url
}

output "monitoring_host_external_ip" {
  description = "External IP of monitoring host"
  value       = module.monitoring_host.external_ip
}

output "monitoring_host_internal_ip" {
  description = "Internal IP of monitoring host"
  value       = module.monitoring_host.internal_ip
}

output "worker_internal_ips" {
  description = "Internal IPs of worker instances"
  value       = module.workers.internal_ips
}

output "worker_external_ips" {
  description = "External IPs of worker instances"
  value       = module.workers.external_ips
}

output "worker_metrics_endpoints" {
  description = "Metrics endpoints for worker instances"
  value       = module.workers.metrics_endpoints
}

output "worker_targets" {
  description = "Worker targets configured for monitoring"
  value       = module.workers.worker_targets
}

output "network_name" {
  description = "Name of the created VPC network"
  value       = module.network.network_name
}

output "subnet_name" {
  description = "Name of the created subnet"
  value       = module.network.subnet_name
}

# SSH commands for easy access
output "ssh_commands" {
  description = "SSH commands to connect to instances"
  value = {
    monitoring_host = "gcloud compute ssh ${module.monitoring_host.instance_name} --zone=${var.zones[0]}"
    workers = [
      for i, name in module.workers.instance_names :
      "gcloud compute ssh ${name} --zone=${module.workers.zones[i]}"
    ]
  }
}

# Summary of deployment
output "deployment_summary" {
  description = "Summary of the deployed infrastructure"
  value = {
    deployment_name = var.deployment_name
    cluster_name    = var.cluster_name
    environment     = var.environment_name
    worker_count    = var.worker_count
    gpu_type        = var.gpu_type
    all_smi_version = var.all_smi_version
    grafana_url     = module.monitoring_host.grafana_url
    worker_targets  = module.workers.worker_targets
  }
}