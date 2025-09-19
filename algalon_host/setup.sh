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
    echo "  --targets <list>      Comma-separated list of worker targets (host:port)"
    echo "  --cluster <name>      Cluster name (default: production)"
    echo "  --environment <env>   Environment name (default: gpu-cluster)"
    echo "  --help                Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  ALGALON_TARGETS       Worker targets (same as --targets)"
    echo "  ALGALON_CLUSTER       Cluster name (same as --cluster)"
    echo "  ALGALON_ENVIRONMENT   Environment name (same as --environment)"
    echo ""
    echo "Description:"
    echo "  Sets up the monitoring host with VictoriaMetrics, Grafana, and VMAgent"
    echo "  that collects metrics from remote all-smi worker nodes."
    echo ""
    echo "Examples:"
    echo "  $0                                          # Setup with localhost:9090"
    echo "  $0 --targets 'worker1:9090,worker2:9090'   # Setup with specific workers"
    echo "  $0 --targets '10.0.1.100:9090,10.0.1.101:9090' --cluster staging"
    echo ""
    echo "  # Using environment variables"
    echo "  export ALGALON_TARGETS='worker1:9090,worker2:9090'"
    echo "  export ALGALON_CLUSTER='production'"
    echo "  $0"
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
    local targets="${1:-${ALGALON_TARGETS:-localhost:9090}}"
    local cluster="${2:-${ALGALON_CLUSTER:-production}}"
    local environment="${3:-${ALGALON_ENVIRONMENT:-gpu-cluster}}"

    echo -e "${BLUE}🏗️  Setting up Algalon Host (Monitoring & Visualization)...${NC}"
    echo "   🎯 Targets: $targets"
    echo "   🏷️  Cluster: $cluster"
    echo "   🌍 Environment: $environment"
    echo ""

    # Generate targets configuration
    echo "🎯 Generating targets configuration..."
    export ALGALON_TARGETS="$targets"
    export ALGALON_CLUSTER="$cluster"
    export ALGALON_ENVIRONMENT="$environment"

    ./generate-targets.sh

    if [[ "$targets" == "localhost:9090" ]]; then
        echo -e "${YELLOW}⚠️  Using localhost:9090 as target${NC}"
        echo "   For production, specify actual worker IPs using --targets option"
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
    if [[ "$targets" == "localhost:9090" ]]; then
        echo "   1. Deploy workers on GPU nodes using algalon_worker/setup.sh"
        echo "   2. Update targets: ./generate-targets.sh --targets 'worker1:9090,worker2:9090'"
        echo "   3. Restart VMAgent: docker compose restart vmagent"
    else
        echo "   1. Deploy workers on GPU nodes using algalon_worker/setup.sh"
        echo "   2. Verify workers are reachable at configured targets"
        echo "   3. Monitor metrics in Grafana dashboard"
    fi
    echo ""
    echo "🔧 Configuration files:"
    echo "   - Worker targets: node/targets/all-smi-targets.yml"
    echo "   - Grafana dashboards: grafana/dashboards/"
    echo "   - VMAgent config: prometheus.yml"
}

# Parse command line arguments
TARGETS="${ALGALON_TARGETS:-}"
CLUSTER="${ALGALON_CLUSTER:-production}"
ENVIRONMENT="${ALGALON_ENVIRONMENT:-gpu-cluster}"

while [[ $# -gt 0 ]]; do
    case $1 in
        --targets)
            TARGETS="$2"
            shift 2
            ;;
        --cluster)
            CLUSTER="$2"
            shift 2
            ;;
        --environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --help|-h)
            print_usage
            exit 0
            ;;
        "")
            break
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
setup_host "$TARGETS" "$CLUSTER" "$ENVIRONMENT"