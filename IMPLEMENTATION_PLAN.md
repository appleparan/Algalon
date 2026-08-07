# Alert Center Redesign — Status

- **Spec**: `docs/superpowers/specs/2026-08-07-alert-center-design.md` (approved)
- **Branch**: `feat/alert-center-redesign`

## Phases

| Phase | Plan | Status |
|---|---|---|
| 0. Spec + AGENTS.md rewrite | (spec §8) | ✅ done |
| 1. `monitoring/` single source (6 rule groups, scrape config, dcgm CSV, rule tests, CI) | `docs/superpowers/plans/2026-08-07-alert-center-phase1-monitoring.md` | ✅ done |
| 2. Compose stacks (`deploy/compose/{worker,host}`) | `docs/superpowers/plans/2026-08-07-alert-center-phase2-compose.md` | ✅ done |
| 3. Dashboards | `docs/superpowers/plans/2026-08-07-alert-center-phase3-dashboards.md` | ✅ done |
| 4. Helm chart | `docs/superpowers/plans/2026-08-07-alert-center-phase4-helm.md` | ✅ done |
| 5. Terraform migration + legacy removal | not yet planned | ⬜ |

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
- **Phase 5 (CI, deferred by decision)**: `terraform-test.yml` Cost Estimation
  job fails on any PR touching `tests/**` — it `cd`s into the nonexistent
  `terraform/examples/basic` (real examples: `host-only`, `training-cluster`).
  Pre-existing bug surfaced by PR #1; fix the path and narrow the `tests/**`
  trigger to `tests/{unit,integration,e2e}/**` during the terraform migration.

Before removing this file, record a summary (stages, key decisions,
verification results) in the PR.
