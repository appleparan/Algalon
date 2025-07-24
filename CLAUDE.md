# Algalon
## GPU Monitoring System with VictoriaMetrics, Grafana & DCGM

## Overview
A complete Docker Compose-based GPU monitoring solution that displays GPU metrics using GPU IDs instead of UUIDs, with dashboards focused on Memory Utilization and GPU Utilization.

## Architecture
- **VictoriaMetrics**: Time-series database for metric storage
- **DCGM-Exporter**: NVIDIA GPU metrics collection
- **VMAgent**: Metrics scraping and forwarding
- **Grafana**: Visualization and dashboards

## Key Features
- ✅ GPU ID-based labeling (0, 1, 2... instead of UUIDs)
- ✅ Real-time monitoring with 5-second intervals
- ✅ Memory & GPU utilization focused dashboards
- ✅ Auto-provisioned Grafana datasources and dashboards
- ✅ Containerized deployment with Docker Compose

## Quick Start
1. Ensure NVIDIA Docker runtime is installed
2. Create the required configuration files
3. Run `docker-compose up -d`
4. Access Grafana at http://localhost:3000 (admin/admin)

## Dashboard Panels
- GPU Utilization timeline
- Memory Utilization timeline  
- GPU Memory Usage (used vs total)
- GPU Temperature monitoring
- Current utilization bar gauges

## Requirements
- Docker & Docker Compose
- NVIDIA GPU with drivers
- nvidia-docker2 runtime

## Access Points
- **Grafana**: http://localhost:3000
- **VictoriaMetrics**: http://localhost:8428
- **DCGM Metrics**: http://localhost:9400/metrics

## Configuration
The system automatically configures:
- DCGM exporter with essential GPU metrics
- Grafana datasource pointing to VictoriaMetrics
- Pre-built dashboard with GPU ID labeling
- Prometheus scraping configuration

Perfect for monitoring multiple GPUs with clean, GPU ID-based identification in a production environment.
