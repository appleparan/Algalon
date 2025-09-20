# Algalon 🌟
*The Comprehensive Hardware Observer - Multi-Platform Monitoring Solution*

A scalable, distributed monitoring system that provides real-time insights into GPU, CPU, and system performance across multiple remote nodes with clean, ID-based labeling and intuitive dashboards. Powered by **[all-smi](https://github.com/inureyes/all-smi)** for comprehensive multi-platform hardware monitoring.

Deploy with **Terraform** for production-ready infrastructure or **Docker Compose** for development and testing.

## ✨ Features

- **🎯 Hardware ID Display**: Shows GPU 0, 1, 2... and CPU cores with clear identification
- **🌐 Distributed Architecture**: Monitor hardware across multiple remote worker nodes
- **🚀 Multi-Platform Support**: NVIDIA GPUs, Apple Silicon, Jetson, NPUs via all-smi
- **📊 Comprehensive Monitoring**: GPU + CPU + Memory + Process-level metrics
- **⚡ Real-time Monitoring**: Configurable update intervals for live performance tracking
- **🏗️ Infrastructure as Code**: Deploy with Terraform for cloud-native scalability
- **🐋 Containerized**: Complete Docker Compose deployment with host/worker separation
- **📈 Auto-provisioned**: Grafana dashboards and datasources ready out-of-the-box
- **🔧 Production Ready**: Built with VictoriaMetrics for scalable time-series storage
- **📡 Remote Scraping**: VMAgent collects metrics from distributed all-smi exporters
- **☁️ Cloud Ready**: Native Google Cloud Platform support with auto-scaling

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
┌─────────▼─────────┐  ┌──────────────────┐  ┌──────────────────┐
│   Worker Node 1   │  │   Worker Node 2  │  │   Worker Node N  │
│ ┌───────────────┐ │  │ ┌───────────────┐│  │ ┌───────────────┐│
│ │   all-smi     │ │  │ │   all-smi     ││  │ │   all-smi     ││
│ │(GPU+CPU+Mem)  │ │  │ │(GPU+CPU+Mem)  ││  │ │(GPU+CPU+Mem)  ││
│ │    :9090      │ │  │ │    :9090      ││  │ │    :9090      ││
│ └───────────────┘ │  │ └───────────────┘│  │ └───────────────┘│
└───────────────────┘  └──────────────────┘  └──────────────────┘
```

## 🚀 Quick Start

### Prerequisites
- **For Terraform**: Terraform >= 1.6, Google Cloud account with appropriate permissions
- **For Docker Compose**: Docker & Docker Compose
- **Worker Nodes**: GPU with drivers (NVIDIA/Apple Silicon/NPU), appropriate container runtime
- Network connectivity between host and worker nodes

## 📦 Deployment Options

Choose your deployment method based on your needs:

### 🏗️ Terraform Deployment (Recommended for Production)

**Production-ready cloud deployment with auto-scaling and infrastructure management.**

#### Quick Start with Terraform

```bash
# Clone repository
git clone https://github.com/appleparan/Algalon.git
cd Algalon/terraform/examples/basic

# Configure deployment
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project settings

# Deploy infrastructure
terraform init
terraform apply
```

#### What You Get
- ✅ **Automated Infrastructure**: VPC, firewall rules, compute instances
- ✅ **Auto-scaling Workers**: Managed instance groups with health checks
- ✅ **Cost Optimization**: Preemptible instances and auto-shutdown
- ✅ **Security**: Restricted access and service accounts
- ✅ **Monitoring**: Built-in logging and monitoring integration

#### Configuration Example
```hcl
# terraform.tfvars
project_id = "your-gcp-project"
deployment_name = "algalon-prod"
worker_count = 3
gpu_type = "nvidia-tesla-v100"
cluster_name = "ml-training"
```

**👉 [See detailed Terraform guide](terraform/README.md)**

### 🐋 Docker Compose Deployment

**Flexible local deployment for development and testing.**

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

**Custom all-smi Version, Port, and Interval:**
```bash
# Use specific all-smi version
./setup.sh --worker --version v0.8.0

# Use custom port and interval
./setup.sh --worker --port 8080 --interval 10

# Full customization
./setup.sh --worker --version v0.9.0 --port 9091 --interval 3
```

**Available Options:**
- **Versions**: `v0.9.0` (default), `v0.8.0`, `main`
- **Ports**: Any available port (default: 9090)
- **Intervals**: Collection interval in seconds (default: 5)

#### Component-Specific Setup

**Host with Dynamic Targets:**
```bash
cd algalon_host
./setup.sh --targets "worker1:9090,worker2:9090,10.0.1.100:9091"
```

**Worker with Full Configuration:**
```bash
cd algalon_worker
./setup.sh --version v0.9.0 --port 9090 --interval 5
```

### Manual Setup (Advanced Users)

#### Option 1: Using Environment Variables
```bash
# Worker setup with custom configuration
cd algalon_worker
export ALL_SMI_VERSION=v0.9.0
export ALL_SMI_PORT=9090
export ALL_SMI_INTERVAL=5
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
# ALL_SMI_INTERVAL=5

docker compose build
docker compose up -d
```

### Post-Deployment Configuration

#### For Distributed Setup

1. **Update worker targets** dynamically:
   ```bash
   cd algalon_host
   ./generate-targets.sh --targets "192.168.1.100:9090,192.168.1.101:9090" --cluster production
   ```

   Or manually edit `algalon_host/node/targets/all-smi-targets.yml`:
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

#### Configuration Options
- **Port**: Default `9090` (configurable via `--port` option)
- **Interval**: Default `5` seconds (configurable via `--interval` option)
- **Targets**: Dynamic configuration with environment variables
- **Firewall**: Ensure configured ports are accessible

## ☁️ Cloud Deployment

### Google Cloud Platform

Deploy Algalon on GCP with full automation:

```bash
# Quick cloud deployment
cd terraform/examples/basic
terraform init
terraform apply
```

**Features:**
- **Auto-scaling**: Managed instance groups with health checks
- **Cost Optimization**: Preemptible instances and resource scheduling
- **Security**: VPC isolation and IAM service accounts
- **Monitoring**: Cloud Logging and Monitoring integration

### Other Cloud Providers

- **AWS**: Adapt Terraform modules for EC2 and Auto Scaling Groups
- **Azure**: Use Azure Resource Manager templates
- **Multi-cloud**: Kubernetes deployment with cluster autoscaling

**👉 [See complete cloud deployment guide](CLOUD_DEPLOYMENT.md)**

## 📊 Dashboard Overview

### GPU Monitoring Dashboard (DCGM-based)
- **GPU Utilization Timeline**: Real-time GPU usage across all devices
- **Memory Utilization Timeline**: VRAM usage tracking
- **Memory Usage Breakdown**: Used vs Total memory visualization  
- **Temperature Monitoring**: GPU thermal status
- **Current Status Bars**: Instant utilization overview

### All-SMI Hardware Monitoring Dashboard (NEW)
- **GPU Metrics**: Utilization, memory usage, temperature, power consumption
- **CPU Monitoring**: System-wide CPU utilization
- **Memory Usage**: System memory utilization percentage
- **Disk Metrics**: Available space and utilization by device
- **Process Monitoring**: Top processes with CPU/memory usage (table view)
- **Multi-platform Support**: Works with NVIDIA, Apple Silicon, NPUs, etc.

### System Monitoring Dashboard (Legacy)
- **CPU Utilization**: Per-core and per-socket CPU usage
- **System Memory Usage**: Total and used system memory
- **Process Monitoring**: GPU process-level resource allocation

### Dashboard Access
- **All-SMI Dashboard**: Comprehensive hardware monitoring for all-smi nodes
- **GPU Dashboard**: DCGM-based monitoring for NVIDIA-specific setups
- **System Dashboard**: Additional system metrics and legacy support

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

**Docker Compose (Local):**
```bash
# Single machine with GPU for testing
./setup.sh --single-node

# Custom port and interval
./setup.sh --single-node --port 9091 --interval 10
```

**Terraform (Cloud):**
```bash
cd terraform/examples/basic
terraform apply -var="deployment_name=algalon-dev" \
                -var="worker_count=1" \
                -var="use_preemptible_workers=true"
```

### Scenario 2: Small Production Cluster

**Docker Compose:**
```bash
# Monitoring host
./setup.sh --host --targets "192.168.1.20:9090,192.168.1.21:9090"

# GPU workers
./setup.sh --worker --interval 5
```

**Terraform:**
```bash
cd terraform/examples/basic
terraform apply -var="deployment_name=algalon-prod" \
                -var="worker_count=3" \
                -var="gpu_type=nvidia-tesla-v100" \
                -var="create_static_ip=true"
```

### Scenario 3: Auto-scaling Production

**Terraform with Managed Instance Groups:**
```bash
cd terraform/examples/production
terraform apply -var="enable_autoscaling=true" \
                -var="autoscaling_min_replicas=2" \
                -var="autoscaling_max_replicas=10"
```

### Scenario 4: Multi-Environment Setup

**Development + Staging + Production:**
```bash
# Development
terraform apply -var="environment_name=dev" \
                -var="use_preemptible_workers=true"

# Staging
terraform apply -var="environment_name=staging" \
                -var="worker_count=2"

# Production
terraform apply -var="environment_name=prod" \
                -var="worker_count=5" \
                -var="gpu_type=nvidia-tesla-a100"
```

## 🤝 Contributing

Contributions welcome! Areas for improvement:
- Additional dashboard templates and alert rules
- Cloud provider modules (AWS, Azure, etc.)
- Kubernetes deployment manifests
- Custom metric collections and exporters
- Security enhancements and compliance features

**Testing Infrastructure:**
- Comprehensive test suite with GitHub Actions
- Unit, integration, and E2E tests
- Security scanning and compliance checking
- Cost estimation and optimization

**👉 [See testing guide](TESTING.md)**

## 🙏 Credits

This project is powered by **[all-smi](https://github.com/inureyes/all-smi)** - A comprehensive hardware monitoring tool that provides unified metrics collection across multiple platforms including NVIDIA GPUs, Apple Silicon, Jetson devices, and NPUs.

Special thanks to the all-smi project for enabling cross-platform hardware monitoring and making it possible to create truly universal GPU monitoring solutions.

## 📝 License

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

See the [LICENSE](LICENSE) file for the full license text.

---

*Named after Algalon the Observer - watching over your GPUs with cosmic precision* ⭐
