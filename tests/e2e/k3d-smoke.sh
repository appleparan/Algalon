#!/usr/bin/env bash
# Algalon k3d end-to-end smoke test — proves the Helm chart actually works.
#
# Usage:  ./tests/e2e/k3d-smoke.sh      (or: make e2e-k3d)
#
# Creates a throwaway single-node k3d cluster, installs the Phase 4 chart and
# asserts the four properties that distinguish "the manifests render" (already
# covered by `make helm-validate`) from "the pipeline runs":
#
#   1. vmalert loaded all seven rule groups
#   2. the Watchdog alert reached Alertmanager  (vmalert -> AM link is live)
#   3. up{job="node"} == 1                      (vmagent -> VM scrape is live)
#   4. the dcgm DaemonSet schedules nothing     (nodeSelector keeps GPU-only
#                                                exporters off non-GPU nodes)
#
# The cluster is deleted on every exit path, including failures and Ctrl-C.
# The host kubeconfig is never touched: the cluster writes to a temp file.
#
# Requires: k3d, helm, kubectl, docker, rsync (for `make helm-sync`).
# Exit code: 0 when all four assertions pass, 1 otherwise.
set -euo pipefail

readonly CLUSTER='algalon-e2e'
readonly RELEASE='algalon'
readonly CHART='deploy/helm/algalon'
readonly CURL_IMAGE='curlimages/curl:8.10.1'
readonly HELM_TIMEOUT='5m'

# Every assertion polls: the pipeline converges in seconds, not instantly
# (30s scrape interval, 30s rule evaluation), so a single probe is a coin flip.
readonly ASSERT_TIMEOUT_S=90
readonly ASSERT_INTERVAL_S=3

# Slack webhooks are mandatory in the chart (see algalon.alertmanagerSecretName).
# These hosts do not resolve: delivery fails, which is expected and irrelevant —
# the assertion is that the alert reaches Alertmanager, not Slack.
readonly SLACK_CRITICAL_URL='https://hooks.invalid/c'
readonly SLACK_WARNING_URL='https://hooks.invalid/w'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly ROOT_DIR

WORK_DIR=''

log()  { printf '\n==> %s\n' "$1"; }
info() { printf '    %s\n' "$1"; }

cleanup() {
  local status=$?
  log "Tearing down k3d cluster ${CLUSTER}"
  k3d cluster delete "$CLUSTER" >/dev/null 2>&1 || true
  [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ] && rm -rf "$WORK_DIR"
  exit "$status"
}

require_tools() {
  local missing=() tool
  for tool in k3d helm kubectl docker rsync; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    printf 'missing required tools: %s\n' "${missing[*]}" >&2
    exit 1
  fi
}

# --- assertion bookkeeping -------------------------------------------------
# Results are collected instead of failing fast so one broken assertion still
# shows the state of the other three — that is what makes the summary useful.
ASSERT_NAMES=()
ASSERT_RESULTS=()
ASSERT_DETAILS=()

record() {
  ASSERT_NAMES+=("$1")
  ASSERT_RESULTS+=("$2")
  ASSERT_DETAILS+=("$3")
}

# Wraps an assertion body (read from $1) with the `deadline`/`interval`
# variables its retry loop needs, so the timeout lives in exactly one place.
# The trailing newlines matter: `$(...)` strips them, and a body glued onto
# the prelude turns into a silently different program.
with_retry() {
  # shellcheck disable=SC2016  # emitted verbatim for the pod's shell to expand
  printf 'deadline=$(( $(date +%%s) + %s ))\ninterval=%s\n%s\n' \
    "$ASSERT_TIMEOUT_S" "$ASSERT_INTERVAL_S" "$1"
}

# run_in_cluster <pod-suffix> <sh-script>
# Runs the script in a throwaway pod on the cluster network (the services are
# ClusterIP-only, so the probe has to come from inside). Prints the pod's
# stdout; returns the pod's exit code.
run_in_cluster() {
  local script=$2 pod="e2e-${1}-$$" rc=0 out
  out=$(kubectl run "$pod" --rm --attach --quiet --restart=Never \
    --image="$CURL_IMAGE" --pod-running-timeout=3m \
    --command -- sh -c "$script" 2>"${WORK_DIR}/${pod}.err") || rc=$?
  printf '%s' "$out"
  if [ "$rc" -ne 0 ]; then
    # stdout belongs to the caller's capture; diagnostics go to stderr.
    printf '    kubectl run stderr (%s):\n' "$pod" >&2
    sed 's/^/      /' "${WORK_DIR}/${pod}.err" >&2 || true
  fi
  return "$rc"
}

# --- assertions ------------------------------------------------------------

assert_rule_groups() {
  local script detail
  script=$(with_retry "$(cat <<'SH'
groups='gpu-xid gpu-ecc gpu-health node-precursor storage-nfs meta slo'
while :; do
  body=$(curl -sf --max-time 10 "http://algalon-vmalert:8880/api/v1/rules" || true)
  found=0
  missing=''
  for g in $groups; do
    if printf '%s' "$body" | grep -Eq "\"name\"[[:space:]]*:[[:space:]]*\"${g}\""; then
      found=$((found + 1))
    else
      missing="${missing} ${g}"
    fi
  done
  # Counting (not just "nothing missing") so an empty group list cannot pass.
  if [ "$found" -eq 7 ]; then
    printf 'all 7 rule groups loaded\n'
    exit 0
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    printf 'only %s/7 groups loaded, missing:%s\n' "$found" "${missing:- <none>}"
    exit 1
  fi
  sleep "$interval"
done
SH
)")
  if detail=$(run_in_cluster 'rules' "$script"); then
    record 'vmalert rule groups' 'PASS' "$detail"
  else
    record 'vmalert rule groups' 'FAIL' "${detail:-vmalert /api/v1/rules unreachable}"
    return 1
  fi
}

assert_watchdog_at_alertmanager() {
  local script detail
  script=$(with_retry "$(cat <<'SH'
while :; do
  body=$(curl -sf --max-time 10 "http://algalon-alertmanager:9093/api/v2/alerts" || true)
  if printf '%s' "$body" | grep -q 'Watchdog'; then
    printf 'Watchdog registered at Alertmanager\n'
    exit 0
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    printf 'Watchdog absent from /api/v2/alerts\n'
    exit 1
  fi
  sleep "$interval"
done
SH
)")
  if detail=$(run_in_cluster 'watchdog' "$script"); then
    record 'Watchdog reached Alertmanager' 'PASS' "$detail"
  else
    record 'Watchdog reached Alertmanager' 'FAIL' "${detail:-Alertmanager /api/v2/alerts unreachable}"
    return 1
  fi
}

assert_node_scrape() {
  local script detail
  script=$(with_retry "$(cat <<'SH'
while :; do
  body=$(curl -sfG --max-time 10 \
    --data-urlencode 'query=up{job="node"}' \
    "http://algalon-victoriametrics:8428/api/v1/query" || true)
  if printf '%s' "$body" | grep -Eq '"value":\[[0-9.]+,"1"\]'; then
    printf 'up{job="node"} == 1\n'
    exit 0
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    printf 'no up{job="node"} sample with value 1 (got: %s)\n' "${body:-<empty>}"
    exit 1
  fi
  sleep "$interval"
done
SH
)")
  if detail=$(run_in_cluster 'nodeup' "$script"); then
    record 'up{job="node"} == 1' 'PASS' "$detail"
  else
    record 'up{job="node"} == 1' 'FAIL' "${detail:-VictoriaMetrics /api/v1/query unreachable}"
    return 1
  fi
}

# The k3d node carries no nvidia.com/gpu.present label, so the GPU-only
# DaemonSet must want zero pods. A non-zero desired count would mean the
# nodeSelector stopped protecting non-GPU nodes.
assert_dcgm_unscheduled() {
  local deadline desired=''
  deadline=$(( $(date +%s) + ASSERT_TIMEOUT_S ))
  while :; do
    desired=$(kubectl get daemonset "${RELEASE}-dcgm-exporter" \
      -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || true)
    if [ "$desired" = '0' ]; then
      record 'dcgm DaemonSet unscheduled' 'PASS' 'desiredNumberScheduled == 0'
      return 0
    fi
    if [ "$(date +%s)" -ge "$deadline" ]; then
      record 'dcgm DaemonSet unscheduled' 'FAIL' \
        "desiredNumberScheduled == ${desired:-<unset>}"
      return 1
    fi
    sleep "$ASSERT_INTERVAL_S"
  done
}

print_summary() {
  local i failed=0
  printf '\n'
  printf '  %-32s %-6s %s\n' 'ASSERTION' 'RESULT' 'DETAIL'
  printf '  %-32s %-6s %s\n' '--------------------------------' '------' '------'
  for i in "${!ASSERT_NAMES[@]}"; do
    printf '  %-32s %-6s %s\n' \
      "${ASSERT_NAMES[$i]}" "${ASSERT_RESULTS[$i]}" "${ASSERT_DETAILS[$i]}"
    [ "${ASSERT_RESULTS[$i]}" = 'PASS' ] || failed=$((failed + 1))
  done
  printf '\n'
  if [ "$failed" -gt 0 ]; then
    printf '❌ k3d smoke test FAILED (%d/%d assertions failed)\n' \
      "$failed" "${#ASSERT_NAMES[@]}"
    return 1
  fi
  printf '✅ k3d smoke test passed (%d/%d assertions)\n' \
    "${#ASSERT_NAMES[@]}" "${#ASSERT_NAMES[@]}"
}

# --- main ------------------------------------------------------------------

main() {
  require_tools
  cd "$ROOT_DIR"

  WORK_DIR=$(mktemp -d)
  trap cleanup EXIT INT TERM

  # A leftover cluster from an interrupted run would otherwise fail create.
  if k3d cluster list "$CLUSTER" >/dev/null 2>&1; then
    log "Removing pre-existing k3d cluster ${CLUSTER}"
    k3d cluster delete "$CLUSTER" >/dev/null
  fi

  log "Creating k3d cluster ${CLUSTER}"
  # --no-lb: nothing is exposed off-cluster, every probe runs inside.
  # The kubeconfig stays in $WORK_DIR so a k3s/kubectl setup on the host is
  # left completely alone.
  k3d cluster create "$CLUSTER" --no-lb --wait \
    --kubeconfig-update-default=false --kubeconfig-switch-context=false
  KUBECONFIG="${WORK_DIR}/kubeconfig"
  export KUBECONFIG
  k3d kubeconfig get "$CLUSTER" >"$KUBECONFIG"
  chmod 600 "$KUBECONFIG"
  kubectl cluster-info >/dev/null
  info "$(kubectl get nodes -o name | tr '\n' ' ')"

  log 'Syncing monitoring content into the chart'
  make helm-sync

  log "Installing chart as release ${RELEASE}"
  helm install "$RELEASE" "$CHART" \
    --set "alertmanager.slack.criticalUrl=${SLACK_CRITICAL_URL}" \
    --set "alertmanager.slack.warningUrl=${SLACK_WARNING_URL}" \
    --wait --timeout "$HELM_TIMEOUT"

  log 'Running assertions'
  assert_rule_groups || true
  assert_watchdog_at_alertmanager || true
  assert_node_scrape || true
  assert_dcgm_unscheduled || true

  if ! print_summary; then
    log 'Cluster state at failure'
    kubectl get pods -o wide || true
    kubectl get daemonsets || true
    return 1
  fi
}

main "$@"
