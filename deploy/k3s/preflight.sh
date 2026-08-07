#!/usr/bin/env bash
# Algalon k3s preflight — read-only host checks before installing k3s.
#
# Usage:  ./preflight.sh <server|agent>
#
# This script only reads. It never installs, starts, stops, configures or
# removes anything — run it as often as you like, on any node.
#
# Environment:
#   ALGALON_CLUSTER_CIDR   pod CIDR the cluster will use   (default 10.42.0.0/16)
#   ALGALON_SERVICE_CIDR   service CIDR the cluster uses   (default 10.43.0.0/16)
#   Set both when the defaults collide with the site network; install-server.sh
#   passes them to k3s as --cluster-cidr / --service-cidr.
#
# Exit code: 0 when every required check passes (warnings are allowed), 1 otherwise.
set -euo pipefail

CLUSTER_CIDR="${ALGALON_CLUSTER_CIDR:-10.42.0.0/16}"
SERVICE_CIDR="${ALGALON_SERVICE_CIDR:-10.43.0.0/16}"
readonly RUNBOOK='deploy/k3s/README.md'

fails=0
warns=0

pass() { printf 'PASS  %s\n' "$1"; }
warn() { printf 'WARN  %s\n' "$1"; warns=$((warns + 1)); }
fail() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
note() { printf '        %s\n' "$1"; }

have() { command -v "$1" >/dev/null 2>&1; }

usage() {
    cat >&2 <<'EOF'
usage: preflight.sh <server|agent>

  server   central node that will run the k3s control plane (API on 6443)
  agent    GPU/worker node that will join an existing cluster

See deploy/k3s/README.md for the full runbook.
EOF
    exit 2
}

# --- 1. ports ---------------------------------------------------------------

# Listening sockets bound to a port, as raw `ss` lines. proto is t (tcp) or u (udp).
listeners() {
    local proto="$1" port="$2"
    ss -H -ln "-${proto}" 2>/dev/null | awk -v port="$port" '
        { addr = $4; sub(/.*:/, "", addr); if (addr == port) print }
    '
}

# check_port <t|u> <port> <required|optional> <what the port is for>
check_port() {
    local proto="$1" port="$2" level="$3" purpose="$4"
    local proto_name='tcp' found=''

    [ "$proto" = 'u' ] && proto_name='udp'

    if ! have ss; then
        warn "port ${port}/${proto_name} (${purpose}): cannot check, 'ss' not found"
        return 0
    fi

    found="$(listeners "$proto" "$port" || true)"
    if [ -z "$found" ]; then
        pass "port ${port}/${proto_name} free (${purpose})"
        return 0
    fi

    if [ "$level" = 'required' ]; then
        fail "port ${port}/${proto_name} already in use (${purpose})"
    else
        warn "port ${port}/${proto_name} already in use (${purpose})"
    fi
    while IFS= read -r line; do
        [ -n "$line" ] && note "$line"
    done <<<"$found"
    if [ "$level" = 'required' ]; then
        note "free the port, or reconfigure the service holding it, then re-run"
    else
        note "the exporter DaemonSet binds this host port; it will CrashLoop until freed"
    fi
    return 0
}

check_ports() {
    if [ "$MODE" = 'server' ]; then
        check_port t 6443 required 'kube-apiserver'
        printf 'NOTE  a k3s server also runs an embedded agent — run "./preflight.sh agent" here too\n'
    else
        check_port t 10250 required 'kubelet'
        check_port u 8472 required 'flannel VXLAN'
        check_port t 9100 optional 'node-exporter hostPort'
        check_port t 9400 optional 'dcgm-exporter hostPort'
    fi
}

# --- 2. CIDR overlap --------------------------------------------------------

ip_to_int() {
    local IFS='.' a b c d
    read -r a b c d <<<"$1"
    printf '%s\n' "$(((a << 24) + (b << 16) + (c << 8) + d))"
}

# cidr_overlap <a.b.c.d/len> <a.b.c.d/len> — true when the two ranges intersect.
cidr_overlap() {
    local len_a="${1##*/}" len_b="${2##*/}" len mask
    len="$len_a"
    if [ "$len_b" -lt "$len" ]; then
        len="$len_b"
    fi
    mask=$(((0xFFFFFFFF << (32 - len)) & 0xFFFFFFFF))
    [ "$(($(ip_to_int "${1%%/*}") & mask))" -eq "$(($(ip_to_int "${2%%/*}") & mask))" ]
}

check_cidrs() {
    local line route target overlaps=()

    if ! have ip; then
        warn "CIDR overlap: cannot check, 'ip' not found"
        return 0
    fi

    while IFS= read -r line; do
        route="${line%% *}"
        case "$route" in
            default | multicast | broadcast | local | unreachable | blackhole | prohibit | throw) continue ;;
        esac
        if ! [[ "$route" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$ ]]; then
            continue
        fi
        case "$route" in
            */*) : ;;
            *) route="${route}/32" ;;
        esac
        for target in "$CLUSTER_CIDR" "$SERVICE_CIDR"; do
            if cidr_overlap "$route" "$target"; then
                overlaps+=("${target} <- ${line}")
            fi
        done
    done < <(ip -4 route show)

    if [ "${#overlaps[@]}" -eq 0 ]; then
        pass "no route overlaps ${CLUSTER_CIDR} (pods) or ${SERVICE_CIDR} (services)"
        return 0
    fi

    fail "existing routes overlap the cluster CIDRs — pod/service traffic would blackhole"
    for line in "${overlaps[@]}"; do
        note "$line"
    done
    note "if these are cni0/flannel.* routes, an earlier k3s is still installed (see below)"
    note "otherwise pick free ranges and re-run both this script and the installer with:"
    note "  ALGALON_CLUSTER_CIDR=10.52.0.0/16 ALGALON_SERVICE_CIDR=10.53.0.0/16"
    note "which install-server.sh passes as --cluster-cidr / --service-cidr"
    return 0
}

# --- 3. nvidia-container-toolkit -------------------------------------------

check_nvidia_toolkit() {
    local version=''
    if have nvidia-ctk; then
        version="$(nvidia-ctk --version 2>/dev/null | head -1 || true)"
        pass "nvidia-container-toolkit present (${version:-version unknown})"
        note "k3s auto-detects it and creates the 'nvidia' RuntimeClass — install the chart with"
        note "  --set dcgmExporter.runtimeClassName=nvidia"
        return 0
    fi
    warn "nvidia-container-toolkit not found (nvidia-ctk)"
    note "GPU nodes need it for dcgm-exporter; CPU-only nodes do not"
    note "installing it does NOT require editing /etc/docker/daemon.json for k3s"
}

# --- 4. host firewall -------------------------------------------------------

check_firewall() {
    local active=()

    if have systemctl && systemctl is-active --quiet firewalld 2>/dev/null; then
        active+=('firewalld')
    fi
    if have ufw && ufw status 2>/dev/null | head -1 | grep -q 'Status: active'; then
        active+=('ufw')
    fi

    if [ "${#active[@]}" -eq 0 ]; then
        pass 'no active host firewall detected (firewalld/ufw)'
        return 0
    fi

    warn "active host firewall: ${active[*]}"
    note "k3s manages its own iptables rules; a host firewall can still drop node-to-node"
    note "traffic on 6443/tcp, 10250/tcp and 8472/udp — see ${RUNBOOK} (Firewalls)"
}

# --- 5. existing k3s install ------------------------------------------------

check_existing_k3s() {
    local path found=()

    for path in /usr/local/bin/k3s /usr/local/bin/k3s-uninstall.sh \
        /usr/local/bin/k3s-agent-uninstall.sh /etc/systemd/system/k3s.service \
        /etc/systemd/system/k3s-agent.service /etc/rancher/k3s /var/lib/rancher/k3s; do
        if [ -e "$path" ]; then
            found+=("$path")
        fi
    done

    if [ "${#found[@]}" -eq 0 ]; then
        pass 'no existing k3s installation'
        return 0
    fi

    fail 'k3s is already installed on this host'
    for path in "${found[@]}"; do
        note "$path"
    done
    note "the install scripts never touch an existing cluster — remove it by hand first:"
    note "  /usr/local/bin/k3s-uninstall.sh          # server node"
    note "  /usr/local/bin/k3s-agent-uninstall.sh    # agent node"
    note "see ${RUNBOOK} (Rollback) — and confirm you are not wiping a live cluster"
}

# --- main -------------------------------------------------------------------

main() {
    [ "$#" -eq 1 ] || usage
    MODE="$1"
    case "$MODE" in
        server | agent) : ;;
        *) usage ;;
    esac
    readonly MODE

    printf 'Algalon k3s preflight — mode=%s host=%s\n' "$MODE" "$(hostname)"
    printf 'pod CIDR %s / service CIDR %s\n\n' "$CLUSTER_CIDR" "$SERVICE_CIDR"

    check_ports
    check_cidrs
    check_nvidia_toolkit
    check_firewall
    check_existing_k3s

    printf '\n'
    if [ "$fails" -gt 0 ]; then
        printf 'preflight FAILED: %d blocking issue(s), %d warning(s)\n' "$fails" "$warns"
        return 1
    fi
    printf 'preflight OK: 0 blocking issues, %d warning(s)\n' "$warns"
}

main "$@"
