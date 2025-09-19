# Network module for Algalon infrastructure
# Creates VPC, subnets, and firewall rules

resource "google_compute_network" "algalon_network" {
  name                    = var.network_name
  auto_create_subnetworks = false
  description             = "Network for Algalon monitoring infrastructure"
}

resource "google_compute_subnetwork" "algalon_subnet" {
  name          = "${var.network_name}-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.algalon_network.id
  description   = "Subnet for Algalon instances"
}

# Firewall rule for Grafana access
resource "google_compute_firewall" "algalon_grafana" {
  name    = "${var.network_name}-grafana"
  network = google_compute_network.algalon_network.name

  allow {
    protocol = "tcp"
    ports    = ["3000"]
  }

  source_ranges = var.grafana_allowed_ips
  target_tags   = ["algalon-monitoring"]
  description   = "Allow access to Grafana dashboard"
}

# Firewall rule for VictoriaMetrics access (optional external access)
resource "google_compute_firewall" "algalon_victoria_metrics" {
  count   = var.enable_external_victoria_metrics ? 1 : 0
  name    = "${var.network_name}-victoria-metrics"
  network = google_compute_network.algalon_network.name

  allow {
    protocol = "tcp"
    ports    = ["8428"]
  }

  source_ranges = var.victoria_metrics_allowed_ips
  target_tags   = ["algalon-monitoring"]
  description   = "Allow access to VictoriaMetrics"
}

# Firewall rule for internal metrics collection
resource "google_compute_firewall" "algalon_metrics_internal" {
  name    = "${var.network_name}-metrics-internal"
  network = google_compute_network.algalon_network.name

  allow {
    protocol = "tcp"
    ports    = var.worker_ports
  }

  source_tags = ["algalon-monitoring"]
  target_tags = ["algalon-worker"]
  description = "Allow metrics collection from workers"
}

# Firewall rule for SSH access
resource "google_compute_firewall" "algalon_ssh" {
  count   = var.enable_ssh_access ? 1 : 0
  name    = "${var.network_name}-ssh"
  network = google_compute_network.algalon_network.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.ssh_allowed_ips
  target_tags   = ["algalon-monitoring", "algalon-worker"]
  description   = "Allow SSH access to instances"
}

# Internal communication between instances
resource "google_compute_firewall" "algalon_internal" {
  name    = "${var.network_name}-internal"
  network = google_compute_network.algalon_network.name

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["1-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["1-65535"]
  }

  source_ranges = [var.subnet_cidr]
  description   = "Allow internal communication within subnet"
}