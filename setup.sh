#!/bin/bash

# Algalon Multi-Platform Hardware Monitoring System Setup Script
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_usage() {
    echo "🌟 Algalon Multi-Platform Hardware Monitoring Setup"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --host         Setup monitoring host (VictoriaMetrics + Grafana)"
    echo "  --worker       Setup hardware worker node (all-smi Exporter)"
    echo "  --single-node  Setup all components on single node (development)"
    echo "  --help         Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --host               # Setup monitoring host"
    echo "  $0 --worker             # Setup GPU worker node"
    echo "  $0 --single-node        # All-in-one setup"
    echo ""
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}❌ Docker is not installed. Please install Docker first.${NC}"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        echo -e "${RED}❌ Docker Compose is not installed. Please install Docker Compose first.${NC}"
        exit 1
    fi
}

check_hardware_runtime() {
    # Check for NVIDIA runtime
    if docker info | grep -q nvidia; then
        echo -e "${GREEN}✅ NVIDIA Docker runtime detected${NC}"
    elif command -v nvidia-smi &> /dev/null; then
        echo -e "${YELLOW}⚠️  NVIDIA GPUs detected but Docker runtime missing. For NVIDIA GPUs, install nvidia-container-toolkit:${NC}"
        echo "   curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg"
        echo "   curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list"
        echo "   sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit"
        echo "   sudo systemctl restart docker"
        echo ""
    else
        echo -e "${BLUE}ℹ️  all-smi supports multiple platforms beyond NVIDIA (Apple Silicon, NPU, etc.)${NC}"
    fi
}

setup_host() {
    echo -e "${BLUE}🏗️  Setting up Algalon Host (Monitoring & Visualization)...${NC}"
    
    cd "${SCRIPT_DIR}/algalon_host"
    
    # Check if targets are configured
    if grep -q "localhost:9400" node/targets/all-smi-targets.yml; then
        echo -e "${YELLOW}⚠️  Worker targets are using localhost${NC}"
        echo "   Please update algalon_host/node/targets/all-smi-targets.yml with actual worker IPs"
        echo ""
    fi
    
    echo "🚀 Starting monitoring services..."
    docker compose up -d
    
    echo "⏳ Waiting for services to initialize..."
    sleep 20
    
    echo -e "${GREEN}🎉 Algalon Host is ready!${NC}"
    echo ""
    echo "📊 Access points:"
    echo "   - Grafana Dashboard: http://localhost:3000 (admin/admin)"
    echo "   - VictoriaMetrics: http://localhost:8428"
    echo ""
    echo "📝 Next steps:"
    echo "   1. Update worker IPs in: algalon_host/node/targets/all-smi-targets.yml"
    echo "   2. Deploy workers: ./setup.sh --worker"
    echo "   3. Restart VMAgent: docker compose restart vmagent"
}

setup_worker() {
    echo -e "${BLUE}🏗️  Setting up Algalon Worker (Hardware Metrics Exporter)...${NC}"
    
    check_hardware_runtime
    
    cd "${SCRIPT_DIR}/algalon_worker"
    
    echo "🏗️ Building all-smi from source (this may take a few minutes)..."
    docker compose build
    
    echo "🚀 Starting all-smi Exporter..."
    docker compose up -d
    
    echo "⏳ Waiting for all-smi to start..."
    sleep 15
    
    # Test metrics endpoint
    if curl -sf http://localhost:9400/metrics > /dev/null; then
        echo -e "${GREEN}🎉 Algalon Worker is ready!${NC}"
        echo ""
        echo "📊 Metrics endpoint: http://$(hostname -I | awk '{print $1}'):9400/metrics"
        echo ""
        echo "📋 Hardware Information:"
        if command -v nvidia-smi &> /dev/null; then
            echo "   NVIDIA GPUs:"
            nvidia-smi --query-gpu=index,name --format=csv,noheader,nounits | while IFS=, read -r id name; do
                echo "     GPU $id: $name"
            done
        fi
        echo "   Platform: $(uname -m) ($(uname -s))"
        echo ""
        echo "📝 Next steps:"
        echo "   1. Add this worker IP to host's all-smi-targets.yml"
        echo "   2. Restart host VMAgent to discover this worker"
    else
        echo -e "${RED}❌ Failed to start all-smi Exporter. Check logs: docker compose logs${NC}"
        exit 1
    fi
}

setup_single_node() {
    echo -e "${BLUE}🏗️  Setting up Algalon Single Node (All components)...${NC}"
    
    check_hardware_runtime
    
    # Setup worker first
    cd "${SCRIPT_DIR}/algalon_worker"
    echo "🏗️ Building all-smi from source (this may take a few minutes)..."
    docker compose build
    
    echo "🚀 Starting all-smi Exporter..."
    docker compose up -d
    
    # Wait and verify worker
    sleep 15
    if ! curl -sf http://localhost:9400/metrics > /dev/null; then
        echo -e "${RED}❌ all-smi Exporter failed to start${NC}"
        exit 1
    fi
    
    # Setup host with localhost target
    cd "${SCRIPT_DIR}/algalon_host"
    
    # Ensure target points to localhost for single-node
    if ! grep -q "localhost:9400" node/targets/all-smi-targets.yml; then
        echo "# Single-node configuration" > node/targets/all-smi-targets.yml
        echo "- targets:" >> node/targets/all-smi-targets.yml
        echo "    - 'localhost:9400'" >> node/targets/all-smi-targets.yml
        echo "  labels:" >> node/targets/all-smi-targets.yml
        echo "    job: 'all-smi'" >> node/targets/all-smi-targets.yml
        echo "    cluster: 'development'" >> node/targets/all-smi-targets.yml
        echo "    monitoring_type: 'comprehensive'" >> node/targets/all-smi-targets.yml
    fi
    
    echo "🚀 Starting monitoring services..."
    docker compose up -d
    
    echo "⏳ Waiting for all services to initialize..."
    sleep 30
    
    echo -e "${GREEN}🎉 Algalon Single Node is ready!${NC}"
    echo ""
    echo "📊 Access points:"
    echo "   - Grafana Dashboard: http://localhost:3000 (admin/admin)"
    echo "   - VictoriaMetrics: http://localhost:8428"
    echo "   - all-smi Metrics: http://localhost:9400/metrics"
    echo ""
    echo "📋 Hardware Information:"
    if command -v nvidia-smi &> /dev/null; then
        echo "   NVIDIA GPUs:"
        nvidia-smi --query-gpu=index,name --format=csv,noheader,nounits | while IFS=, read -r id name; do
            echo "     GPU $id: $name"
        done
    fi
    echo "   Platform: $(uname -m) ($(uname -s))"
    echo ""
    echo "✨ Navigate to Grafana and explore:"
    echo "   - GPU Monitoring Dashboard (enhanced with all-smi)"
    echo "   - All-SMI System Monitoring Dashboard (NEW)"
}

# Main script logic
case "${1:-}" in
    --host)
        check_docker
        setup_host
        ;;
    --worker)
        check_docker
        setup_worker
        ;;
    --single-node)
        check_docker
        setup_single_node
        ;;
    --help|-h)
        print_usage
        ;;
    "")
        echo -e "${YELLOW}⚠️  No option specified. Use --help to see available options.${NC}"
        print_usage
        exit 1
        ;;
    *)
        echo -e "${RED}❌ Unknown option: $1${NC}"
        print_usage
        exit 1
        ;;
esac
