#!/bin/bash

# GPU Monitoring System Setup Script
set -e

echo "🚀 Setting up GPU Monitoring System..."

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
