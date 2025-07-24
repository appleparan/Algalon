# Algalon 🌟
*The GPU Observer - Complete GPU Monitoring Solution*

A Docker Compose-based GPU monitoring system that provides real-time insights into your NVIDIA GPU performance with clean, ID-based labeling and intuitive dashboards.

## ✨ Features

- **🎯 GPU ID Display**: Shows GPU 0, 1, 2... instead of confusing UUIDs
- **📊 Memory & GPU Focused**: Dashboards centered on utilization metrics that matter
- **⚡ Real-time Monitoring**: 5-second update intervals for live performance tracking
- **🐋 Containerized**: Complete Docker Compose deployment
- **📈 Auto-provisioned**: Grafana dashboards and datasources ready out-of-the-box
- **🔧 Production Ready**: Built with VictoriaMetrics for scalable time-series storage

## 🏗️ Architecture

```
┌─────────────────┐    ┌──────────────┐    ┌─────────────────┐
│   DCGM Exporter │───▶│   VMAgent    │───▶│ VictoriaMetrics │
│  (GPU Metrics)  │    │ (Scraping)   │    │ (Time Series)   │
└─────────────────┘    └──────────────┘    └─────────────────┘
                                                      │
┌─────────────────┐                                   │
│     Grafana     │◀──────────────────────────────────┘
│  (Dashboards)   │
└─────────────────┘
```

## 🚀 Quick Start

### Prerequisites
- Docker & Docker Compose
- NVIDIA GPU with drivers
- nvidia-docker2 runtime

### Installation
1. Clone or create the project files
2. Run the setup script:
   ```bash
   chmod +x setup.sh
   ./setup.sh
   ```
3. Or start manually:
   ```bash
   docker-compose up -d
   ```

### Access
- **Grafana Dashboard**: http://localhost:3000 (admin/admin)
- **VictoriaMetrics UI**: http://localhost:8428
- **Raw GPU Metrics**: http://localhost:9400/metrics

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

## 📈 Scaling

For multiple nodes or advanced setups:
- Configure VMAgent for remote VictoriaMetrics clusters
- Use Grafana's multi-datasource features
- Deploy with Kubernetes for orchestration

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
