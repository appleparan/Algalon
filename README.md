# Algalon 🌟
*The GPU Observer - Distributed GPU Monitoring Solution*

A scalable, distributed GPU monitoring system built with Docker Compose that provides real-time insights into NVIDIA GPU performance across multiple remote worker nodes with clean, ID-based labeling and intuitive dashboards.

## ✨ Features

- **🎯 GPU ID Display**: Shows GPU 0, 1, 2... instead of confusing UUIDs
- **🌐 Distributed Architecture**: Monitor GPUs across multiple remote worker nodes
- **📊 Memory & GPU Focused**: Dashboards centered on utilization metrics that matter
- **⚡ Real-time Monitoring**: 5-second update intervals for live performance tracking
- **🐋 Containerized**: Complete Docker Compose deployment with host/worker separation
- **📈 Auto-provisioned**: Grafana dashboards and datasources ready out-of-the-box
- **🔧 Production Ready**: Built with VictoriaMetrics for scalable time-series storage
- **📡 Remote Scraping**: VMAgent collects metrics from distributed DCGM exporters

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
│ │ DCGM Exporter │ │  │ │ DCGM Exporter ││  │ │ DCGM Exporter ││
│ │ (GPU Metrics) │ │  │ │ (GPU Metrics) ││  │ │ (GPU Metrics) ││
│ │    :9400      │ │  │ │    :9400      ││  │ │    :9400      ││
│ └───────────────┘ │  │ └───────────────┘│  │ └───────────────┘│
└───────────────────┘  └─────────────────┘  └─────────────────┘
```

## 🚀 Quick Start

### Prerequisites
- **Host Node**: Docker & Docker Compose
- **Worker Nodes**: Docker, NVIDIA GPU with drivers, nvidia-docker2 runtime
- Network connectivity between host and worker nodes on port 9400

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
2. **Verify connectivity**: Ensure host can reach workers on port 9400
3. **Access services**:
   - **Grafana Dashboard**: http://localhost:3000 (admin/admin)
   - **VictoriaMetrics UI**: http://localhost:8428  
   - **Worker Metrics**: http://worker-ip:9400/metrics

## 📊 Dashboard Overview

### Main Panels
- **GPU Utilization Timeline**: Real-time GPU usage across all devices
- **Memory Utilization Timeline**: VRAM usage tracking
- **Memory Usage Breakdown**: Used vs Total memory visualization
- **Temperature Monitoring**: GPU thermal status
- **Current Status Bars**: Instant utilization overview

### Sample View
```
GPU 0 Utilization: ████████░░ 85%
GPU 1 Utilization: ██████░░░░ 62%
GPU 2 Utilization: ███░░░░░░░ 31%
```

## 🛠️ Configuration

### Monitored Metrics
- GPU Utilization (%)
- Memory Utilization (%)
- Memory Usage (Used/Total)
- GPU Temperature
- Power Consumption
- Clock Frequencies

### Customization
- Edit `dcgm-exporter-config.csv` to add/remove metrics
- Modify dashboard panels in Grafana UI
- Adjust retention period in VictoriaMetrics settings

## 🔧 Troubleshooting

### Verify GPU Access
```bash
docker run --rm --gpus all nvidia/cuda:11.0-base-ubuntu20.04 nvidia-smi
```

### Check Service Status
```bash
docker-compose ps
docker-compose logs dcgm-exporter
```

### Common Issues
- **No GPU metrics**: Ensure nvidia-docker2 is properly installed
- **Permission denied**: Check Docker daemon has GPU access
- **Dashboard not loading**: Wait 30 seconds for all services to initialize

## 📈 Scaling & Production

### Adding Worker Nodes
1. Deploy worker on new GPU node: `./setup.sh --worker`
2. Add worker IP to `algalon_host/node/targets/dcgm-targets.yml`
3. VMAgent automatically discovers new targets within 30 seconds

### Multi-Cluster Support
```yaml
# Different clusters with labels
- targets: ['10.0.1.100:9400', '10.0.1.101:9400']
  labels: {cluster: 'production', datacenter: 'dc1'}
- targets: ['10.0.2.100:9400', '10.0.2.101:9400'] 
  labels: {cluster: 'staging', datacenter: 'dc2'}
```

### High Availability
- Deploy multiple VictoriaMetrics instances with clustering
- Use Grafana's multi-datasource features for failover
- Consider Kubernetes deployment for orchestration

### Security Considerations
- Restrict port 9400 access to monitoring hosts only
- Use VPN or private networks for worker communication
- Monitor resource usage of DCGM exporters

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
