# Phase 6: Slurm Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Map Slurm queue state AND per-job accounting into Algalon — visible in dashboards and actionable in alerts — by wiring two external exporters into the existing scrape/rules/dashboards pipeline.

**Architecture:** Two exporters, both consumed as external scrape targets (they run on Slurm hosts, not inside Algalon's stacks): [rivosinc/prometheus-slurm-exporter](https://github.com/rivosinc/prometheus-slurm-exporter) on the slurmctld/login node (**:9092**, cluster/queue/partition level) and [guilbaults/slurm-job-exporter](https://github.com/guilbaults/slurm-job-exporter) on every compute node (**:9798**, cgroup-based per-job CPU/mem/GPU with `user`/`account`/jobid labels). Because slurm-job-exporter is per-node, its target entries carry Algalon's `node` label — every `slurm_job_*` series then joins with DCGM/node-exporter series `on(node)`, which is what makes job-centric node views and job-labeled alerts possible.

**Verified metric facts (from upstream docs, 2026-08-08):** queue exporter — `slurm_node_count_per_state{state=...}` (alloc/idle/drain/down), `slurm_job_count_per_state{state=...}` (pending/running/failed...), `slurm_partition_*`; job exporter — `slurm_job_memory_usage`, `slurm_job_core_usage_total`, `slurm_job_utilization_gpu`, `slurm_job_memory_usage_gpu`, `slurm_job_power_gpu` (labels `user`, `account`, jobid; `gpu`/`gpu_type` on GPU metrics). **The exact jobid label name (`slurmjobid` per upstream README examples) MUST be verified against the exporter source in Task 1 and used consistently everywhere after.**

## Global Constraints

- Follow every established convention: scrape job names are contract (new jobs named exactly `slurm` and `slurm-job`); rules carry severity ∈ {critical, warning} + `action`, single `summary` annotation, comments above rules; tests need `groupname:` and `metricsql_expr_test`; dashboards are flat-panel JSON with uid prefix `algalon-`, `${datasource}` on every target, `refresh: "30s"`, validated by `make dashboards-validate`; docs are bilingual (EN + `docs/ko/` mirror, 1:1 headings).
- Quality gate before every commit: `make rules-validate rules-test scrape-validate alertmanager-validate compose-validate dashboards-validate helm-validate` (all 7). `make e2e-k3d` once at the end (Task 4) — Slurm targets are absent there, which must not break any assertion.
- Slurm integration is OPT-IN everywhere: empty target files by default (compose), `slurm.enabled: false` default (Helm values). No existing rule/dashboard file is modified except where a task explicitly says so.
- Work in worktree `.claude/worktrees/phase6-slurm`, branch `feat/slurm-integration`. Commit per task; never --no-verify. Real helm = `~/.local/bin/helm` v3.21.3.

---

### Task 1: Scrape wiring (compose + Helm)

**Files:**
- Modify: `monitoring/scrape/prometheus.yml` — append two jobs, same file_sd shape as existing ones: `slurm` → `/etc/vmagent/targets/slurm-targets.yml`, `slurm-job` → `/etc/vmagent/targets/slurm-job-targets.yml`, with a comment block explaining the two exporters and the `node`-label contract for slurm-job targets.
- Create: `monitoring/scrape/targets/slurm-targets.yml.example` (one entry: `slurmctld.example.internal:9092`, no node label needed) and `monitoring/scrape/targets/slurm-job-targets.yml.example` (one entry per compute node, port 9798, `node:` label REQUIRED — mirror the node-targets example).
- Modify: `deploy/helm/algalon/values.yaml` — add:

```yaml
# -- Slurm integration (optional) --
# Both exporters run OUTSIDE the cluster on Slurm hosts; list them here.
slurm:
  enabled: false
  # prometheus-slurm-exporter on the slurmctld/login node (queue/partition state)
  queueTargets: []        # e.g. ["slurmctld.example.internal:9092"]
  # slurm-job-exporter on every compute node (per-job cgroup/GPU accounting)
  jobTargets: []          # e.g. [{address: "gpu01.example.internal:9798", node: "gpu01"}]
```

- Modify: `deploy/helm/algalon/templates/host-vmagent-configmap.yaml` — when `.Values.slurm.enabled`, render two additional scrape jobs with `static_configs`: job `slurm` from `queueTargets`; job `slurm-job` from `jobTargets` with `labels: {node: ...}` per entry.
- Modify: `deploy/compose/host/targets/README.md` — add the two new template copy lines and the node-label requirement for slurm-job targets.

**Verification step (mandatory):** fetch the jobid label name from the exporter source: `curl -s https://raw.githubusercontent.com/guilbaults/slurm-job-exporter/main/slurm-job-exporter.py | grep -o 'slurmjobid\|"jobid"' | head -3` — record the result; every later task uses exactly that label name (referred to as `JOBID_LABEL` below; expected: `slurmjobid`).

- [ ] Steps: edit files → `make scrape-validate compose-validate helm-validate` green (helm rendered with `--set slurm.enabled=true --set queueTargets/jobTargets` overrides asserted to contain `job_name: slurm` and `job_name: slurm-job` + the node label; and with defaults asserted NOT to) → full gate → commit `feat: Add Slurm exporter scrape wiring (compose and Helm)`.

### Task 2: `slurm.yml` rule group + tests

**Files:** Create `monitoring/rules/slurm.yml`, `tests/rules/slurm.test.yml`.

Rules (group `slurm`, interval 30s; all comments cite the queue/job exporter and the design intent):

1. `SlurmNodeDown` — `slurm_node_count_per_state{state="down"} > 0`, for 5m, **critical**, action `investigate`; summary: `'{{ $value }} Slurm node(s) DOWN'`.
2. `SlurmNodeDrained` — same shape with `state="drain"`, for 10m, **warning**, action `investigate`.
3. `SlurmJobFailureSpike` — `delta(slurm_job_count_per_state{state="failed"}[30m]) > 3`, **warning**, action `investigate`; summary mentions the 30m window.
4. `SlurmQueueStalledWithIdleNodes` — `(slurm_job_count_per_state{state="pending"} > 0) and on() (slurm_node_count_per_state{state="idle"} > 0)`, for 30m, **warning**, action `investigate` — pending work while nodes sit idle points at scheduler/partition misconfiguration.
5. `SlurmJobGpuIdle` — `avg by (node, user, JOBID_LABEL) (slurm_job_utilization_gpu) < 10`, for 30m, **warning**, action `investigate`; summary: `'Job {{ $labels.JOBID_LABEL }} (user {{ $labels.user }}) is holding GPUs on {{ $labels.node }} below 10% utilization for 30m'` (substitute the verified label name). This is the report-motivated allocation-waste alert (Microsoft median-52%-utilization finding cited in the report's intro) — and it carries user/jobid straight into Slack.

Tests: positive + negative cases per rule (synthetic series; use the verified JOBID_LABEL); include a negative for `SlurmQueueStalledWithIdleNodes` where pending exists but idle == 0.

- [ ] Steps: TDD (test RED → rules → GREEN), mutation check on one threshold, full gate, commit `feat: Add Slurm queue and job accounting alert rules`.

### Task 3: Two dashboards

**Files:** Create `monitoring/dashboards/slurm-queue.json` (uid `algalon-slurm-queue`, title `Algalon / Slurm Queue`), `monitoring/dashboards/slurm-jobs.json` (uid `algalon-slurm-jobs`, title `Algalon / Slurm Job Explorer`).

**slurm-queue.json** — cluster view, `datasource` variable only:
- Row 1, stat tiles (w=6 each): Pending jobs (`slurm_job_count_per_state{state="pending"}`), Running jobs (`state="running"`), Nodes down (`state="down"` of node metric; thresholds 0 green / 1 red), Nodes drained (orange at ≥1).
- Row 2: timeseries `sum by (state) (slurm_job_count_per_state)` (legend `{{state}}`, stacked off) w=12; state-timeline of `slurm_node_count_per_state` by state w=12.
- Row 3: partition table — instant `slurm_partition_job_state_total` (labelsToFields; partition/state/Value columns) w=24.

**slurm-jobs.json** — job-centric view; variables `datasource` + `job_id` (query `label_values(slurm_job_memory_usage, JOBID_LABEL)`, refresh on time change):
- Row 1, stat tiles for `{JOBID_LABEL="$job_id"}`: user (from label of `slurm_job_memory_usage` via table/stat name override — if a stat of a label is awkward, render user+account in the row title using a text panel fed by the same query), memory usage (bytes), process count, GPU count (`count(slurm_job_utilization_gpu{JOBID_LABEL="$job_id"})`).
- Row 2 (job resources): timeseries GPU utilization per gpu (`slurm_job_utilization_gpu{JOBID_LABEL="$job_id"}` legend `GPU {{gpu}}`, percent 0-100) w=12; GPU memory + power (two separate panels, w=6 each — never dual-axis).
- Row 3 (node join — the point of this integration): timeseries `avg by (node) (DCGM_FI_DEV_GPU_UTIL) and on(node) (count by (node) (slurm_job_memory_usage{JOBID_LABEL="$job_id"}) > 0)` legend `{{node}} (DCGM)` w=12; NFS GETATTR latency for the job's nodes (same `and on(node)` join over the mountstats ratio expr from node-health) w=12. Panel descriptions state: "node-level signal joined on(node) — job-exclusive nodes read as job signal".
- Row 4: table "Firing alerts on this job's nodes" — instant `ALERTS{alertstate="firing"} and on(node) (count by (node) (slurm_job_memory_usage{JOBID_LABEL="$job_id"}) > 0)` w=24.

- [ ] Steps: author both (follow existing dashboards' JSON shape), `make dashboards-validate` green (7 files), jq spot-check titles/queries, commit `feat: Add Slurm queue and job explorer dashboards`.

### Task 4: Docs (EN+KO), README, status, e2e re-run

**Files:** Create `docs/slurm.md` + `docs/ko/slurm.md`; modify `README.md` + `README.ko.md` (docs tables + one sentence in the intro's monitored-signals list), `IMPLEMENTATION_PLAN.md` (add Phase 6 row, `✅ done`).

`docs/slurm.md` contents (KO mirrors 1:1): why two exporters (queue vs job accounting); install pointers for both (queue exporter on slurmctld, port 9092; slurm-job-exporter on compute nodes, port 9798, requires `JobAcctGatherType=jobacct_gather/cgroup` and NVML for GPU attribution); target registration for compose (copy templates, node label REQUIRED on slurm-job targets) and Helm (`slurm.enabled` + target lists); what you get — the 5 alerts (with the jobid/user-labeled `SlurmJobGpuIdle` reaching Slack) and the 2 dashboards; the `on(node)` join contract and its limit (node-level signals attribute cleanly only on exclusive-node jobs; shared nodes rely on the cgroup metrics).

- [ ] Steps: write docs → link check → full gate → `make e2e-k3d` (must stay 4/4 — no Slurm targets in k3d is the expected, non-breaking state) → commit `docs: Add Slurm integration guide and Phase 6 status`.

---

## Self-Review Notes

- User asks covered: both exporters (T1), queue state + detailed job state (T2 rules, T3 both dashboards), visible in dashboards (T3) AND alerts (T2 — `SlurmJobGpuIdle` carries user/jobid labels into Slack), bilingual docs (T4).
- Contract preservation: job names `slurm`/`slurm-job` fixed; `node` label on slurm-job targets is what powers every join; opt-in defaults keep GPU-only deployments unchanged; e2e unaffected.
- Deliberate scope cuts: no exporter deployment automation (they need Slurm CLI/cgroup access on hosts — documented, not containerized); existing alert rules keep their label sets (job context reaches operators via the new rule + the Job Explorer alert table, not by mutating gpu-xid).
