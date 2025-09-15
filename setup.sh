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
    echo "  --host                     Setup monitoring host (VictoriaMetrics + Grafana)"
    echo "  --worker                   Setup hardware worker node (all-smi Exporter)"
    echo "  --single-node              Setup all components on single node (development)"
    echo "  --version <ver>            all-smi version for worker (default: v0.9.0)"
    echo "  --port <port>              Port for all-smi API (default: 9090)"
    echo "  --help                     Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --host                           # Setup monitoring host"
    echo "  $0 --worker                         # Setup worker (v0.9.0, port 9090)"
    echo "  $0 --worker --version v0.8.0        # Worker with specific version"
    echo "  $0 --worker --port 8080             # Worker with custom port"
    echo "  $0 --single-node --port 9091        # Single-node with custom port"
    echo ""
    echo "📁 Individual component setup:"
    echo "  cd algalon_host && ./setup.sh                    # Host setup only"
    echo "  cd algalon_worker && ./setup.sh --version v0.8.0 # Worker with version"
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
    echo "   Using dedicated host setup script..."
    echo ""
    
    cd "${SCRIPT_DIR}/algalon_host"
    ./setup.sh
}

setup_worker() {
    local version="${1:-v0.9.0}"
    local port="${2:-9090}"
    
    echo -e "${BLUE}🏗️  Setting up Algalon Worker (Hardware Metrics Exporter)...${NC}"
    echo "   Using dedicated worker setup script..."
    echo ""
    
    cd "${SCRIPT_DIR}/algalon_worker"
    ./setup.sh --version "${version}" --port "${port}"
}

setup_single_node() {
    local version="${1:-v0.9.0}"
    local port="${2:-9090}"
    
    echo -e "${BLUE}🏗️  Setting up Algalon Single Node (All components)...${NC}"
    echo "   Setting up worker and host components in sequence..."
    echo ""
    
    # Setup worker first using dedicated script
    echo -e "${YELLOW}📦 Step 1: Setting up worker component${NC}"
    cd "${SCRIPT_DIR}/algalon_worker"
    ./setup.sh --version "${version}" --port "${port}"
    
    # Ensure target points to localhost for single-node
    echo -e "${YELLOW}📦 Step 2: Configuring host for single-node${NC}"
    cd "${SCRIPT_DIR}/algalon_host"
    
    if ! grep -q "localhost:${port}" node/targets/all-smi-targets.yml; then
        echo "# Single-node configuration" > node/targets/all-smi-targets.yml
        echo "- targets:" >> node/targets/all-smi-targets.yml
        echo "    - 'localhost:${port}'" >> node/targets/all-smi-targets.yml
        echo "  labels:" >> node/targets/all-smi-targets.yml
        echo "    job: 'all-smi'" >> node/targets/all-smi-targets.yml
        echo "    cluster: 'development'" >> node/targets/all-smi-targets.yml
        echo "    monitoring_type: 'comprehensive'" >> node/targets/all-smi-targets.yml
    fi
    
    # Setup host using dedicated script
    echo -e "${YELLOW}📦 Step 3: Setting up host component${NC}"
    ./setup.sh
    
    echo ""
    echo -e "${GREEN}🎉 Algalon Single Node is ready!${NC}"
    echo ""
    echo "✨ Navigate to Grafana and explore:"
    echo "   - GPU Monitoring Dashboard (enhanced with all-smi)"
    echo "   - All-SMI System Monitoring Dashboard (NEW)"
}

# Parse command line arguments
MODE=""
ALL_SMI_VERSION="v0.9.0"
ALL_SMI_PORT="9090"

while [[ $# -gt 0 ]]; do
    case $1 in
        --host)
            MODE="host"
            shift
            ;;
        --worker)
            MODE="worker"
            shift
            ;;
        --single-node)
            MODE="single-node"
            shift
            ;;
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
if [[ -z "$MODE" ]]; then
    echo -e "${YELLOW}⚠️  No mode specified. Use --help to see available options.${NC}"
    print_usage
    exit 1
fi

check_docker

case "$MODE" in
    host)
        setup_host
        ;;
    worker)
        setup_worker "${ALL_SMI_VERSION}" "${ALL_SMI_PORT}"
        ;;
    single-node)
        setup_single_node "${ALL_SMI_VERSION}" "${ALL_SMI_PORT}"
        ;;
esac
