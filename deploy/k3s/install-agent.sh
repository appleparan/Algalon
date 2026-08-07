#!/usr/bin/env bash
# Algalon k3s agent install — a GPU/worker node that keeps running its Docker
# training workloads and additionally joins the cluster to host the exporter
# DaemonSets (dcgm-exporter, node-exporter, optionally all-smi).
#
# Usage:
#   K3S_URL=https://<server>:6443 K3S_TOKEN=<node-token> ./install-agent.sh
#
# The k3s agent brings its own containerd with its own socket, state directory
# and image store. It does not read, manage or restart anything owned by Docker.
#
# Environment (all optional):
#   ALGALON_CLUSTER_CIDR / ALGALON_SERVICE_CIDR   CIDRs the server was installed
#                                                 with, for the preflight check
#   INSTALL_K3S_VERSION / INSTALL_K3S_CHANNEL     passed through to get.k3s.io
#
# This script refuses to run when k3s is already installed. It never uninstalls
# or reconfigures an existing agent — there is no --force (see README.md, Rollback).
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

require_join_env() {
    local missing=()
    [ -n "${K3S_URL:-}" ] || missing+=('K3S_URL')
    [ -n "${K3S_TOKEN:-}" ] || missing+=('K3S_TOKEN')

    if [ "${#missing[@]}" -gt 0 ]; then
        cat >&2 <<EOF
error: missing required environment: ${missing[*]}

    K3S_URL=https://<server>:6443 K3S_TOKEN=<node-token> ./install-agent.sh

Read the token on the server with:  sudo cat /var/lib/rancher/k3s/server/node-token
EOF
        exit 1
    fi
}

refuse_if_installed() {
    local path
    for path in /usr/local/bin/k3s /etc/systemd/system/k3s.service \
        /etc/systemd/system/k3s-agent.service /var/lib/rancher/k3s; do
        if [ -e "$path" ]; then
            cat >&2 <<EOF
error: k3s is already installed on this host (${path} exists).

This installer never touches an existing install. If the node is already a
cluster member, nothing to do. To rejoin a different cluster, remove it by hand
first:

    /usr/local/bin/k3s-agent-uninstall.sh    # agent node
    /usr/local/bin/k3s-uninstall.sh          # server node

See deploy/k3s/README.md (Rollback).
EOF
            exit 1
        fi
    done
}

main() {
    require_join_env
    refuse_if_installed

    echo '==> preflight'
    "${SCRIPT_DIR}/preflight.sh" agent
    echo

    echo "==> installing k3s agent, joining ${K3S_URL}"
    curl -sfL https://get.k3s.io |
        INSTALL_K3S_EXEC='agent' K3S_URL="$K3S_URL" K3S_TOKEN="$K3S_TOKEN" sh -

    cat <<'EOF'

==> k3s agent installed.

Verify from the server:
    kubectl get nodes -o wide
    kubectl -n algalon get pods -o wide --field-selector spec.nodeName=<this-node>

Label the node so the GPU DaemonSets schedule on it (gpu-operator does this
automatically; a bare k3s agent does not):
    kubectl label node <this-node> nvidia.com/gpu.present=true

If k3s auto-detected nvidia-container-toolkit it created the 'nvidia'
RuntimeClass — the chart must be told to use it:
    helm upgrade algalon deploy/helm/algalon --reuse-values \
      --set dcgmExporter.runtimeClassName=nvidia

Full runbook: deploy/k3s/README.md
EOF
}

main "$@"
