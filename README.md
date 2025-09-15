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

### Deployment Options

#### Option 1: Single Node (Development/Testing)
```bash
chmod +x setup.sh
./setup.sh --single-node
```

#### Option 2: Distributed Setup (Production)
```bash
# On monitoring host
chmod +x setup.sh
./setup.sh --host

# On each GPU worker node  
./setup.sh --worker
```

#### Option 3: Manual Setup
```bash
# Host node (monitoring & visualization)
cd algalon_host
docker-compose up -d

# Worker nodes (GPU metrics)
cd algalon_worker  
docker-compose up -d
```

### Configuration
1. **Edit worker targets**: Update `algalon_host/node/targets/dcgm-targets.yml` with actual worker IPs
2. **Verify connectivity**: Ensure host can reach workers on port 9090
3. **Access services**:
   - **Grafana Dashboard**: http://localhost:3000 (admin/admin)
   - **VictoriaMetrics UI**: http://localhost:8428  
   - **Worker Metrics**: http://worker-ip:9090/metrics

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

### Common Issues
- **No metrics**: Ensure appropriate GPU runtime is installed (nvidia-docker2 for NVIDIA)
- **Permission denied**: Check Docker daemon has hardware access
- **Dashboard not loading**: Wait 30 seconds for all services to initialize
- **Platform not detected**: Verify all-smi supports your hardware platform

## 📈 Scaling & Production

### Adding Worker Nodes
1. Deploy worker on new hardware node: `./setup.sh --worker`
2. Add worker IP to `algalon_host/node/targets/all-smi-targets.yml`
3. VMAgent automatically discovers new targets within 30 seconds

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
