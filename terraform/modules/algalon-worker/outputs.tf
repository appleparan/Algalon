output "instance_names" {
  description = "Names of the created worker instances"
  value       = google_compute_instance.algalon_worker[*].name
}

output "instance_self_links" {
  description = "Self links of the created worker instances"
  value       = google_compute_instance.algalon_worker[*].self_link
}

output "internal_ips" {
  description = "Internal IP addresses of the worker instances"
  value       = google_compute_instance.algalon_worker[*].network_interface[0].network_ip
}

output "external_ips" {
  description = "External IP addresses of the worker instances (if enabled)"
  value       = var.enable_external_ip ? google_compute_instance.algalon_worker[*].network_interface[0].access_config[0].nat_ip : []
}

output "metrics_endpoints" {
  description = "Metrics endpoints for the worker instances"
  value = var.enable_external_ip ? [
    for instance in google_compute_instance.algalon_worker :
    "http://${instance.network_interface[0].access_config[0].nat_ip}:${var.all_smi_port}/metrics"
  ] : [
    for instance in google_compute_instance.algalon_worker :
    "http://${instance.network_interface[0].network_ip}:${var.all_smi_port}/metrics"
  ]
}

output "worker_targets" {
  description = "Comma-separated list of worker targets for monitoring host"
  value = join(",", [
    for instance in google_compute_instance.algalon_worker :
    "${instance.network_interface[0].network_ip}:${var.all_smi_port}"
  ])
}

output "zones" {
  description = "Zones where worker instances are deployed"
  value       = google_compute_instance.algalon_worker[*].zone
}

# Managed Instance Group outputs
output "instance_group_manager" {
  description = "Name of the managed instance group (if created)"
  value       = var.create_instance_group ? google_compute_instance_group_manager.algalon_worker_group[0].name : null
}

output "instance_group_self_link" {
  description = "Self link of the managed instance group (if created)"
  value       = var.create_instance_group ? google_compute_instance_group_manager.algalon_worker_group[0].self_link : null
}

output "health_check_self_link" {
  description = "Self link of the health check (if created)"
  value       = var.create_instance_group ? google_compute_health_check.algalon_worker_health[0].self_link : null
}

output "autoscaler_self_link" {
  description = "Self link of the autoscaler (if created)"
  value       = var.create_instance_group && var.enable_autoscaling ? google_compute_autoscaler.algalon_worker_autoscaler[0].self_link : null
}