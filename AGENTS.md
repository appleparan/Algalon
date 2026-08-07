# Algalon

Multi-platform GPU cluster monitoring and **alert center**: DCGM-exporter +
node_exporter (+ optional all-smi) → VMAgent → VictoriaMetrics → vmalert →
Alertmanager → Slack, with Grafana dashboards. Deployable via Docker Compose,
Helm, and Terraform (GCP).

Design rationale and full architecture:
`docs/superpowers/specs/2026-08-07-alert-center-design.md`. Alert rules encode
findings from the Lablup Technical Report 2026 (504-GPU B200 cluster ops
analysis).

## Agent Orchestration

- The main session runs **Claude Fable 5 as orchestrator**: it plans, decomposes
  work, makes design decisions, and synthesizes reviews. It does not grind
  through large implementation diffs itself.
- Delegate implementation, exploration, and review subtasks to **Opus 5
  subagents** via the Agent tool with `model: "opus"`.
- Independent subtasks go out **in parallel in a single message**; sequential
  dispatch only when outputs feed each other.
- Skip delegation for work finishable in a handful of tool calls — do it
  directly.
- Never put destructive commands (`rm -rf`, forced worktree removal) in
  subagent prompts.

## Repository Map

- `monitoring/` — single source of truth: vmalert rules, Grafana dashboards,
  exporter configs, scrape templates
- `deploy/compose/{host,worker}` — Docker Compose stacks
- `deploy/helm/algalon` — Helm chart (worker DaemonSets + host stack)
- `deploy/k3s/` — k3s bootstrap scripts and runbook for on-prem clusters
- `tests/rules/` — vmalert rule unit tests

## Gotchas

- `monitoring/` is the **only** place rules/dashboards live. Compose
  bind-mounts it; Helm packages it into ConfigMaps. Never copy those files
  into `deploy/`.
- XID errors are **post-mortem** signals (GPU already stopped). Precursor
  rules must come from node_exporter metrics (`node_intr_total`,
  `node_procs_running`, `node_vmstat_pgpgout`, NFS mountstats) — do not try to
  build early warning on DCGM metrics alone.
- NFS metrics require node_exporter's `--collector.mountstats` flag (off by
  default). Removing that flag silently kills the `storage-nfs.yml` rule group.
- Metric prefixes by layer: `DCGM_FI_*` (GPU), `node_*` (OS), `all_smi_*`
  (optional cross-platform). Dashboards and rules must not mix layers for the
  same signal.
- XID severity mapping is intentional, not arbitrary: 31/43/94 → warning
  (app restart suffices); 119/145/149 → critical (GPU reset); 79 → critical
  (node reboot). Keep new XID rules consistent with this scheme (spec §5.1).
- all-smi is opt-in (`--profile all-smi` in compose, `allSmi.enabled` in Helm)
  and pinned to a release tag, never `latest`.
- `SLACK_WEBHOOK_URL` is env/secret-injected. No webhook URLs in git.

## Verification

- Rules: `vmalert -dryRun` + rule unit tests
- Compose: `docker compose config` (both stacks, with and without profiles)
- Alertmanager: `amtool check-config`
- Dashboards: jq convention checks
- Helm: `helm lint` && `helm template | kubeconform`
- E2E: `make e2e-k3d` (added in Task 4)

Run the checks for every layer a change touches before committing.
