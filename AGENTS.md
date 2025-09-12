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

## Migration Plan: DCGM → all-smi

### Phase 1: Worker Node Container Replacement (2-3h)
**Goal**: Replace DCGM-Exporter with all-smi
**Status**: Planning

**Tasks**:
- [ ] Update worker docker-compose.yml
- [ ] Configure all-smi container image
- [ ] Verify Prometheus metrics endpoint
- [ ] Adjust port and network settings

### Phase 2: Host Scraping Configuration (1-2h)
**Goal**: Configure VMAgent to collect all-smi metrics
**Status**: Planning

**Tasks**:
- [ ] Update prometheus.yml
- [ ] Create all-smi-targets.yml
- [ ] Configure metric labeling and filtering
- [ ] Test connectivity and validation

### Phase 3: Grafana Dashboard Updates (2-3h)
**Goal**: Build dashboards utilizing new metrics
**Status**: Planning

**Tasks**:
- [ ] Update existing GPU metric queries
- [ ] Add CPU, Memory metric panels
- [ ] Create process-level monitoring panels
- [ ] Implement multi-platform support labeling

### Phase 4: Testing & Validation (1-2h)
**Goal**: Verify complete system operation and optimization
**Status**: Planning

**Tasks**:
- [ ] Verify metric collection accuracy
- [ ] Compare performance and resource usage
- [ ] Update documentation
- [ ] Prepare rollback plan

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
- **all-smi Metrics**: http://localhost:9400/metrics (or configured port)

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