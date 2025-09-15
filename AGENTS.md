# Algalon
## GPU Monitoring System with VictoriaMetrics, Grafana & all-smi

## Overview
A complete Docker Compose-based GPU monitoring solution that displays GPU metrics using GPU IDs instead of UUIDs, with dashboards focused on Memory Utilization and GPU Utilization. **Now migrating from DCGM to all-smi for enhanced multi-platform support.**

## Current Architecture (DCGM-based)
- **VictoriaMetrics**: Time-series database for metric storage
- **DCGM-Exporter**: NVIDIA GPU metrics collection
- **VMAgent**: Metrics scraping and forwarding
- **Grafana**: Visualization and dashboards

## Target Architecture (all-smi-based)
- **VictoriaMetrics**: Time-series database for metric storage (unchanged)
- **all-smi**: Multi-platform GPU/CPU/Memory metrics collection
- **VMAgent**: Metrics scraping and forwarding (unchanged)
- **Grafana**: Enhanced visualization with additional metrics

## Migration Status: DCGM → all-smi ✅ COMPLETED

### Phase 1: Worker Node Container Replacement ✅
**Goal**: Replace DCGM-Exporter with all-smi
**Status**: ✅ Complete

**Completed Tasks**:
- ✅ Updated worker docker-compose.yml to use `ghcr.io/inureyes/all-smi:latest`
- ✅ Configured all-smi container with API mode and process monitoring
- ✅ Set Prometheus metrics endpoint on port 9090
- ✅ Maintained NVIDIA runtime and network settings

### Phase 2: Host Scraping Configuration ✅
**Goal**: Configure VMAgent to collect all-smi metrics
**Status**: ✅ Complete

**Completed Tasks**:
- ✅ Updated prometheus.yml to target `all-smi` job
- ✅ Created all-smi-targets.yml with comprehensive labeling
- ✅ Configured metric labeling for multi-platform support
- ✅ Set up file service discovery for all-smi endpoints

### Phase 3: Grafana Dashboard Updates ✅
**Goal**: Build dashboards utilizing new metrics
**Status**: ✅ Complete

**Completed Tasks**:
- ✅ Updated existing GPU metric queries (DCGM → all-smi format)
- ✅ Changed metric names: `DCGM_FI_DEV_GPU_UTIL` → `all_smi_gpu_utilization`
- ✅ Updated GPU indexing: `gpu` → `gpu_index` labels
- ✅ Created new System Monitoring dashboard with CPU/Memory/Process panels
- ✅ Implemented comprehensive system monitoring capabilities

### Phase 4: Documentation & Rollback ✅
**Goal**: Document changes and prepare rollback strategy
**Status**: ✅ Complete

**Migration Summary**:
- ✅ Enhanced monitoring from GPU-only to comprehensive system monitoring
- ✅ Maintained existing VictoriaMetrics + Grafana infrastructure
- ✅ Added CPU utilization, system memory, and process-level tracking
- ✅ Prepared rollback capability by preserving original DCGM configuration patterns

## Expected Benefits
- ✅ **Scalability**: Support for NVIDIA, Apple Silicon, NPU platforms
- ✅ **Completeness**: Integrated GPU+CPU+Memory monitoring
- ✅ **Compatibility**: Maintains existing VictoriaMetrics infrastructure
- ✅ **Process Tracking**: Application-level metrics

## Key Features (Enhanced)
- ✅ GPU ID-based labeling (0, 1, 2... instead of UUIDs)
- ✅ Real-time monitoring with 5-second intervals
- ✅ Memory & GPU utilization focused dashboards
- ✅ **NEW**: CPU and system memory monitoring
- ✅ **NEW**: Process-level GPU usage tracking
- ✅ **NEW**: Multi-platform support (NVIDIA, Apple Silicon, NPU)
- ✅ Auto-provisioned Grafana datasources and dashboards
- ✅ Containerized deployment with Docker Compose

## Quick Start
1. Ensure NVIDIA Docker runtime is installed (or appropriate runtime for your platform)
2. Create the required configuration files
3. Run `docker-compose up -d`
4. Access Grafana at http://localhost:3000 (admin/admin)

## Dashboard Panels (Enhanced)
**Existing**:
- GPU Utilization timeline
- Memory Utilization timeline  
- GPU Memory Usage (used vs total)
- GPU Temperature monitoring
- Current utilization bar gauges

**New with all-smi**:
- CPU Utilization per core/socket
- System Memory Usage
- Process-level GPU allocation
- Multi-platform device detection

## Requirements
- Docker & Docker Compose
- GPU with drivers (NVIDIA, Apple Silicon, or supported NPU)
- Appropriate container runtime (nvidia-docker2 for NVIDIA)

## Access Points
- **Grafana**: http://localhost:3000
- **VictoriaMetrics**: http://localhost:8428
- **all-smi Metrics**: http://localhost:9090/metrics (or configured port)

## Configuration
The system automatically configures:
- all-smi exporter with comprehensive hardware metrics
- Grafana datasource pointing to VictoriaMetrics
- Pre-built dashboard with GPU ID labeling
- Prometheus scraping configuration for multi-platform support

Perfect for monitoring multiple GPUs and system resources with clean, ID-based identification across different hardware platforms in a production environment.

## Migration Notes
- VictoriaMetrics infrastructure remains unchanged
- Existing dashboard queries will be updated to use new metric names
- Backward compatibility maintained during transition period
- Enhanced monitoring capabilities with minimal infrastructure changes