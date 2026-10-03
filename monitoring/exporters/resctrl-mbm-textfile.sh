#!/bin/bash
# Algalon — export CPU memory bandwidth from Linux resctrl MBM as
# node_exporter textfile metrics.
#
# WHERE IT RUNS: every node whose memory bandwidth you want on the host
# dashboard, from a systemd timer (or cron), as root. Like the scripts in
# monitoring/slurm/ this is a site-side artifact: Algalon ships the script
# and the dashboard panel that reads it, but never deploys or schedules it.
#
# WHY A TEXTFILE COLLECTOR: node_exporter has no MBM collector, and a GPU
# node starved of host memory bandwidth (data loaders, pinned-memory copies,
# NCCL staging) looks idle on every DCGM metric. MBM is the hardware counter
# that answers "is the CPU memory bus saturated", and resctrl is the only
# stable kernel interface to it.
#
# WHY IT IS SHAPED THIS WAY — LOW OVERHEAD IS THE DESIGN GOAL:
#   * Each read of an mbm_*_bytes file makes the kernel read a hardware
#     counter on a CPU inside that L3 domain (a cross-CPU MSR read via IPI
#     when the reader runs elsewhere). Cost is therefore
#     groups x domains x events x frequency. This script reads ONLY the
#     default monitor group — 2 events x (L3 domains, usually 1-2 per
#     socket) — so one run is a handful of reads, a few dozen at most on
#     large Sub-NUMA layouts. At a 30-60 s timer that is noise.
#   * It never creates monitor or control groups and never writes tasks,
#     cpus or schemata. Per-job groups would need an RMID per job, kernel
#     bookkeeping for each, and an extra MSR write whenever a CPU switches
#     between tasks of different groups — overhead on the workload itself,
#     not just on the collector. Per-job attribution is out of scope on
#     purpose.
#   * It never mounts resctrl. Mounting is the operator's decision
#     (`mount -t resctrl resctrl /sys/fs/resctrl`), and a monitoring script
#     that silently changes kernel state is not a monitoring script.
#   * One pass per invocation: no daemon, no loop, no sleep. Values are read
#     with the `read` builtin and the timestamp with `printf '%(%s)T'`, so
#     the only forks per run are mktemp, chmod and mv for the atomic write.
#
# WHAT THE DEFAULT GROUP MEASURES: traffic of every task that is not in
# another resctrl group. On a node where nobody creates groups that is the
# whole machine. If something else on the node does create monitor or
# control groups, their traffic is excluded from these numbers.
#
# SUB-NUMA CLUSTERING (SNC): with SNC enabled, recent kernels nest
# mon_sub_L3_* directories inside each mon_L3_* directory, one per SNC
# node, and the parent mon_L3_* files report the sum of their sub-domains.
# This script reads only the parent files, so `domain` is always the L3
# cache id and the series count stays one per L3 domain whether SNC is on
# or off. The dashboard therefore never changes shape when an operator
# toggles SNC in the BIOS; per-SNC-node breakdown is deliberately dropped.
#
# CONFIGURATION (environment, all optional):
#   RESCTRL_ROOT   resctrl mount point (default /sys/fs/resctrl)
#   TEXTFILE_DIR   .prom output dir    (default /var/lib/node_exporter/textfile)
#
# OUTPUT ($TEXTFILE_DIR/algalon_resctrl_mbm.prom):
#   node_resctrl_memory_bandwidth_bytes_total{domain="<L3 id>",scope="total"|"local"}
#       counter. domain is the numeric suffix of mon_L3_NN without zero
#       padding (mon_L3_00 -> "0"). scope="local" is traffic to the
#       domain's local memory; scope="total" adds remote traffic.
#   node_resctrl_mbm_available                    gauge, 1 or 0
#   node_resctrl_mbm_last_run_timestamp_seconds   gauge
#
# FAILURE POLICY: a timer unit must not fail for an expected condition.
#   * resctrl not mounted, or mounted without MBM support: write
#     available=0 plus the timestamp and exit 0.
#   * a counter file that does not hold a number ("Unavailable", "Error",
#     "Unassigned", or an unreadable file): omit that one series. Emitting
#     0 instead would look like a counter reset and produce a bogus rate
#     spike on the next good read.
#   * the output cannot be written: exit 1 with a message on stderr. That
#     is a real misconfiguration and the failed unit is how it gets seen.
#   The .prom file is written tmp+rename in the same directory, so
#   node_exporter only ever sees the previous snapshot or the new one.
#
# CAVEATS — documented behaviour, NOT verified on hardware by this project:
#   * Check support first: `grep -c cqm_mbm_total /proc/cpuinfo` (non-zero
#     means the CPU advertises MBM total; cqm_mbm_local for local).
#   * Counter width and overflow are handled by the kernel; the files are
#     already 64-bit byte totals. They reset when resctrl is unmounted and
#     remounted, which rate()/increase() treat as a normal counter reset.
#   * AMD may return "Unavailable" when hardware counters are exhausted
#     (more active RMIDs than counters); those reads are skipped, so expect
#     gaps rather than wrong values.
#   * SNC layouts need a recent kernel for correct MBM values; older
#     kernels may misreport with SNC enabled.
#   * Do not mount with the mba_MBps option: it makes the kernel drive the
#     MBA throttle from MBM readings, which turns a passive measurement
#     into a feedback controller.
#   * resctrl is root-owned; running as a non-root user is untested.
#
# EXAMPLE systemd units (30 s cadence):
#
#   # /etc/systemd/system/algalon-resctrl-mbm.service
#   [Unit]
#   Description=Algalon resctrl MBM textfile export
#   ConditionPathIsDirectory=/sys/fs/resctrl
#   [Service]
#   Type=oneshot
#   ExecStart=/usr/local/bin/algalon-resctrl-mbm-textfile
#   Nice=19
#   IOSchedulingClass=idle
#
#   # /etc/systemd/system/algalon-resctrl-mbm.timer
#   [Unit]
#   Description=Run the Algalon resctrl MBM export every 30 s
#   [Timer]
#   OnBootSec=30s
#   OnUnitActiveSec=30s
#   AccuracySec=1s
#   [Install]
#   WantedBy=timers.target
#
#   systemctl daemon-reload && systemctl enable --now algalon-resctrl-mbm.timer
#
# The node_exporter on that host must run with
# --collector.textfile.directory pointing at TEXTFILE_DIR.

set -euo pipefail
shopt -s nullglob

RESCTRL_ROOT="${RESCTRL_ROOT:-/sys/fs/resctrl}"
TEXTFILE_DIR="${TEXTFILE_DIR:-/var/lib/node_exporter/textfile}"

readonly PROM_NAME='algalon_resctrl_mbm.prom'

warn() {
  printf 'algalon-resctrl-mbm: %s\n' "$*" >&2
}

die() {
  warn "$*"
  exit 1
}

# Write $2 to $1 through a temporary file in the same directory, so the
# rename is atomic and no reader ever observes a partial file.
write_atomic() {
  local dest="$1" content="$2" dir tmp
  dir="${dest%/*}"
  tmp="$(mktemp "$dir/.algalon-resctrl-mbm.XXXXXX" 2>/dev/null)" || return 1
  if ! printf '%s' "$content" >"$tmp"; then
    rm -f -- "$tmp"
    return 1
  fi
  chmod 0644 -- "$tmp" || { rm -f -- "$tmp"; return 1; }
  mv -f -- "$tmp" "$dest" || { rm -f -- "$tmp"; return 1; }
}

# Read one counter file into the named variable. Fails — so the caller
# skips the series — when the file is missing, unreadable, or holds
# anything but a plain non-negative integer.
read_counter() {
  local file="$1" __val=''
  [ -r "$file" ] || return 1
  { read -r __val <"$file"; } 2>/dev/null || [ -n "$__val" ] || return 1
  [[ "$__val" =~ ^[0-9]+$ ]] || return 1
  printf -v "$2" '%s' "$__val"
}

main() {
  local now
  printf -v now '%(%s)T' -1

  mkdir -p -- "$TEXTFILE_DIR" 2>/dev/null || die "cannot create $TEXTFILE_DIR"
  [ -w "$TEXTFILE_DIR" ] || die "$TEXTFILE_DIR is not writable"

  local series='' available=0 dir id domain scope value
  for dir in "$RESCTRL_ROOT"/mon_data/mon_L3_*; do
    [ -d "$dir" ] || continue
    id="${dir##*/mon_L3_}"
    [[ "$id" =~ ^[0-9]+$ ]] || continue
    domain=$((10#$id))
    for scope in total local; do
      # A counter file that exists at all proves MBM is supported, even if
      # this particular read comes back "Unavailable".
      [ -e "$dir/mbm_${scope}_bytes" ] && available=1
      read_counter "$dir/mbm_${scope}_bytes" value || continue
      series+="node_resctrl_memory_bandwidth_bytes_total{domain=\"$domain\",scope=\"$scope\"} $value"$'\n'
    done
  done

  local out=''
  if [ -n "$series" ]; then
    out+='# HELP node_resctrl_memory_bandwidth_bytes_total Bytes moved between the L3 domain and memory, from resctrl MBM (default monitor group). scope="local" is local-memory traffic; scope="total" includes remote.'$'\n'
    out+='# TYPE node_resctrl_memory_bandwidth_bytes_total counter'$'\n'
    out+="$series"
  fi
  out+='# HELP node_resctrl_mbm_available 1 if resctrl is mounted and exposes MBM counters, 0 otherwise.'$'\n'
  out+='# TYPE node_resctrl_mbm_available gauge'$'\n'
  out+="node_resctrl_mbm_available $available"$'\n'
  out+='# HELP node_resctrl_mbm_last_run_timestamp_seconds Unix time of the last run of the resctrl MBM textfile export.'$'\n'
  out+='# TYPE node_resctrl_mbm_last_run_timestamp_seconds gauge'$'\n'
  out+="node_resctrl_mbm_last_run_timestamp_seconds $now"$'\n'

  write_atomic "$TEXTFILE_DIR/$PROM_NAME" "$out" || die "cannot write $TEXTFILE_DIR/$PROM_NAME"
}

main "$@"
