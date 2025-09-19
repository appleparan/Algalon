#!/bin/bash
# Worker Discovery Script for Algalon Monitoring Host
# Automatically discovers and registers workers in the network

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" >&2
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

# Default configuration
DISCOVERY_INTERVAL=300  # 5 minutes
NETWORK_RANGE=""
PORT_RANGE="9090"
TARGETS_FILE="/opt/Algalon/algalon_host/node/targets/all-smi-targets.yml"
DISCOVERY_LOG="/var/log/worker-discovery.log"
REGISTRATION_SCRIPT="/opt/Algalon/algalon_host/scripts/register-worker.sh"

# Usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Automatically discover and register Algalon workers in the network.

Options:
    -n, --network CIDR      Network range to scan (e.g., 192.168.1.0/24)
    -p, --port PORT         Port to scan for workers (default: 9090)
    -i, --interval SECONDS  Discovery interval in seconds (default: 300)
    -f, --file FILE         Path to targets configuration file
    -l, --log FILE          Path to discovery log file
    -d, --daemon            Run as daemon (continuous discovery)
    --dry-run               Show what would be discovered without registration
    -h, --help              Show this help message

Examples:
    # Discover workers in local network once
    $0 --network 192.168.1.0/24

    # Run continuous discovery every 5 minutes
    $0 --network 192.168.1.0/24 --daemon

    # Discover on custom port
    $0 --network 10.0.0.0/8 --port 9091

    # Dry run to see what would be discovered
    $0 --network 192.168.1.0/24 --dry-run
EOF
}

# Parse command line arguments
parse_args() {
    DAEMON_MODE=false
    DRY_RUN=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--network)
                NETWORK_RANGE="$2"
                shift 2
                ;;
            -p|--port)
                PORT_RANGE="$2"
                shift 2
                ;;
            -i|--interval)
                DISCOVERY_INTERVAL="$2"
                shift 2
                ;;
            -f|--file)
                TARGETS_FILE="$2"
                shift 2
                ;;
            -l|--log)
                DISCOVERY_LOG="$2"
                shift 2
                ;;
            -d|--daemon)
                DAEMON_MODE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                error "Unexpected argument: $1"
                usage
                exit 1
                ;;
        esac
    done

    if [ -z "$NETWORK_RANGE" ]; then
        # Try to auto-detect network range
        NETWORK_RANGE=$(ip route | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+' | head -1 | awk '{print $1}')
        if [ -z "$NETWORK_RANGE" ]; then
            error "Network range not specified and could not be auto-detected"
            error "Please specify network range with --network option"
            exit 1
        fi
        log "Auto-detected network range: $NETWORK_RANGE"
    fi
}

# Check dependencies
check_dependencies() {
    local missing_deps=()

    if ! command -v nmap >/dev/null 2>&1; then
        missing_deps+=("nmap")
    fi

    if ! command -v curl >/dev/null 2>&1; then
        missing_deps+=("curl")
    fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        error "Missing required dependencies: ${missing_deps[*]}"
        error "Please install missing packages:"
        error "  Ubuntu/Debian: sudo apt-get install ${missing_deps[*]}"
        error "  CentOS/RHEL: sudo yum install ${missing_deps[*]}"
        exit 1
    fi
}

# Discover workers in network
discover_workers() {
    local network="$1"
    local port="$2"

    log "Scanning network $network for workers on port $port..."

    # Use nmap to scan for open ports
    local scan_result
    scan_result=$(nmap -p "$port" --open -oG - "$network" 2>/dev/null | grep "Ports:" | awk '{print $2}')

    local discovered_workers=()
    for ip in $scan_result; do
        local target="$ip:$port"
        log "Testing potential worker at $target..."

        # Test if it's actually an Algalon worker
        if test_algalon_worker "$target"; then
            discovered_workers+=("$target")
            success "Discovered Algalon worker: $target"
        fi
    done

    echo "${discovered_workers[@]}"
}

# Test if target is an Algalon worker
test_algalon_worker() {
    local target="$1"
    local timeout=5

    # Test metrics endpoint
    if curl -f -s --max-time "$timeout" "http://$target/metrics" | grep -q "nvidia_smi\|gpu\|all_smi" 2>/dev/null; then
        return 0
    fi

    return 1
}

# Check if worker is already registered
is_worker_registered() {
    local target="$1"

    if [ ! -f "$TARGETS_FILE" ]; then
        return 1
    fi

    grep -q "$target" "$TARGETS_FILE" 2>/dev/null
}

# Register discovered workers
register_workers() {
    local workers=("$@")

    if [ ${#workers[@]} -eq 0 ]; then
        log "No new workers to register"
        return 0
    fi

    local new_workers=()
    for worker in "${workers[@]}"; do
        if ! is_worker_registered "$worker"; then
            new_workers+=("$worker")
        fi
    done

    if [ ${#new_workers[@]} -eq 0 ]; then
        log "All discovered workers are already registered"
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        log "Would register new workers: ${new_workers[*]}"
        return 0
    fi

    log "Registering ${#new_workers[@]} new workers: ${new_workers[*]}"

    if [ -x "$REGISTRATION_SCRIPT" ]; then
        "$REGISTRATION_SCRIPT" "${new_workers[@]}"
    else
        warn "Registration script not found or not executable: $REGISTRATION_SCRIPT"
        log "Manually add these workers to $TARGETS_FILE:"
        for worker in "${new_workers[@]}"; do
            log "  - targets: ['$worker']"
        done
    fi
}

# Single discovery run
run_discovery() {
    log "Starting worker discovery..."
    log "Network: $NETWORK_RANGE, Port: $PORT_RANGE"

    # Discover workers
    local discovered_workers
    discovered_workers=($(discover_workers "$NETWORK_RANGE" "$PORT_RANGE"))

    if [ ${#discovered_workers[@]} -eq 0 ]; then
        log "No Algalon workers discovered in network $NETWORK_RANGE"
        return 0
    fi

    log "Discovered ${#discovered_workers[@]} workers: ${discovered_workers[*]}"

    # Register new workers
    register_workers "${discovered_workers[@]}"

    log "Discovery run completed"
}

# Daemon mode
run_daemon() {
    log "Starting worker discovery daemon"
    log "Discovery interval: ${DISCOVERY_INTERVAL}s"
    log "Network: $NETWORK_RANGE"
    log "Port: $PORT_RANGE"
    log "Log file: $DISCOVERY_LOG"

    # Create log directory
    mkdir -p "$(dirname "$DISCOVERY_LOG")"

    # Main daemon loop
    while true; do
        {
            echo "=== Discovery run at $(date) ==="
            run_discovery
            echo ""
        } >> "$DISCOVERY_LOG" 2>&1

        log "Sleeping for ${DISCOVERY_INTERVAL}s..."
        sleep "$DISCOVERY_INTERVAL"
    done
}

# Setup signal handlers for daemon
setup_signal_handlers() {
    trap 'log "Received SIGTERM, shutting down..."; exit 0' TERM
    trap 'log "Received SIGINT, shutting down..."; exit 0' INT
}

# Main function
main() {
    log "Algalon Worker Discovery Starting"

    parse_args "$@"
    check_dependencies

    log "Configuration:"
    log "  Network range: $NETWORK_RANGE"
    log "  Port: $PORT_RANGE"
    log "  Discovery interval: ${DISCOVERY_INTERVAL}s"
    log "  Daemon mode: $DAEMON_MODE"
    log "  Dry run: $DRY_RUN"
    log "  Targets file: $TARGETS_FILE"

    if [ "$DAEMON_MODE" = true ]; then
        setup_signal_handlers
        run_daemon
    else
        run_discovery
    fi

    success "Worker discovery completed"
}

# Run main function
main "$@"