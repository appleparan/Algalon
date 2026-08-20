#!/bin/bash
# Algalon — push a finished Slurm job's stdout into VictoriaLogs.
#
# HOOK: EpilogSlurmctld (slurm.conf: EpilogSlurmctld=/path/to/this/script).
# It runs ONCE per job, on the slurmctld host, as SlurmUser — not once per
# node — so a multi-node job is pushed exactly once with no dedup logic. The
# controller must be able to read the job's StdOut path, which on a typical
# cluster means it mounts the same shared filesystem the users do.
#
# WHY A ONE-SHOT PUSH AND NOT A TAILER: job outputs live on shared NFS. A
# directory watcher would glob and stat those trees continuously, generating
# exactly the NFS GETATTR load Algalon's node-precursor and storage-nfs rules
# watch for — the collector would poison the signal it is deployed to
# protect. Logs are therefore shipped once, at job end, bounded in size.
#
# CONFIGURATION (environment, all optional):
#   VLOGS_URL              VictoriaLogs base URL     (default http://localhost:9428)
#   ALGALON_LOG_MAX_BYTES  trailing bytes to ship    (default 10485760 = 10 MiB)
#   CURL_TIMEOUT           curl --max-time, seconds  (default 10)
#
# DEPENDENCIES: bash, curl, jq, and Slurm's own scontrol. jq is the only
# non-obvious one; it is packaged for every distro that ships Slurm, and is
# used here because escaping arbitrary log bytes into JSON by hand in awk is
# a correctness trap. A missing dependency is a silent no-op, not a failure.
#
# FAILURE POLICY: this script can never fail. An EpilogSlurmctld that exits
# non-zero makes slurmctld drain nodes, so every path ends in exit 0 and
# diagnostics go to stderr (the slurmctld log) only.

set -u
trap 'exit 0' EXIT INT TERM

VLOGS_URL="${VLOGS_URL:-http://localhost:9428}"
ALGALON_LOG_MAX_BYTES="${ALGALON_LOG_MAX_BYTES:-10485760}"
CURL_TIMEOUT="${CURL_TIMEOUT:-10}"

warn() {
  printf 'algalon-logpush: %s\n' "$*" >&2
}

# Pull one KEY=value token out of a `scontrol show job -o` line. Tokens are
# space separated, so a value containing a space (a StdOut path with a space
# in it) is truncated at that space — such jobs fail the readability check
# below and are skipped rather than mis-parsed.
scontrol_field() {
  local key="$1" line="$2" rest
  case " $line " in
    *" $key="*) ;;
    *) return 1 ;;
  esac
  rest="${line#*" $key="}"
  printf '%s' "${rest%% *}"
}

main() {
  local jobid="${SLURM_JOB_ID:-}"
  if [ -z "$jobid" ]; then
    warn 'SLURM_JOB_ID is unset; not running as EpilogSlurmctld?'
    return 0
  fi

  local dep
  for dep in scontrol jq curl; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      warn "$dep not found; skipping job $jobid"
      return 0
    fi
  done

  # The job record survives in slurmctld for MinJobAge after completion, so
  # it is still queryable from the epilog.
  local info
  if ! info="$(scontrol show job -o "$jobid" 2>/dev/null)"; then
    warn "scontrol show job $jobid failed; skipping"
    return 0
  fi

  local stdout_path
  stdout_path="$(scontrol_field StdOut "$info")" || stdout_path=''
  if [ -z "$stdout_path" ] || [ "$stdout_path" = '(null)' ]; then
    return 0
  fi
  # Also covers the truncated-at-a-space case, and output written to a
  # filesystem the controller cannot see.
  if [ ! -f "$stdout_path" ] || [ ! -r "$stdout_path" ]; then
    return 0
  fi

  # Prefer the epilog's own environment; fall back to the scontrol line.
  local user jobname exitcode nodelist
  user="${SLURM_JOB_USER:-$(scontrol_field UserId "$info")}"
  user="${user%%(*}"   # scontrol renders UserId as name(uid)
  jobname="${SLURM_JOB_NAME:-$(scontrol_field JobName "$info")}"
  exitcode="${SLURM_JOB_EXIT_CODE:-$(scontrol_field ExitCode "$info")}"
  nodelist="${SLURM_JOB_NODELIST:-$(scontrol_field NodeList "$info")}"

  # slurmjobid + user are the stream fields, which is what makes
  # `{slurmjobid="123"}` — the stream filter the Job Explorer's logs panel
  # issues — a cheap lookup rather than a full scan.
  local endpoint="$VLOGS_URL/insert/jsonline?_stream_fields=slurmjobid,user&_msg_field=_msg"

  # --fail-with-body needs curl >= 7.76; slurmctld hosts are often older.
  local fail_flag='--fail'
  if curl --help all 2>/dev/null | grep -q -- '--fail-with-body'; then
    fail_flag='--fail-with-body'
  fi

  # tail -c may slice the oldest shipped line mid-way; that partial line is
  # shipped as-is, so nothing that made the cut is silently dropped.
  set -o pipefail
  if ! tail -c "$ALGALON_LOG_MAX_BYTES" "$stdout_path" 2>/dev/null \
    | jq -Rc \
        --arg slurmjobid "$jobid" \
        --arg user "$user" \
        --arg jobname "$jobname" \
        --arg exitcode "$exitcode" \
        --arg nodelist "$nodelist" \
        '{_msg: ., slurmjobid: $slurmjobid, user: $user, jobname: $jobname,
          exitcode: $exitcode, nodelist: $nodelist}' \
    | curl "$fail_flag" --silent --show-error \
        --max-time "$CURL_TIMEOUT" \
        -H 'Content-Type: application/stream+json' \
        --data-binary @- \
        "$endpoint" >&2; then
    warn "push failed for job $jobid ($stdout_path -> $VLOGS_URL)"
  fi
  return 0
}

main "$@" || true
exit 0
