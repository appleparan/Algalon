# Algalon 🌟
*The Comprehensive Hardware Observer - Multi-Platform Monitoring Solution*

A scalable, distributed monitoring system built with Docker Compose that provides real-time insights into GPU, CPU, and system performance across multiple remote nodes with clean, ID-based labeling and intuitive dashboards. Now powered by **all-smi** for enhanced multi-platform support.

## ✨ Features

- **🎯 Hardware ID Display**: Shows GPU 0, 1, 2... and CPU cores with clear identification
- **🌐 Distributed Architecture**: Monitor hardware across multiple remote worker nodes
- **🚀 Multi-Platform Support**: NVIDIA GPUs, Apple Silicon, Jetson, NPUs via all-smi
- **📊 Comprehensive Monitoring**: GPU + CPU + Memory + Process-level metrics
- **⚡ Real-time Monitoring**: 5-second update intervals for live performance tracking
- **🐋 Containerized**: Complete Docker Compose deployment with host/worker separation
- **📈 Auto-provisioned**: Grafana dashboards and datasources ready out-of-the-box
- **🔧 Production Ready**: Built with VictoriaMetrics for scalable time-series storage
- **📡 Remote Scraping**: VMAgent collects metrics from distributed all-smi exporters

## 🏗️ Architecture

### Distributed Setup
```
┌─────────────────────────────────────────────────────────────────┐
│                          Host Node                              │
│  ┌──────────────┐    ┌─────────────────┐    ┌─────────────────┐ │
│  │   VMAgent    │───▶│ VictoriaMetrics │───▶│     Grafana     │ │
│  │ (Scraping)   │    │ (Time Series)   │    │  (Dashboards)   │ │
│  └──────┬───────┘    └─────────────────┘    └─────────────────┘ │
└─────────┼───────────────────────────────────────────────────────┘
          │ Remote scraping over network
          │
┌─────────▼─────────┐  ┌─────────────────┐  ┌─────────────────┐
│   Worker Node 1   │  │   Worker Node 2  │  │   Worker Node N  │
│ ┌───────────────┐ │  │ ┌───────────────┐│  │ ┌───────────────┐│
│ │   all-smi     │ │  │ │   all-smi     ││  │ │   all-smi     ││
│ │(GPU+CPU+Mem) │ │  │ │(GPU+CPU+Mem) ││  │ │(GPU+CPU+Mem) ││
│ │    :9090      │ │  │ │    :9090      ││  │ │    :9090      ││
│ └───────────────┘ │  │ └───────────────┘│  │ └───────────────┘│
└───────────────────┘  └─────────────────┘  └─────────────────┘
```

## 🚀 Quick Start

### Prerequisites
- **Host Node**: Docker & Docker Compose
- **Worker Nodes**: Docker, GPU with drivers (NVIDIA/Apple Silicon/NPU), appropriate runtime
- Network connectivity between host and worker nodes on port 9090

## 📦 Deployment Guide

### Automated Setup (Recommended)

The setup scripts provide flexible deployment options with configurable all-smi versions and ports.

#### Quick Start Options

```bash
# Make script executable
chmod +x setup.sh

# Single node setup (development/testing)
./setup.sh --single-node

# Distributed setup
./setup.sh --host     # On monitoring host
./setup.sh --worker   # On each GPU worker node
```

#### Advanced Configuration

**Custom all-smi Version and Port:**
```bash
# Use specific all-smi version
./setup.sh --worker --version v0.8.0

# Use custom port
./setup.sh --worker --port 8080

# Both version and port
./setup.sh --worker --version v0.9.0 --port 9091
./setup.sh --single-node --version v0.9.0 --port 9091
```

**Available Versions:**
- `v0.9.0` (default, latest stable)
- `v0.8.0` (previous stable)
- `main` (development branch)

#### Component-Specific Setup

**Host Only:**
```bash
cd algalon_host
./setup.sh
```

**Worker Only:**
```bash
cd algalon_worker
./setup.sh --version v0.9.0 --port 9090
```

### Manual Setup (Advanced Users)

#### Option 1: Using Environment Variables
```bash
# Worker setup with custom configuration
cd algalon_worker
export ALL_SMI_VERSION=v0.9.0
export ALL_SMI_PORT=9090
docker compose build
docker compose up -d
```

#### Option 2: Using .env File
```bash
# Copy example configuration
cd algalon_worker
cp .env.example .env

# Edit .env file with your preferred settings
# ALL_SMI_VERSION=v0.9.0
# ALL_SMI_PORT=9090

docker compose build
docker compose up -d
```

### Post-Deployment Configuration

#### For Distributed Setup

1. **Update worker targets** in `algalon_host/node/targets/all-smi-targets.yml`:
   ```yaml
   - targets:
       - '192.168.1.100:9090'  # Replace with actual worker IPs
       - '192.168.1.101:9090'  # Add more workers as needed
     labels:
       job: 'all-smi'
       cluster: 'production'
   ```

2. **Restart VMAgent** to discover new workers:
   ```bash
   cd algalon_host
   docker compose restart vmagent
   ```

3. **Verify connectivity**:
   ```bash
   # Test worker endpoints
   curl -f http://worker-ip:9090/metrics
   
   # Check multiple workers
   for ip in 192.168.1.100 192.168.1.101; do
     echo "Testing $ip:9090"
     curl -f http://$ip:9090/metrics >/dev/null && echo "✅ OK" || echo "❌ Failed"
   done
   ```

#### Access Points
- **Grafana Dashboard**: http://localhost:3000 (admin/admin)
- **VictoriaMetrics UI**: http://localhost:8428  
- **Worker Metrics**: http://worker-ip:9090/metrics

#### Port Considerations
- Default port: `9090` (configurable via `--port` option)
- Ensure firewall allows access on configured ports
- Update target configurations when using custom ports

## 📊 Dashboard Overview

### GPU Monitoring Dashboard
- **GPU Utilization Timeline**: Real-time GPU usage across all devices
- **Memory Utilization Timeline**: VRAM usage tracking
- **Memory Usage Breakdown**: Used vs Total memory visualization
- **Temperature Monitoring**: GPU thermal status
- **Current Status Bars**: Instant utilization overview

### System Monitoring Dashboard (NEW)
- **CPU Utilization**: Per-core and per-socket CPU usage
- **System Memory Usage**: Total and used system memory
- **Process Monitoring**: GPU process-level resource allocation
- **Multi-platform Metrics**: Platform-specific hardware insights

### Sample View
```
🖥️  GPU Monitoring:
GPU 0 Utilization: ████████░░ 85%
GPU 1 Utilization: ██████░░░░ 62%
GPU 2 Utilization: ███░░░░░░░ 31%

💻 System Monitoring:
CPU 0-3: ██████░░░░ 65%
Memory:   ████████░░ 82% (6.2GB/8GB)
Processes: 3 GPU tasks running
```

## 🛠️ Configuration

### Monitored Metrics
**GPU Metrics**:
- GPU Utilization (%)
- VRAM Utilization (%)
- VRAM Usage (Used/Total)
- GPU Temperature
- Power Consumption
- Clock Frequencies

**System Metrics** (NEW):
- CPU Utilization per core/socket
- System Memory Usage
- Process-level GPU allocation
- Platform-specific metrics

### Customization
- Configure all-smi API parameters in docker-compose.yml
- Modify dashboard panels in Grafana UI
- Adjust retention period in VictoriaMetrics settings
- Add custom labels in all-smi-targets.yml for multi-platform setups

## 🔧 Troubleshooting

### Verify Hardware Access
```bash
# For NVIDIA GPUs
docker run --rm --gpus all nvidia/cuda:11.0-base-ubuntu20.04 nvidia-smi

# Test all-smi directly
docker run --rm --gpus all ghcr.io/inureyes/all-smi:latest
```

### Check Service Status
```bash
docker compose ps
docker compose logs all-smi

# Test metrics endpoint
curl http://localhost:9090/metrics | grep all_smi
```

### API Testing with curl

The all-smi service provides a comprehensive Prometheus metrics endpoint. Test various aspects of the API:

```bash
# Basic connectivity test
curl -f http://localhost:9090/metrics

# Check GPU metrics (NVIDIA/Apple Silicon/NPU)
curl -s http://localhost:9090/metrics | grep -E "(gpu|cuda|metal|npu)"

# Monitor CPU metrics
curl -s http://localhost:9090/metrics | grep -E "(cpu|core)"

# Check memory utilization
curl -s http://localhost:9090/metrics | grep -E "(memory|mem)"

# View temperature sensors
curl -s http://localhost:9090/metrics | grep temperature

# Check power consumption
curl -s http://localhost:9090/metrics | grep power

# Process-level monitoring (if --processes enabled)
curl -s http://localhost:9090/metrics | grep process

# Get specific metric with value
curl -s http://localhost:9090/metrics | grep "all_smi_gpu_utilization"

# Monitor in real-time (updates every 5 seconds by default)
watch -n 5 'curl -s http://localhost:9090/metrics | grep "all_smi_gpu_utilization"'
```

#### Remote Worker Testing
```bash
# Test remote worker connectivity
curl -f http://worker-ip:9090/metrics

# Check multiple workers
for ip in 10.0.1.100 10.0.1.101; do
  echo "Testing worker: $ip"
  curl -f http://$ip:9090/metrics >/dev/null && echo "✅ OK" || echo "❌ Failed"
done
```

#### Platform-Specific Metrics
```bash
# NVIDIA GPU metrics
curl -s http://localhost:9090/metrics | grep -E "(nvidia|cuda)"

# Apple Silicon metrics
curl -s http://localhost:9090/metrics | grep -E "(apple|metal)"

# NPU/AI accelerator metrics  
curl -s http://localhost:9090/metrics | grep -E "(npu|ai|tpu)"

# Generic platform detection
curl -s http://localhost:9090/metrics | grep "all_smi_info"
```

### Troubleshooting

#### Setup Script Issues
```bash
# Check script permissions
ls -la setup.sh  # Should show executable permissions

# View script help
./setup.sh --help
cd algalon_worker && ./setup.sh --help

# Check Docker installation
docker --version
docker compose version
```

#### Build Issues
```bash
# Check build logs
cd algalon_worker
docker compose build --no-cache

# Verify environment variables
echo $ALL_SMI_VERSION
echo $ALL_SMI_PORT

# Manual build with specific version
export ALL_SMI_VERSION=v0.9.0
export ALL_SMI_PORT=9090
docker compose build
```

#### Runtime Issues
- **No metrics**: Ensure appropriate GPU runtime is installed (nvidia-docker2 for NVIDIA)
- **Permission denied**: Check Docker daemon has hardware access
- **Dashboard not loading**: Wait 30 seconds for all services to initialize
- **Platform not detected**: Verify all-smi supports your hardware platform
- **Port conflicts**: Check if port is already in use (`netstat -tulpn | grep :9090`)
- **Version issues**: Try using a different all-smi version (`--version v0.8.0`)

#### Network Issues
```bash
# Test worker connectivity from host
curl -f http://worker-ip:9090/metrics

# Check Docker network
docker network ls
docker network inspect algalon_worker_monitoring

# Verify port mapping
docker compose ps
```

## 📈 Scaling & Production

### Adding Worker Nodes

#### Standard Setup
```bash
# On new GPU node
./setup.sh --worker

# On monitoring host - add to targets file
echo "    - 'new-worker-ip:9090'" >> algalon_host/node/targets/all-smi-targets.yml

# Restart VMAgent to discover new worker
cd algalon_host && docker compose restart vmagent
```

#### Custom Configuration
```bash
# Worker with custom port
./setup.sh --worker --port 8080

# Worker with specific version
./setup.sh --worker --version v0.8.0

# Update host targets accordingly
echo "    - 'new-worker-ip:8080'" >> algalon_host/node/targets/all-smi-targets.yml
```

### Multi-Cluster Support
```yaml
# Different clusters with platform labels
- targets: ['10.0.1.100:9090', '10.0.1.101:9090']
  labels: {cluster: 'production', platform: 'nvidia', datacenter: 'dc1'}
- targets: ['10.0.2.100:9090', '10.0.2.101:9090'] 
  labels: {cluster: 'staging', platform: 'apple', datacenter: 'dc2'}
- targets: ['10.0.3.100:9090']
  labels: {cluster: 'edge', platform: 'jetson', datacenter: 'dc3'}
```

### High Availability
- Deploy multiple VictoriaMetrics instances with clustering
- Use Grafana's multi-datasource features for failover
- Consider Kubernetes deployment for orchestration

### Security Considerations
- Restrict port 9090 access to monitoring hosts only
- Use VPN or private networks for worker communication  
- Monitor resource usage of all-smi exporters
- Implement platform-specific security policies

## 🎯 Deployment Examples

### Scenario 1: Development Setup
```bash
# Single machine with GPU for testing
./setup.sh --single-node

# Custom port to avoid conflicts
./setup.sh --single-node --port 9091
```

### Scenario 2: Small Production Cluster
```bash
# Monitoring host (192.168.1.10)
./setup.sh --host

# GPU workers (192.168.1.20, 192.168.1.21)
./setup.sh --worker

# Update targets file on host
echo "- targets:" >> algalon_host/node/targets/all-smi-targets.yml
echo "    - '192.168.1.20:9090'" >> algalon_host/node/targets/all-smi-targets.yml
echo "    - '192.168.1.21:9090'" >> algalon_host/node/targets/all-smi-targets.yml
```

### Scenario 3: Mixed Version Environment
```bash
# Stable workers with v0.9.0
./setup.sh --worker --version v0.9.0

# Testing workers with development version
./setup.sh --worker --version main --port 9091

# Different hardware with older version
./setup.sh --worker --version v0.8.0 --port 9092
```

### Scenario 4: Multi-Port Environment
```bash
# Multiple services on same machine
./setup.sh --worker --port 9090  # Primary service
./setup.sh --worker --port 9091  # Secondary service
./setup.sh --worker --port 9092  # Testing service

# Update host targets for all ports
```

## 🤝 Contributing

Contributions welcome! Areas for improvement:
- Additional dashboard templates
- Alert rule configurations
- Multi-node deployment guides
- Custom metric collections

## 📝 License

Open source - feel free to use and modify for your monitoring needs.

---

*Named after Algalon the Observer - watching over your GPUs with cosmic precision* ⭐
