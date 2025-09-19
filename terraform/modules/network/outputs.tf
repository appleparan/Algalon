output "network_name" {
  description = "Name of the created VPC network"
  value       = google_compute_network.algalon_network.name
}

output "network_self_link" {
  description = "Self link of the created VPC network"
  value       = google_compute_network.algalon_network.self_link
}

output "subnet_name" {
  description = "Name of the created subnet"
  value       = google_compute_subnetwork.algalon_subnet.name
}

output "subnet_self_link" {
  description = "Self link of the created subnet"
  value       = google_compute_subnetwork.algalon_subnet.self_link
}

output "subnet_cidr" {
  description = "CIDR block of the created subnet"
  value       = google_compute_subnetwork.algalon_subnet.ip_cidr_range
}