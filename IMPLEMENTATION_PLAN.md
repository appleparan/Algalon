# Alert Center Redesign — Status

## SLO / Golden-Signals Redesign (2026-08)

Symptom-first dashboard layer per Google SRE golden signals
(issue #15). Layering: L0 SLO Overview → L1 Fleet/Queue → L2 Job
Explorer (+logs) → L3 Node Health/Checkpoint IO.

<!-- markdownlint-disable MD013 -->
| Phase | Scope | Status |
| --- | --- | --- |
| 1. SLO recording rules (`algalon:sli:*`, group `slo`) + tests + `slo-overview.json` (uid `algalon-slo`) + docs | existing metrics only | ✅ done (`feat/slo-overview`, issue #15) |
| 2. VictoriaLogs + Slurm epilog log push + Job Explorer logs panel | new components; epilog chosen over tailing to avoid NFS scan load (outputs live on shared NFS) | ✅ done (`feat/job-logs`, issue #17) |
| 3. sacct textfile collector → queue-wait SLI + Scheduler Analytics dashboard (`algalon-scheduler`) for QoS policy decisions | slurmctld-side script via `nodeExporter.textfileDirectory`; NO burn-rate paging on job success — most failures are user error (controller decision) | ✅ done (`feat/sacct-sli`, issue #20) |
<!-- markdownlint-enable MD013 -->

Phase 1 SLIs (instantaneous 0-1 ratios; 30d compliance computed in the
dashboard via `avg_over_time`): `exporter_availability` (avg(up)),
`slurm_node_availability` (1 - (down+drain)/total),
`gpu_health` (not HW-throttled ∧ temp < 92C),
`nfs_latency_ok` (active (instance,operation) paths < 100ms/op; idle ⇒ 1),
`job_failures_1h` (delta approximation; the exact counter arrives with the
Phase 3 collector but is deliberately charted, not paged on).
Phase 3 adds `job_wait_ok_1h` (share of jobs started within the 30-minute
budget; denominator guarded with `> 0` so an idle hour is absent, not NaN).
SLO targets live in the dashboard (thresholds), not in rules.

- **Spec**: `docs/superpowers/specs/2026-08-07-alert-center-design.md` (approved)
- **Branches**: `feat/alert-center-*` (one per phase, PRs #1-#5)

## Phases

<!-- markdownlint-disable MD013 -->
| Phase | Plan | Status |
| --- | --- | --- |
| 0. Spec + AGENTS.md rewrite | (spec §8) | ✅ done |
| 1. `monitoring/` single source (6 rule groups, scrape config, dcgm CSV, rule tests, CI) | `docs/superpowers/plans/2026-08-07-alert-center-phase1-monitoring.md` | ✅ done |
| 2. Compose stacks (`deploy/compose/{worker,host}`) | `docs/superpowers/plans/2026-08-07-alert-center-phase2-compose.md` | ✅ done |
| 3. Dashboards | `docs/superpowers/plans/2026-08-07-alert-center-phase3-dashboards.md` | ✅ done |
| 4. Helm chart | `docs/superpowers/plans/2026-08-07-alert-center-phase4-helm.md` | ✅ done |
| 5. Legacy removal + local deploy strategy (k3s) + e2e | `docs/superpowers/plans/2026-08-07-alert-center-phase5-local-deploy.md` | ✅ done |
| 6. Slurm integration (scrape wiring, `slurm` rule group, 2 dashboards, bilingual docs) | `docs/superpowers/plans/2026-08-08-phase6-slurm-integration.md` | ✅ done |
<!-- markdownlint-enable MD013 -->

## Notes carried to later phases

- **Phase 2 (Alertmanager)**: `up==0` is unscoped critical — routing/inhibition
  must consider blast radius; `GpuUncorrectableRowRemap` latches ~10m via delta
  window — grouping must not read repeats as new incidents; consider a meta
  absence guard for mountstats metrics (the `storage-nfs` group is silently
  inert without node_exporter `--collector.mountstats`).
- **Phase 2 (deploy docs)**: `DCGM_FI_DEV_CLOCKS_EVENT_REASONS` is the
  dcgm-exporter 4.x metric name; 3.x fleets use
  `DCGM_FI_DEV_CLOCK_THROTTLE_REASONS` (we pin 4.6.0-4.8.3).
- **Phase 3 (dashboards)**: agreed 5-dashboard set — GPU Fleet Overview
  (node×GPU heatmap), Node Health precursor peer-band views, Checkpoint &
  Storage I/O (phase bands from `algalon:checkpoint_*` recording rules), Alert
  Center (`ALERTS` table), all-smi (profile-only). An absent
  `checkpoint_load_phase` series means "unknown", not "not loading".
- **Future**: peer-relative `scalar()` guards assume a homogeneous fleet;
  revisit with `by(...)` grouping for mixed hardware.
- **Phase 6 (Slurm)**: the `node` label on `slurm-job` targets is the join
  key for every job↔hardware query — a mismatch fails silently. Node-level
  signals (DCGM, NFS, `ALERTS`) attribute to a job only on exclusive nodes.
  The Alertmanager inhibit rule now requires `node!=""` on the source side,
  so cluster-wide criticals (e.g. `SlurmNodeDown`) inhibit nothing.
- **Phase 5 (CI Cost-Estimation bug — dissolved, terraform removed)**: the
  `terraform-test.yml` Cost Estimation job failed on any PR touching
  `tests/**` because it `cd`ed into a nonexistent example directory. The
  workflow and the entire Terraform toolchain were deleted in Phase 5, so
  there is nothing left to fix.

Before removing this file, record a summary (stages, key decisions,
verification results) in the PR.
