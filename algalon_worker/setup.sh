#!/bin/bash

# Algalon Worker Setup Script
# Sets up hardware metrics worker node with all-smi exporter
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_usage() {
    echo "🌟 Algalon Worker Setup - Hardware Metrics Exporter"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --version <ver>     all-smi version to build (default: v0.9.0)"
    echo "  --port <port>       Port for all-smi API (default: 9090)"
    echo "  --help              Show this help message"
    echo ""
    echo "Description:"
    echo "  Sets up a hardware worker node with all-smi exporter that provides"
    echo "  GPU, CPU, and memory metrics for remote monitoring."
    echo ""
    echo "Prerequisites:"
    echo "  - Docker & Docker Compose"
    echo "  - GPU drivers (NVIDIA/Apple Silicon/NPU)"
    echo "  - Appropriate container runtime (nvidia-docker2 for NVIDIA)"
    echo ""
    echo "Examples:"
    echo "  $0                           # Setup with defaults (v0.9.0, port 9090)"
    echo "  $0 --version v0.8.0          # Use specific version"
    echo "  $0 --port 8080               # Use custom port"
    echo "  $0 --version v0.9.0 --port 9091  # Custom version and port"
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

setup_worker() {
    local version="${1:-v0.9.0}"
    local port="${2:-9090}"
    
    echo -e "${BLUE}🏗️  Setting up Algalon Worker (Hardware Metrics Exporter)...${NC}"
    echo "   🏷️  all-smi version: ${version}"
    echo "   🔌 Port: ${port}"
    echo ""
    
    check_hardware_runtime
    
    # Export environment variables for docker-compose
    export ALL_SMI_VERSION="${version}"
    export ALL_SMI_PORT="${port}"
    
    echo "🏗️ Generating Dockerfile for all-smi ${version}..."
    ./generate-dockerfile.sh "${version}" "${port}"
    
    echo "🏗️ Building all-smi ${version} from source (this may take a few minutes)..."
    docker compose build
    
    echo "🚀 Starting all-smi Exporter on port ${port}..."
    docker compose up -d
    
    echo "⏳ Waiting for all-smi to start..."
    sleep 15
    
    # Test metrics endpoint
    if curl -sf http://localhost:${port}/metrics > /dev/null; then
        echo -e "${GREEN}🎉 Algalon Worker is ready!${NC}"
        echo ""
        echo "📊 Metrics endpoint: http://$(hostname -I | awk '{print $1}'):${port}/metrics"
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
        echo "   1. Add this worker IP ($(hostname -I | awk '{print $1}'):${port}) to host's all-smi-targets.yml"
        echo "   2. Restart host VMAgent to discover this worker: docker compose restart vmagent"
        echo ""
        echo "🧪 Test commands:"
        echo "   # Basic connectivity"
        echo "   curl -f http://localhost:${port}/metrics"
        echo ""
        echo "   # Check GPU metrics"
        echo "   curl -s http://localhost:${port}/metrics | grep -E '(gpu|cuda|metal)'"
        echo ""
        echo "   # Monitor in real-time"
        echo "   watch -n 5 'curl -s http://localhost:${port}/metrics | grep all_smi_gpu_utilization'"
    else
        echo -e "${RED}❌ Failed to start all-smi Exporter. Check logs: docker compose logs${NC}"
        echo ""
        echo "🔍 Troubleshooting:"
        echo "   docker compose logs all-smi"
        echo "   docker compose ps"
        echo ""
        exit 1
    fi
}

# Parse command line arguments
ALL_SMI_VERSION="v0.9.0"
ALL_SMI_PORT="9090"

while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            ALL_SMI_VERSION="$2"
            shift 2
            ;;
        --port)
            ALL_SMI_PORT="$2"
            shift 2
            ;;
        --help|-h)
            print_usage
            exit 0
            ;;
        *)
            echo -e "${RED}❌ Unknown option: $1${NC}"
            print_usage
            exit 1
            ;;
    esac
done

# Main script logic
check_docker
setup_worker "${ALL_SMI_VERSION}" "${ALL_SMI_PORT}"