#!/usr/bin/env bash
# Algalon k3s server install — the central node that runs the control plane and
# the Algalon host stack (VictoriaMetrics, vmagent, vmalert, Alertmanager, Grafana).
#
# Usage:  ./install-server.sh
#
# Traefik, ServiceLB and metrics-server are disabled on purpose: they grab host
# ports (80/443 via ServiceLB) on machines that are also running Docker training
# workloads. Algalon exposes nothing but ClusterIP Services.
#
# Environment (all optional):
#   ALGALON_CLUSTER_CIDR   pod CIDR      -> --cluster-cidr (default 10.42.0.0/16)
#   ALGALON_SERVICE_CIDR   service CIDR  -> --service-cidr (default 10.43.0.0/16)
#   INSTALL_K3S_VERSION / INSTALL_K3S_CHANNEL   passed through to get.k3s.io
#
# This script refuses to run when k3s is already installed. It never uninstalls,
# overwrites or reconfigures an existing cluster — there is no --force. Removing
# a cluster is a deliberate manual step (see README.md, Rollback).
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly TOKEN_PATH='/var/lib/rancher/k3s/server/node-token'
readonly KUBECONFIG_PATH='/etc/rancher/k3s/k3s.yaml'

refuse_if_installed() {
    local path
    for path in /usr/local/bin/k3s /etc/systemd/system/k3s.service \
        /etc/systemd/system/k3s-agent.service /var/lib/rancher/k3s; do
        if [ -e "$path" ]; then
            cat >&2 <<EOF
error: k3s is already installed on this host (${path} exists).

This installer never touches an existing cluster. If you really want to
reinstall, remove the old one by hand first — and make sure it is not serving a
live cluster:

    /usr/local/bin/k3s-uninstall.sh          # server node
    /usr/local/bin/k3s-agent-uninstall.sh    # agent node

See deploy/k3s/README.md (Rollback).
EOF
            exit 1
        fi
    done
}

main() {
    local exec_args

    refuse_if_installed

    echo '==> preflight'
    "${SCRIPT_DIR}/preflight.sh" server
    echo

    exec_args='server --disable traefik --disable servicelb --disable metrics-server'
    if [ -n "${ALGALON_CLUSTER_CIDR:-}" ]; then
        exec_args="${exec_args} --cluster-cidr ${ALGALON_CLUSTER_CIDR}"
    fi
    if [ -n "${ALGALON_SERVICE_CIDR:-}" ]; then
        exec_args="${exec_args} --service-cidr ${ALGALON_SERVICE_CIDR}"
    fi

    echo "==> installing k3s server: ${exec_args}"
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="${exec_args}" sh -

    cat <<EOF

==> k3s server installed.

Node token (agents need it, root-readable only):
    sudo cat ${TOKEN_PATH}

Kubeconfig:
    export KUBECONFIG=${KUBECONFIG_PATH}     # or copy it, rewriting 127.0.0.1
    sudo k3s kubectl get nodes

Next steps:
  1. Create the Slack webhook Secret (the chart refuses to render without it):
       kubectl -n algalon create secret generic algalon-slack \\
         --from-literal=slack_webhook_critical='https://hooks.slack.com/...' \\
         --from-literal=slack_webhook_warning='https://hooks.slack.com/...'
  2. Install the stack:
       make helm-sync
       helm install algalon deploy/helm/algalon --namespace algalon --create-namespace \\
         --set alertmanager.slack.existingSecret=algalon-slack
  3. Join each GPU node:
       K3S_URL=https://<this-host>:6443 K3S_TOKEN=<token> ./deploy/k3s/install-agent.sh

Full runbook: deploy/k3s/README.md
EOF
}

main "$@"
