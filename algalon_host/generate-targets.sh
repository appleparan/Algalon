#!/bin/bash

# Algalon Targets Generator
# Generates all-smi-targets.yml from environment variables
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGETS_FILE="${SCRIPT_DIR}/node/targets/all-smi-targets.yml"
TEMPLATE_FILE="${SCRIPT_DIR}/node/targets/all-smi-targets.yml.template"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_usage() {
    echo "🎯 Algalon Targets Generator"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Environment Variables:"
    echo "  ALGALON_TARGETS       Comma-separated list of worker targets"
    echo "                        Format: 'host1:port1,host2:port2,host3:port3'"
    echo "                        Example: 'worker1:9090,worker2:9090,10.0.1.100:9091'"
    echo ""
    echo "  ALGALON_CLUSTER       Cluster name (default: production)"
    echo "  ALGALON_ENVIRONMENT   Environment name (default: gpu-cluster)"
    echo "  ALGALON_DEFAULT_PORT  Default port if not specified (default: 9090)"
    echo ""
    echo "Options:"
    echo "  --targets <list>      Override ALGALON_TARGETS"
    echo "  --cluster <name>      Override ALGALON_CLUSTER"
    echo "  --environment <env>   Override ALGALON_ENVIRONMENT"
    echo "  --help                Show this help message"
    echo ""
    echo "Examples:"
    echo "  # Using environment variables"
    echo "  export ALGALON_TARGETS='worker1:9090,worker2:9090,10.0.1.100:9091'"
    echo "  $0"
    echo ""
    echo "  # Using command line"
    echo "  $0 --targets 'localhost:9090,worker1:9090' --cluster staging"
    echo ""
    echo "  # For Google Cloud with internal IPs"
    echo "  $0 --targets '10.128.0.2:9090,10.128.0.3:9090,10.128.0.4:9090'"
    echo ""
}

generate_targets() {
    local targets="$1"
    local cluster="${2:-production}"
    local environment="${3:-gpu-cluster}"
    local default_port="${4:-9090}"

    if [[ -z "$targets" ]]; then
        echo -e "${RED}❌ No targets specified. Use ALGALON_TARGETS environment variable or --targets option.${NC}"
        echo ""
        print_usage
        exit 1
    fi

    echo -e "${BLUE}🎯 Generating targets configuration...${NC}"
    echo "   📍 Targets: $targets"
    echo "   🏷️  Cluster: $cluster"
    echo "   🌍 Environment: $environment"
    echo "   🔌 Default port: $default_port"
    echo ""

    # Create targets configuration
    targets_config="- targets:"

    # Process comma-separated targets
    IFS=',' read -ra TARGET_ARRAY <<< "$targets"
    for target in "${TARGET_ARRAY[@]}"; do
        # Trim whitespace
        target=$(echo "$target" | xargs)

        # Add default port if not specified
        if [[ ! "$target" =~ :[0-9]+$ ]]; then
            target="${target}:${default_port}"
        fi

        targets_config="${targets_config}
    - '${target}'"
    done

    targets_config="${targets_config}
  labels:
    job: 'all-smi'
    cluster: '${cluster}'
    environment: '${environment}'
    monitoring_type: 'comprehensive'  # all-smi provides GPU+CPU+Memory"

    # Check if template exists, otherwise create basic template
    if [[ ! -f "$TEMPLATE_FILE" ]]; then
        echo -e "${YELLOW}⚠️  Template file not found, creating basic configuration${NC}"
        echo "# targets/all-smi-targets.yml" > "$TARGETS_FILE"
        echo "# Configuration for all-smi GPU/CPU monitoring worker nodes" >> "$TARGETS_FILE"
        echo "# This file is auto-generated from environment variables" >> "$TARGETS_FILE"
        echo "" >> "$TARGETS_FILE"
        echo "$targets_config" >> "$TARGETS_FILE"
    else
        # Use template and replace placeholder
        sed "s|{{TARGETS_CONFIG}}|$targets_config|g" "$TEMPLATE_FILE" > "$TARGETS_FILE"
    fi

    echo -e "${GREEN}✅ Targets configuration generated: $TARGETS_FILE${NC}"
    echo ""
    echo "📋 Generated configuration:"
    echo "$targets_config"
    echo ""
    echo "🔄 To apply changes, restart VMAgent:"
    echo "   docker compose restart vmagent"
    echo ""
}

# Parse command line arguments
TARGETS="${ALGALON_TARGETS:-}"
CLUSTER="${ALGALON_CLUSTER:-production}"
ENVIRONMENT="${ALGALON_ENVIRONMENT:-gpu-cluster}"
DEFAULT_PORT="${ALGALON_DEFAULT_PORT:-9090}"

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
        *)
            echo -e "${RED}❌ Unknown option: $1${NC}"
            print_usage
            exit 1
            ;;
    esac
done

# Main script logic
generate_targets "$TARGETS" "$CLUSTER" "$ENVIRONMENT" "$DEFAULT_PORT"