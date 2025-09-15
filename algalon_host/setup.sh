#!/bin/bash

# Algalon Host Setup Script
# Sets up monitoring host with VictoriaMetrics, Grafana, and VMAgent
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_usage() {
    echo "🌟 Algalon Host Setup - Monitoring & Visualization"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --help         Show this help message"
    echo ""
    echo "Description:"
    echo "  Sets up the monitoring host with VictoriaMetrics, Grafana, and VMAgent"
    echo "  that collects metrics from remote all-smi worker nodes."
    echo ""
    echo "Examples:"
    echo "  $0              # Setup monitoring host"
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

setup_host() {
    echo -e "${BLUE}🏗️  Setting up Algalon Host (Monitoring & Visualization)...${NC}"
    
    # Check if targets are configured
    if grep -q "localhost:9090" node/targets/all-smi-targets.yml; then
        echo -e "${YELLOW}⚠️  Worker targets are using localhost${NC}"
        echo "   Please update node/targets/all-smi-targets.yml with actual worker IPs"
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
    echo "   1. Update worker IPs in: node/targets/all-smi-targets.yml"
    echo "   2. Deploy workers on GPU nodes using algalon_worker/setup.sh"
    echo "   3. Restart VMAgent: docker compose restart vmagent"
    echo ""
    echo "🔧 Configuration files:"
    echo "   - Worker targets: node/targets/all-smi-targets.yml"
    echo "   - Grafana dashboards: grafana/dashboards/"
    echo "   - VMAgent config: prometheus.yml"
}

# Main script logic
case "${1:-}" in
    --help|-h)
        print_usage
        ;;
    "")
        check_docker
        setup_host
        ;;
    *)
        echo -e "${RED}❌ Unknown option: $1${NC}"
        print_usage
        exit 1
        ;;
esac