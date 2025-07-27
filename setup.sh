#!/bin/bash

# GPU Monitoring System Setup Script
set -e

echo "🚀 Setting up GPU Monitoring System..."

# Create directory structure
mkdir -p grafana/provisioning/datasources
mkdir -p grafana/provisioning/dashboards
mkdir -p grafana/dashboards

# Create configuration files
echo "📝 Creating configuration files..."

# Prometheus config
cat > prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'dcgm-exporter'
    static_configs:
      - targets: ['dcgm-exporter:9400']
    scrape_interval: 5s
    metrics_path: /metrics
EOF

# DCGM config
cat > dcgm-exporter-config.csv << 'EOF'
# Format,,
# If line starts with a '#' it is considered a comment,,
# DCGM FIELD, Prometheus metric type, help message

# GPU Utilization
DCGM_FI_DEV_GPU_UTIL, gauge, GPU utilization (in %).
DCGM_FI_DEV_MEM_COPY_UTIL, gauge, Memory utilization (in %).

# Memory Information  
DCGM_FI_DEV_FB_FREE, gauge, Framebuffer memory free (in MiB).
DCGM_FI_DEV_FB_USED, gauge, Framebuffer memory used (in MiB).
DCGM_FI_DEV_FB_TOTAL, gauge, Total framebuffer memory (in MiB).

# Temperature
DCGM_FI_DEV_GPU_TEMP, gauge, GPU temperature (in C).
DCGM_FI_DEV_MEMORY_TEMP, gauge, Memory temperature (in C).

# Power
DCGM_FI_DEV_POWER_USAGE, gauge, Power draw (in W).
DCGM_FI_DEV_TOTAL_ENERGY_CONSUMPTION, counter, Total energy consumption since boot (in mJ).

# Clock frequencies
DCGM_FI_DEV_SM_CLOCK, gauge, SM clock frequency (in MHz).
DCGM_FI_DEV_MEM_CLOCK, gauge, Memory clock frequency (in MHz).

# PCIe
DCGM_FI_DEV_PCIE_TX_THROUGHPUT, counter, Total number of bytes transmitted through PCIe TX
DCGM_FI_DEV_PCIE_RX_THROUGHPUT, counter, Total number of bytes received through PCIe RX
EOF

# Grafana datasource config
cat > grafana/provisioning/datasources/victoriametrics.yml << 'EOF'
apiVersion: 1

datasources:
  - name: VictoriaMetrics
    type: prometheus
    access: proxy
    url: http://victoriametrics:8428
    isDefault: true
    editable: true
    httpMethod: POST
    jsonData:
      httpMethod: POST
      manageAlerts: false
      prometheusType: Prometheus
      prometheusVersion: 2.40.0
      cacheLevel: 'High'
EOF

# Grafana dashboard provider config
cat > grafana/provisioning/dashboards/gpu-dashboard.yml << 'EOF'
apiVersion: 1

providers:
  - name: 'GPU Monitoring'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards
EOF

echo "✅ Configuration files created successfully!"

# Check if nvidia-docker is installed
if ! command -v nvidia-docker &> /dev/null; then
    echo "⚠️  nvidia-docker is not installed. Please install it first:"
    echo "   curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -"
    echo "   distribution=\$(. /etc/os-release;echo \$ID\$VERSION_ID)"
    echo "   curl -s -L https://nvidia.github.io/nvidia-docker/\$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list"
    echo "   sudo apt-get update && sudo apt-get install -y nvidia-docker2"
    echo "   sudo systemctl restart docker"
fi

# Start the monitoring system
echo "🚀 Starting GPU Monitoring System..."
docker-compose up -d

echo "⏳ Waiting for services to start..."
sleep 30

echo "🎉 GPU Monitoring System is ready!"
echo ""
echo "📊 Access points:"
echo "   - Grafana Dashboard: http://localhost:3000 (admin/admin)"
echo "   - VictoriaMetrics: http://localhost:8428"
echo "   - DCGM Exporter: http://localhost:9400/metrics"
echo ""
echo "📋 GPU Information:"
nvidia-smi --query-gpu=index,name,uuid --format=csv,noheader,nounits | while IFS=, read -r id name uuid; do
    echo "   GPU $id: $name"
done

echo ""
echo "✨ The dashboard will show GPU IDs instead of UUIDs as requested!"
echo "   Navigate to Grafana and look for the 'GPU Monitoring Dashboard'"
