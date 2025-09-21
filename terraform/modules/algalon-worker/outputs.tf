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

output "zone" {
  description = "Zone where worker instances are deployed"
  value       = var.zone
}

output "total_gpu_count" {
  description = "Total number of GPUs allocated across all instances"
  value       = var.total_gpu_count
}

output "instance_count" {
  description = "Number of instances created"
  value       = local.instance_count
}

output "gpus_per_instance" {
  description = "Number of GPUs per instance"
  value       = var.gpus_per_instance
}