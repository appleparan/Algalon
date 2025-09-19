#!/bin/bash
# Worker Registration Script for Algalon Monitoring Host
# This script helps register new workers with the monitoring system

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
TARGETS_FILE="/opt/Algalon/algalon_host/node/targets/all-smi-targets.yml"
BACKUP_DIR="/opt/Algalon/algalon_host/backups"
DRY_RUN=false

# Usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS] WORKER_TARGET [WORKER_TARGET...]

Register one or more workers with Algalon monitoring host.

Arguments:
    WORKER_TARGET       Worker target in format IP:PORT (e.g., 192.168.1.100:9090)

Options:
    -f, --file FILE     Path to targets configuration file (default: $TARGETS_FILE)
    -d, --dry-run       Show what would be done without making changes
    -b, --backup        Create backup before making changes (default: enabled)
    --no-backup         Skip backup creation
    -r, --restart       Restart VMAgent after registration (default: enabled)
    --no-restart        Skip VMAgent restart
    -h, --help          Show this help message

Examples:
    # Register single worker
    $0 192.168.1.100:9090

    # Register multiple workers
    $0 192.168.1.100:9090 192.168.1.101:9090

    # Dry run to see what would be changed
    $0 --dry-run 192.168.1.100:9090

    # Register without restarting VMAgent
    $0 --no-restart 192.168.1.100:9090
EOF
}

# Parse command line arguments
parse_args() {
    RESTART_VMAGENT=true
    CREATE_BACKUP=true
    WORKER_TARGETS=()

    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--file)
                TARGETS_FILE="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -b|--backup)
                CREATE_BACKUP=true
                shift
                ;;
            --no-backup)
                CREATE_BACKUP=false
                shift
                ;;
            -r|--restart)
                RESTART_VMAGENT=true
                shift
                ;;
            --no-restart)
                RESTART_VMAGENT=false
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
                WORKER_TARGETS+=("$1")
                shift
                ;;
        esac
    done

    if [ ${#WORKER_TARGETS[@]} -eq 0 ]; then
        error "No worker targets specified"
        usage
        exit 1
    fi
}

# Validate worker target format
validate_target() {
    local target="$1"
    if [[ ! "$target" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}:[0-9]+$ ]] && \
       [[ ! "$target" =~ ^[a-zA-Z0-9.-]+:[0-9]+$ ]]; then
        error "Invalid target format: $target"
        error "Expected format: IP:PORT or HOSTNAME:PORT"
        return 1
    fi
    return 0
}

# Test worker connectivity
test_worker() {
    local target="$1"
    local host=$(echo "$target" | cut -d: -f1)
    local port=$(echo "$target" | cut -d: -f2)

    log "Testing connectivity to $target..."

    # Test basic connectivity
    if ! timeout 5 bash -c "cat < /dev/null > /dev/tcp/$host/$port" 2>/dev/null; then
        warn "Cannot connect to $target (port may be closed or host unreachable)"
        return 1
    fi

    # Test metrics endpoint
    if command -v curl >/dev/null 2>&1; then
        if curl -f -s "http://$target/metrics" >/dev/null 2>&1; then
            success "Worker $target is responding with metrics"
            return 0
        else
            warn "Worker $target is reachable but not serving metrics at /metrics"
            return 1
        fi
    else
        success "Worker $target is reachable (curl not available to test metrics)"
        return 0
    fi
}

# Create backup of targets file
create_backup() {
    if [ "$CREATE_BACKUP" = false ]; then
        return 0
    fi

    if [ ! -f "$TARGETS_FILE" ]; then
        warn "Targets file does not exist: $TARGETS_FILE"
        return 0
    fi

    mkdir -p "$BACKUP_DIR"
    local backup_file="$BACKUP_DIR/all-smi-targets.yml.$(date +%Y%m%d_%H%M%S)"

    if [ "$DRY_RUN" = true ]; then
        log "Would create backup: $backup_file"
        return 0
    fi

    cp "$TARGETS_FILE" "$backup_file"
    success "Created backup: $backup_file"
}

# Check if target already exists
target_exists() {
    local target="$1"
    if [ ! -f "$TARGETS_FILE" ]; then
        return 1
    fi
    grep -q "$target" "$TARGETS_FILE" 2>/dev/null
}

# Add worker target to configuration
add_worker() {
    local target="$1"

    if target_exists "$target"; then
        warn "Worker $target is already registered"
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        log "Would add worker: $target"
        return 0
    fi

    # Create targets file if it doesn't exist
    if [ ! -f "$TARGETS_FILE" ]; then
        mkdir -p "$(dirname "$TARGETS_FILE")"
        cat > "$TARGETS_FILE" << 'EOF'
# Algalon Worker Targets Configuration
# Auto-generated by register-worker.sh

scrape_configs:
  - job_name: 'all-smi'
    static_configs:
EOF
    fi

    # Add the target
    echo "      - targets: ['$target']" >> "$TARGETS_FILE"
    success "Added worker: $target"
}

# Restart VMAgent service
restart_vmagent() {
    if [ "$RESTART_VMAGENT" = false ]; then
        log "Skipping VMAgent restart (--no-restart specified)"
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        log "Would restart VMAgent service"
        return 0
    fi

    log "Restarting VMAgent service..."

    # Check if we're in the Algalon host directory
    if [ -f "/opt/Algalon/algalon_host/docker-compose.yml" ]; then
        cd /opt/Algalon/algalon_host
        if docker-compose restart vmagent 2>/dev/null; then
            success "VMAgent service restarted"
        else
            warn "Failed to restart VMAgent with docker-compose, trying docker restart"
            if docker restart vmagent 2>/dev/null; then
                success "VMAgent container restarted"
            else
                error "Failed to restart VMAgent service"
                return 1
            fi
        fi
    else
        warn "Could not find docker-compose.yml, trying direct docker restart"
        if docker restart vmagent 2>/dev/null; then
            success "VMAgent container restarted"
        else
            error "Failed to restart VMAgent service"
            return 1
        fi
    fi
}

# Display current configuration
show_current_config() {
    log "Current targets configuration:"
    if [ -f "$TARGETS_FILE" ]; then
        echo "----------------------------------------"
        cat "$TARGETS_FILE"
        echo "----------------------------------------"
    else
        warn "Targets file does not exist: $TARGETS_FILE"
    fi
}

# Main function
main() {
    log "Starting Algalon Worker Registration"

    parse_args "$@"

    log "Configuration:"
    log "  Targets file: $TARGETS_FILE"
    log "  Dry run: $DRY_RUN"
    log "  Create backup: $CREATE_BACKUP"
    log "  Restart VMAgent: $RESTART_VMAGENT"
    log "  Workers to register: ${WORKER_TARGETS[*]}"

    # Validate all targets first
    for target in "${WORKER_TARGETS[@]}"; do
        if ! validate_target "$target"; then
            exit 1
        fi
    done

    # Test connectivity to all workers
    log "Testing worker connectivity..."
    failed_workers=()
    for target in "${WORKER_TARGETS[@]}"; do
        if ! test_worker "$target"; then
            failed_workers+=("$target")
        fi
    done

    if [ ${#failed_workers[@]} -gt 0 ]; then
        warn "Some workers failed connectivity tests: ${failed_workers[*]}"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Registration cancelled"
            exit 1
        fi
    fi

    # Show current configuration
    show_current_config

    # Create backup
    create_backup

    # Register workers
    log "Registering workers..."
    for target in "${WORKER_TARGETS[@]}"; do
        add_worker "$target"
    done

    # Restart VMAgent
    restart_vmagent

    if [ "$DRY_RUN" = true ]; then
        log "Dry run completed - no changes were made"
    else
        success "Worker registration completed successfully!"
        log "Workers registered: ${WORKER_TARGETS[*]}"
        log "You can verify registration by checking Grafana dashboard"
    fi
}

# Run main function
main "$@"