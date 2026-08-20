#!/bin/bash
# Algalon — turn Slurm accounting (sacct) into node_exporter textfile metrics.
#
# WHERE IT RUNS: the slurmctld host (or any host where `sacct` can reach
# slurmdbd), from cron or a systemd timer. Like epilog-logpush.sh this is a
# site-side artifact: Algalon ships the script and the rules that read it,
# but never deploys or schedules it. See docs/slurm.md for unit examples.
#
# WHY A TEXTFILE COLLECTOR AND NOT AN EXPORTER: sacct is a database query,
# not a cheap read. Running it on every 30 s scrape would put a synchronous
# slurmdbd round-trip in the scrape path, and a slow accounting database
# would then show up as an exporter outage. A cron job that writes a .prom
# file decouples the two: node_exporter serves the last good snapshot at
# memory speed, and a hung sacct delays data rather than breaking scrapes.
#
# WHAT IT IS FOR — POLICY, NOT PAGING. Every metric here answers a
# scheduler-policy question: are queue waits acceptable for this partition,
# are walltime limits set anywhere near reality, which account is actually
# consuming the GPU-hours. Deliberately NOT here: a job success-ratio SLO
# with burn-rate alerting. On a shared research cluster most FAILED jobs
# are user error — a typo in a batch script, an OOM from a batch size the
# user picked, a bad module load. Paging on that *total* pages an operator
# for somebody else's mistake, and an operator who cannot act on a page
# learns to ignore it.
#
# The DISTRIBUTION of those failures is a different question, and it is
# why this script also breaks the outcome counter down by account and
# counts failures per node. User error is diffuse: it lands on whichever
# node the scheduler picked, and it belongs to one account at a time.
# Infrastructure failure is not. Failures concentrating on one node, or
# suddenly spreading across many accounts at once, are shapes user error
# cannot produce — so monitoring/rules/slurm.yml pages on the shape while
# staying silent about the total.
#
# CONFIGURATION (environment, all optional):
#   SACCT_STATE_DIR           state directory  (default /var/lib/algalon-sacct)
#   TEXTFILE_DIR              .prom output dir (default /var/lib/node_exporter/textfile)
#   ALGALON_SACCT_LOOKBACK_S  first-run window (default 3600; ignored once
#                             state exists — subsequent runs resume from the
#                             last window end, so the cron period is free)
#
# STATE: $SACCT_STATE_DIR/state holds the end of the last processed window
# plus every cumulative counter and histogram bucket. The .prom file is a
# pure rendering of that state, which is what makes the counters monotonic
# across runs and across reboots — nothing is recomputed from a time
# window. Deleting the state directory resets every counter to zero; that
# is a normal counter reset and `increase()`/`rate()` handle it.
#
# CARDINALITY: the labels are `partition` (a handful per cluster),
# `account` (tens), `node` (cluster size, on the failure counter only), and
# the histograms' own `le`. The widest family is the outcome counter at
# states(8) x partitions(few) x accounts(tens) — bounded by the site's
# account list, not by usage. `user` is deliberately NOT a label anywhere:
# user counts grow without bound and every one of them would multiply
# three histograms. Per-user attribution belongs in a sacct query, not in
# a time series database.
#
# DEPENDENCIES: bash, awk, GNU date (`date -d`, `date -f`), and Slurm's
# `sacct`. Missing dependencies are a hard failure, not a silent no-op.
#
# FAILURE POLICY, the inverse of the epilog's. EpilogSlurmctld must never
# fail because a non-zero exit drains nodes; a cron job must fail loudly
# because nothing else will notice. So this script exits non-zero on any
# error it cannot attribute to a single job, and cron mails the output.
# Two invariants hold regardless:
#   * the .prom file is written tmp+rename, so a reader never sees a
#     half-written exposition — only the previous snapshot or the new one;
#   * state is written BEFORE the .prom file and only after every job in
#     the window has been folded into it. An aborted run leaves the window
#     end where it was, so the next run re-queries the same jobs; the .prom
#     file is regenerated from state on the next successful run.
# Per-job problems (an unparseable timestamp, a malformed duration) are
# counted in slurm_sacct_collector_errors_total and skipped. One bad row
# must not cost the whole window.

set -u
set -o pipefail

SACCT_STATE_DIR="${SACCT_STATE_DIR:-/var/lib/algalon-sacct}"
TEXTFILE_DIR="${TEXTFILE_DIR:-/var/lib/node_exporter/textfile}"
ALGALON_SACCT_LOOKBACK_S="${ALGALON_SACCT_LOOKBACK_S:-3600}"

readonly PROM_NAME='algalon_sacct.prom'
readonly STATE_NAME='state'

# Bucket boundaries. Chosen for scheduler policy, not for pretty graphs:
#   wait      1m/5m/15m/30m/1h/2h/6h/24h — 30m is the queue-wait budget the
#             algalon:sli:job_wait_ok_1h recording rule reads (le="1800"),
#             so that boundary must exist verbatim.
#   runtime   5m/30m/1h/4h/12h/24h/48h — spans "debug shell" to "multi-day
#             training run", the two ends a partition layout has to serve.
#   ratio     Elapsed/Timelimit. Everything below 0.5 is padded walltime,
#             which is what starves the backfill scheduler; 1.0 is the
#             TIMEOUT wall.
readonly WAIT_BUCKETS='60,300,900,1800,3600,7200,21600,86400'
readonly RUNTIME_BUCKETS='300,1800,3600,14400,43200,86400,172800'
readonly RATIO_BUCKETS='0.1,0.25,0.5,0.75,0.9,1.0'

warn() {
  printf 'algalon-sacct: %s\n' "$*" >&2
}

die() {
  warn "$*"
  exit 1
}

# Write stdin to $1 through a temporary file in the same directory, so the
# rename is atomic and no reader ever observes a partial file.
write_atomic() {
  local dest="$1" dir tmp
  dir="$(dirname -- "$dest")"
  tmp="$(mktemp "$dir/.algalon-sacct.XXXXXX")" || return 1
  if ! cat >"$tmp"; then
    rm -f -- "$tmp"
    return 1
  fi
  chmod 0644 -- "$tmp" || { rm -f -- "$tmp"; return 1; }
  mv -f -- "$tmp" "$dest" || { rm -f -- "$tmp"; return 1; }
}

# Fold one sacct window into the previous state and print the new state.
# Reads three files in order: state, timestamp map, sacct rows.
read -r -d '' PROCESS_AWK <<'AWK_PROCESS'
function dur(s,   d, p, n, days, rest, sec) {
  # [DD-]HH:MM:SS, [DD-]HH:MM, MM:SS or SS, as sacct renders Elapsed and
  # Timelimit. Returns -1 for anything else so the caller can decide
  # whether that is an error or an expected sentinel.
  if (s !~ /^([0-9]+-)?[0-9]+(:[0-9]+)*(\.[0-9]+)?$/) return -1
  if (s ~ /^[0-9]+-/) { split(s, d, "-"); days = d[1] + 0; rest = d[2] }
  else { days = 0; rest = s }
  n = split(rest, p, ":")
  if (n == 3)      sec = p[1] * 3600 + p[2] * 60 + p[3]
  else if (n == 2) sec = p[1] * 60 + p[2]
  else if (n == 1) sec = p[1] + 0
  else return -1
  return days * 86400 + sec
}

function gpus(tres,   t, m) {
  # AllocTRES looks like "billing=8,cpu=8,gres/gpu=2,gres/gpu:a100=2,mem=64G".
  # Slurm always emits the untyped gres/gpu alongside any typed entry, so
  # matching the untyped one counts each GPU exactly once. The leading
  # comma is what keeps "gres/gpu:a100=2" from matching; prepending one
  # lets the first token match without an alternation anchor.
  t = "," tres
  if (match(t, /,gres\/gpu=[0-9]+/) == 0) return 0
  m = substr(t, RSTART, RLENGTH)
  sub(/^.*=/, "", m)
  return m + 0
}

# Split a nodelist on commas that are NOT inside brackets: "a[1,2],b3"
# is two tokens, not three. Returns the token count, or -1 if the
# brackets do not balance.
function split_top(s, toks,   i, c, depth, cur, n) {
  n = 0; cur = ""; depth = 0
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c == "[") depth += 1
    else if (c == "]") { depth -= 1; if (depth < 0) return -1 }
    if (c == "," && depth == 0) { toks[++n] = cur; cur = "" }
    else cur = cur c
  }
  if (depth != 0) return -1
  if (cur != "") toks[++n] = cur
  return n
}

# Expand one token ("gpu01", "gpu[01-04,07]") onto the end of `out`,
# which already holds `n` names. Returns the new count, or -1 on anything
# it does not recognise — a wrong guess here would invent node names, so
# the parser refuses rather than approximates.
function expand_tok(t, out, n,   pre, rest, body, post, items, ni, j, it, r, lo, hi, w, fmt, k) {
  if (index(t, "[") == 0) {
    if (t !~ /^[A-Za-z0-9._-]+$/) return -1
    out[++n] = t
    return n
  }
  pre = substr(t, 1, index(t, "[") - 1)
  rest = substr(t, index(t, "[") + 1)
  if (index(rest, "]") == 0) return -1
  body = substr(rest, 1, index(rest, "]") - 1)
  post = substr(rest, index(rest, "]") + 1)
  # One bracket group per token is the only form Slurm emits; a second one
  # would mean the top-level split was wrong.
  if (index(post, "[") > 0 || index(post, "]") > 0) return -1
  if (pre !~ /^[A-Za-z0-9._-]*$/ || post !~ /^[A-Za-z0-9._-]*$/) return -1
  ni = split(body, items, ",")
  for (j = 1; j <= ni; j++) {
    it = items[j]
    if (it ~ /^[0-9]+$/) { out[++n] = pre it post; continue }
    if (it !~ /^[0-9]+-[0-9]+$/) return -1
    split(it, r, "-")
    lo = r[1]; hi = r[2]
    if (hi + 0 < lo + 0) return -1
    # A pathological range would blow up the series count; refuse it.
    if ((hi + 0) - (lo + 0) > 10000) return -1
    # Zero padding is part of the name: gpu[01-04] is gpu01, not gpu1.
    # The width comes from the low bound, which is how Slurm writes it.
    w = (substr(lo, 1, 1) == "0" && length(lo) > 1) ? length(lo) : 0
    fmt = (w > 0) ? sprintf("%%0%dd", w) : "%d"
    for (k = lo + 0; k <= hi + 0; k++) out[++n] = pre sprintf(fmt, k) post
  }
  return n
}

function expand_nodelist(s, out,   toks, nt, i, n) {
  nt = split_top(s, toks)
  if (nt < 1) return -1
  n = 0
  for (i = 1; i <= nt; i++) {
    n = expand_tok(toks[i], out, n)
    if (n < 0) return -1
  }
  return n
}

function normstate(s) {
  if (s == "COMPLETED")      return "completed"
  if (s == "FAILED")         return "failed"
  if (s == "TIMEOUT")        return "timeout"
  if (s == "CANCELLED")      return "cancelled"
  if (s == "NODE_FAIL")      return "node_fail"
  if (s == "OUT_OF_MEMORY")  return "out_of_memory"
  if (s == "PREEMPTED")      return "preempted"
  # Still moving: not an outcome yet, and it will be picked up by a later
  # run once it reaches a terminal state.
  if (s == "PENDING" || s == "RUNNING" || s == "SUSPENDED" ||
      s == "REQUEUED" || s == "RESIZING" || s == "SIGNALING" ||
      s == "STAGE_OUT" || s == "REVOKED") return ""
  # BOOT_FAIL, DEADLINE, SPECIAL_EXIT and anything a future Slurm invents.
  return "other"
}

function observe(pfx, part, v, B, nb,   i) {
  for (i = 1; i <= nb; i++)
    if (v <= B[i] + 0) V[pfx "_bucket|" part "|" B[i]] += 1
  V[pfx "_sum|" part] += v
  V[pfx "_count|" part] += 1
}

BEGIN {
  nwb = split(WAIT_B, WB, ",")
  nrb = split(RT_B, RB, ",")
  nqb = split(RATIO_B, QB, ",")
  errors = 0
}

# --- previous state ---------------------------------------------------
FILENAME == STATE_FILE {
  if ($0 ~ /^#/ || NF < 2) next
  if ($1 == "last_end") next
  if ($1 == "errors") { errors = $2 + 0; next }
  V[$1] = $2 + 0
  next
}

# --- timestamp string -> epoch ----------------------------------------
FILENAME == TS_FILE {
  TS[$1] = $2 + 0
  next
}

# --- sacct rows -------------------------------------------------------
{
  if ($0 == "") next
  # Split the raw line, not the awk fields: State carries a space in
  # "CANCELLED by 1234", so the default field splitting is useless here.
  n = split($0, f, "|")
  if (n < 11) { errors += 1; next }

  jobid = f[1]
  if (jobid in SEEN) next
  SEEN[jobid] = 1

  split(f[2], sw, " ")
  st = normstate(sw[1])
  if (st == "") next

  # Dedup across overlapping windows: sacct returns every job that was in
  # any state during [starttime, endtime], including ones counted by an
  # earlier run, so the window end is what decides ownership. Strictly
  # greater than the previous end, at most this run's end.
  if (!(f[5] in TS)) { errors += 1; next }
  endt = TS[f[5]]
  if (endt <= LAST_END || endt > NOW) next

  part = (f[8] == "" ? "unknown" : f[8])
  acct = (f[9] == "" ? "unknown" : f[9])

  V["jobs|" st "|" part "|" acct] += 1

  # Per-node failure attribution. Slurm's own NODE_FAIL verdict and a
  # plain FAILED both land here: which of the two it was is already in
  # the outcome counter, and what this counter adds is *where*. One
  # increment per node the job held, so a 64-node job that died charges
  # all 64 — the alert that reads this looks for concentration, and a
  # node that only ever appears inside large allocations cannot
  # concentrate by accident.
  if (st == "failed" || st == "node_fail") {
    nl = f[11]
    if (nl != "" && nl != "None assigned" && nl != "(null)" && nl != "None") {
      nn = expand_nodelist(nl, NODES)
      if (nn < 0) {
        # Never guess at a nodelist. The job still counts as an outcome
        # above; only the node attribution is dropped.
        errors += 1
      } else {
        for (ni = 1; ni <= nn; ni++) V["node_failures|" NODES[ni]] += 1
      }
      delete NODES
    }
  }

  # Start is "None" or "Unknown" for a job that never ran (cancelled or
  # held while pending). It is a real outcome and stays in the state
  # counter above, but it has no wait, no runtime and no ratio — inventing
  # a zero for those would drag every quantile toward the floor.
  if (!(f[4] in TS)) next
  startt = TS[f[4]]

  if (f[3] in TS) {
    wait = startt - TS[f[3]]
    # Clock skew between slurmctld and slurmdbd, or a backfilled record,
    # can put Start marginally before Submit.
    if (wait < 0) wait = 0
    observe("wait", part, wait, WB, nwb)
  } else {
    errors += 1
  }

  rt = endt - startt
  if (rt < 0) rt = 0
  observe("rt", part, rt, RB, nrb)

  # UNLIMITED and Partition_Limit are not parse failures: they are jobs
  # for which "fraction of the walltime used" has no meaning.
  tl_raw = f[7]
  if (tl_raw != "UNLIMITED" && tl_raw != "Partition_Limit" &&
      tl_raw != "INVALID" && tl_raw != "") {
    el = dur(f[6])
    tl = dur(tl_raw)
    if (el < 0 || tl < 0) errors += 1
    else if (tl > 0) observe("ratio", part, el / tl, QB, nqb)
  }

  g = gpus(f[10])
  if (g > 0 && rt > 0) V["gpu_seconds|" part "|" acct] += g * rt
  next
}

END {
  print "# Algalon sacct collector state. Machine written; delete the file"
  print "# to reset every counter (increase() treats that as a reset)."
  printf "last_end %.15g\n", NOW
  printf "errors %.15g\n", errors
  for (k in V) printf "%s %.15g\n", k, V[k]
}
AWK_PROCESS

# Render the exposition format from state. The .prom file is a pure
# function of the state file: rerunning this on unchanged state produces a
# byte-identical result, which is why a failed .prom write is repairable.
read -r -d '' RENDER_AWK <<'AWK_RENDER'
function esc(s) {
  gsub(/\\/, "\\\\", s)
  gsub(/"/, "\\\"", s)
  return s
}

function sortkeys(src, dst,   i, n, j, t) {
  n = 0
  for (i in src) dst[++n] = i
  for (i = 2; i <= n; i++) {
    t = dst[i]
    j = i - 1
    while (j > 0 && dst[j] > t) { dst[j + 1] = dst[j]; j-- }
    dst[j + 1] = t
  }
  return n
}

function hist(name, pfx, help, PARTS, B, nb,   np, P, i, j, part, c) {
  np = sortkeys(PARTS, P)
  if (np == 0) return
  print "# HELP " name " " help
  print "# TYPE " name " histogram"
  for (i = 1; i <= np; i++) {
    part = P[i]
    for (j = 1; j <= nb; j++)
      printf "%s_bucket{partition=\"%s\",le=\"%s\"} %.15g\n", \
        name, esc(part), B[j], V[pfx "_bucket|" part "|" B[j]] + 0
    c = V[pfx "_count|" part] + 0
    printf "%s_bucket{partition=\"%s\",le=\"+Inf\"} %.15g\n", name, esc(part), c
    printf "%s_sum{partition=\"%s\"} %.15g\n", name, esc(part), V[pfx "_sum|" part] + 0
    printf "%s_count{partition=\"%s\"} %.15g\n", name, esc(part), c
  }
}

BEGIN {
  nwb = split(WAIT_B, WB, ",")
  nrb = split(RT_B, RB, ",")
  nqb = split(RATIO_B, QB, ",")
}

/^#/ { next }
NF < 2 { next }
$1 == "last_end" { last_end = $2 + 0; next }
$1 == "errors" { errors = $2 + 0; next }
{
  V[$1] = $2 + 0
  n = split($1, k, "|")
  kind = k[1]
  if (kind == "jobs" && n == 4) JOBS[k[2] "|" k[3] "|" k[4]] = 1
  else if (kind == "gpu_seconds" && n == 3) GPUSEC[k[2] "|" k[3]] = 1
  else if (kind == "node_failures" && n == 2) NODEFAIL[k[2]] = 1
  else if (n >= 2) {
    # Arrays of arrays are a gawk extension, so each histogram keeps its
    # own partition set rather than one nested map.
    pfx = kind
    sub(/_(bucket|sum|count)$/, "", pfx)
    if (pfx == "wait") SW[k[2]] = 1
    else if (pfx == "rt") SR[k[2]] = 1
    else if (pfx == "ratio") SQ[k[2]] = 1
  }
}

END {
  n = sortkeys(JOBS, L)
  if (n > 0) {
    print "# HELP slurm_jobs_completed_total Slurm jobs that reached a terminal state, by normalized state, partition and account."
    print "# TYPE slurm_jobs_completed_total counter"
    for (i = 1; i <= n; i++) {
      split(L[i], p, "|")
      printf "slurm_jobs_completed_total{state=\"%s\",partition=\"%s\",account=\"%s\"} %.15g\n", \
        esc(p[1]), esc(p[2]), esc(p[3]), V["jobs|" L[i]] + 0
    }
  }

  n = sortkeys(NODEFAIL, L)
  if (n > 0) {
    print "# HELP slurm_job_node_failures_total Jobs that ended FAILED or NODE_FAIL, counted once per node the job held. Concentration on one node is an infrastructure symptom; a flat spread is ordinary user error."
    print "# TYPE slurm_job_node_failures_total counter"
    for (i = 1; i <= n; i++)
      printf "slurm_job_node_failures_total{node=\"%s\"} %.15g\n", esc(L[i]), V["node_failures|" L[i]] + 0
  }

  hist("slurm_job_wait_seconds", "wait", \
    "Seconds between job submission and job start, for jobs that started.", SW, WB, nwb)
  hist("slurm_job_runtime_seconds", "rt", \
    "Seconds between job start and job end, for jobs that started.", SR, RB, nrb)
  hist("slurm_job_timelimit_used_ratio", "ratio", \
    "Elapsed divided by Timelimit; low values mean padded walltimes and worse backfill.", SQ, QB, nqb)

  n = sortkeys(GPUSEC, L)
  if (n > 0) {
    print "# HELP slurm_job_gpu_seconds_total Allocated GPU-seconds delivered (GPU count multiplied by runtime), by partition and account."
    print "# TYPE slurm_job_gpu_seconds_total counter"
    for (i = 1; i <= n; i++) {
      split(L[i], p, "|")
      printf "slurm_job_gpu_seconds_total{partition=\"%s\",account=\"%s\"} %.15g\n", \
        esc(p[1]), esc(p[2]), V["gpu_seconds|" L[i]] + 0
    }
  }

  print "# HELP slurm_sacct_collector_last_run_timestamp_seconds Unix time of the end of the last window this collector processed."
  print "# TYPE slurm_sacct_collector_last_run_timestamp_seconds gauge"
  printf "slurm_sacct_collector_last_run_timestamp_seconds %.15g\n", last_end
  print "# HELP slurm_sacct_collector_errors_total Rows this collector could not parse. A rising value means sacct output drifted from what the parser expects."
  print "# TYPE slurm_sacct_collector_errors_total counter"
  printf "slurm_sacct_collector_errors_total %.15g\n", errors
}
AWK_RENDER

main() {
  local dep
  for dep in sacct awk date mktemp; do
    command -v "$dep" >/dev/null 2>&1 || die "$dep not found in PATH"
  done

  mkdir -p -- "$SACCT_STATE_DIR" || die "cannot create $SACCT_STATE_DIR"
  mkdir -p -- "$TEXTFILE_DIR" || die "cannot create $TEXTFILE_DIR"

  local state_file="$SACCT_STATE_DIR/$STATE_NAME"
  local prom_file="$TEXTFILE_DIR/$PROM_NAME"

  local now last_end
  now="$(date +%s)" || die 'date +%s failed'
  if [ -f "$state_file" ]; then
    last_end="$(awk '$1 == "last_end" { print $2 + 0; exit }' "$state_file")"
  else
    last_end=''
    : >"$state_file" || die "cannot create $state_file"
  fi
  case "$last_end" in
    '' | *[!0-9]*) last_end=$((now - ALGALON_SACCT_LOOKBACK_S)) ;;
  esac
  if [ "$last_end" -ge "$now" ]; then
    warn "state is newer than the clock (last_end=$last_end, now=$now); nothing to do"
    return 0
  fi

  local start_str end_str
  start_str="$(date -d "@$last_end" '+%Y-%m-%dT%H:%M:%S')" || die 'date -d failed'
  end_str="$(date -d "@$now" '+%Y-%m-%dT%H:%M:%S')" || die 'date -d failed'

  local workdir
  workdir="$(mktemp -d)" || die 'mktemp -d failed'
  # shellcheck disable=SC2064  # expand workdir now, it never changes
  trap "rm -rf -- '$workdir'" EXIT

  # --allusers matters: sacct shows only the caller's own jobs unless the
  # caller is a Slurm operator/admin, and a collector that silently reports
  # root's zero jobs is worse than one that fails.
  # Duplicate job ids (after a jobid reset) are already suppressed by
  # default; -D would *add* them back, so it is deliberately not passed.
  local sacct_out="$workdir/sacct"
  if ! sacct --allusers --allocations --noheader --parsable2 \
    --starttime "$start_str" --endtime "$end_str" \
    --format=JobID,State,Submit,Start,End,Elapsed,Timelimit,Partition,Account,AllocTRES,NodeList \
    >"$sacct_out"; then
    die "sacct failed for window $start_str..$end_str; state not advanced"
  fi

  # sacct renders local ISO timestamps and has no epoch output format, so
  # convert them in one `date -f` pass instead of forking per field. Only
  # well-formed values are fed in; "None"/"Unknown" are dropped here and
  # detected downstream as a missing map entry.
  local ts_list="$workdir/ts" ts_epoch="$workdir/ts.epoch" ts_map="$workdir/ts.map"
  # The date pattern is spelled out digit by digit rather than with {2}/{4}
  # repetitions: mawk, the default awk on Debian and Ubuntu, does not
  # support POSIX interval expressions and would silently match nothing.
  awk -F'|' '
    NF >= 5 {
      for (i = 3; i <= 5; i++)
        if ($i ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]$/) print $i
    }' "$sacct_out" | sort -u >"$ts_list" || die 'timestamp extraction failed'

  : >"$ts_map"
  if [ -s "$ts_list" ]; then
    date -f "$ts_list" '+%s' >"$ts_epoch" ||
      die 'date -f failed to convert sacct timestamps; state not advanced'
    if [ "$(wc -l <"$ts_list")" -ne "$(wc -l <"$ts_epoch")" ]; then
      die 'timestamp conversion produced a different number of lines; state not advanced'
    fi
    paste -d' ' "$ts_list" "$ts_epoch" >"$ts_map" || die 'paste failed'
  fi

  local new_state="$workdir/state.new"
  if ! awk -v STATE_FILE="$state_file" -v TS_FILE="$ts_map" \
    -v LAST_END="$last_end" -v NOW="$now" \
    -v WAIT_B="$WAIT_BUCKETS" -v RT_B="$RUNTIME_BUCKETS" -v RATIO_B="$RATIO_BUCKETS" \
    "$PROCESS_AWK" "$state_file" "$ts_map" "$sacct_out" >"$new_state"; then
    die 'sacct processing failed; state not advanced'
  fi

  # State first: the .prom file is derived from it, so a crash between the
  # two loses a snapshot (recovered next run) rather than double counting.
  write_atomic "$state_file" <"$new_state" || die "cannot write $state_file"

  if ! awk -v WAIT_B="$WAIT_BUCKETS" -v RT_B="$RUNTIME_BUCKETS" -v RATIO_B="$RATIO_BUCKETS" \
    "$RENDER_AWK" "$state_file" >"$workdir/prom"; then
    die 'rendering the exposition failed'
  fi
  write_atomic "$prom_file" <"$workdir/prom" || die "cannot write $prom_file"
}

main "$@"
