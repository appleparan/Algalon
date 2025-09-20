output "instance_name" {
  description = "Name of the created monitoring host instance"
  value       = google_compute_instance.algalon_host.name
}

output "instance_self_link" {
  description = "Self link of the created monitoring host instance"
  value       = google_compute_instance.algalon_host.self_link
}

output "internal_ip" {
  description = "Internal IP address of the monitoring host"
  value       = google_compute_instance.algalon_host.network_interface[0].network_ip
}

output "external_ip" {
  description = "External IP address of the monitoring host"
  value       = var.enable_external_ip ? (var.reserve_static_ip ? google_compute_address.algalon_host_ip[0].address : google_compute_instance.algalon_host.network_interface[0].access_config[0].nat_ip) : null
}

output "grafana_url" {
  description = "URL for the Grafana dashboard"
  value       = var.enable_external_ip ? "http://${var.reserve_static_ip ? google_compute_address.algalon_host_ip[0].address : google_compute_instance.algalon_host.network_interface[0].access_config[0].nat_ip}:3000" : "http://${google_compute_instance.algalon_host.network_interface[0].network_ip}:3000"
}

output "victoria_metrics_url" {
  description = "URL for VictoriaMetrics"
  value       = var.enable_external_ip ? "http://${var.reserve_static_ip ? google_compute_address.algalon_host_ip[0].address : google_compute_instance.algalon_host.network_interface[0].access_config[0].nat_ip}:8428" : "http://${google_compute_instance.algalon_host.network_interface[0].network_ip}:8428"
}

output "static_ip_address" {
  description = "Static IP address if created"
  value       = var.reserve_static_ip ? google_compute_address.algalon_host_ip[0].address : null
}

output "ssh_command" {
  description = "Command to SSH into the monitoring host"
  value       = var.enable_external_ip ? "gcloud compute ssh ${google_compute_instance.algalon_host.name} --zone=${google_compute_instance.algalon_host.zone}" : "gcloud compute ssh ${google_compute_instance.algalon_host.name} --zone=${google_compute_instance.algalon_host.zone} --internal-ip"
}