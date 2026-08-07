# Alert Center Phase 3: Dashboards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Five provisioned Grafana dashboards under `monitoring/dashboards/` (single source), wired into the host compose stack, with a jq-based validation harness in Make/CI.

**Architecture:** Dashboards are Grafana JSON files authored by hand (no grafonnet). A `datasource` template variable keeps them portable across compose/Helm. The host compose gains a file-provider provisioning entry mounting `monitoring/dashboards/`. CI validates JSON structure (parse, uid/tag/refresh conventions, datasource variable usage) — visual checks are manual (documented).

**Tech Stack:** Grafana 13.1.3 JSON dashboards (panels: timeseries, state-timeline, stat, table); MetricsQL queries against VictoriaMetrics; jq for validation.

**Spec:** design spec §Phase 3 + agreed 5-dashboard set (IMPLEMENTATION_PLAN.md notes). Data contracts: Phase 1 rules/recording rules, Phase 2 `node` target label.

## Global Constraints

- Dashboards live ONLY in `monitoring/dashboards/`; deploy layers mount/package them. Legacy `algalon_host/grafana/dashboards/` stays untouched until Phase 5.
- File/uid/title registry (exact):
  | File | uid | title |
  |---|---|---|
  | `alert-center.json` | `algalon-alerts` | Algalon / Alert Center |
  | `gpu-fleet.json` | `algalon-fleet` | Algalon / GPU Fleet Overview |
  | `node-health.json` | `algalon-node` | Algalon / Node Health (Precursors) |
  | `checkpoint-io.json` | `algalon-checkpoint` | Algalon / Checkpoint & Storage I/O |
  | `all-smi.json` | `algalon-allsmi` | Algalon / all-smi (Optional) |
- Every dashboard: `tags: ["algalon"]`, `refresh: "30s"`, `timezone: "browser"`, `editable: true`, time default `now-6h` to `now`; a `datasource` template variable (`type: "datasource"`, `query: "prometheus"`) and EVERY panel target uses `"datasource": {"type": "prometheus", "uid": "${datasource}"}`.
- Template variable `node` where specified: `label_values(up{job="node"}, node)`, multi=false, includeAll=false.
- Visualization rules (dataviz): magnitude ramps are single-hue (`continuous-blues` — never Spectral/Turbo/rainbow); status colors (red/orange/green) ONLY for alert severity, threshold lines, and up/down states; never two y-axes on one panel (split panels instead); peer bands are neutral gray fills with the selected node as the single accent series; text/labels never colored by series.
- Alert severity color mapping everywhere: critical=red, warning=orange, ok/none=green.
- All work in worktree `.claude/worktrees/alert-center-phase3`, branch `feat/alert-center-phase3-dashboards`. Commit per task; never --no-verify. Run `make dashboards-validate` (once it exists) plus the Phase 1–2 gate (`rules-validate rules-test scrape-validate alertmanager-validate compose-validate`) before each commit that could affect them.
- jq is available on the dev machine and ubuntu-latest runners.

## File Structure (this phase)

```
monitoring/dashboards/
├─ alert-center.json        # Task 1
├─ gpu-fleet.json           # Task 2
├─ node-health.json         # Task 3
├─ checkpoint-io.json       # Task 4
└─ all-smi.json             # Task 5
deploy/compose/host/grafana/provisioning/dashboards/algalon.yml   # Task 1
deploy/compose/host/docker-compose.yml                             # Task 1 (grafana mount)
Makefile                    # Task 1: dashboards-validate
.github/workflows/monitoring-test.yml                              # Task 1: step
deploy/compose/README.md    # Task 5: dashboards section
IMPLEMENTATION_PLAN.md      # Task 5: Phase 3 done
```

---

### Task 1: Validation harness + provisioning + Alert Center dashboard

**Files:**
- Create: `monitoring/dashboards/alert-center.json`
- Create: `deploy/compose/host/grafana/provisioning/dashboards/algalon.yml`
- Modify: `deploy/compose/host/docker-compose.yml` (grafana volumes)
- Modify: `Makefile` (add `dashboards-validate`, extend `.PHONY`)
- Modify: `.github/workflows/monitoring-test.yml` (add step)

**Interfaces:**
- Produces: `make dashboards-validate` (Tasks 2–5 reuse); the JSON conventions above proven by one full dashboard.

- [ ] **Step 1: Add the validation target (test first)**

Append to `Makefile` (extend `.PHONY` with `dashboards-validate`):

```make
dashboards-validate: ## Validate Grafana dashboard JSON conventions
	@set -e; for f in monitoring/dashboards/*.json; do \
		jq -e '.uid | test("^algalon-")' "$$f" >/dev/null || { echo "$$f: bad uid"; exit 1; }; \
		jq -e '.tags | index("algalon")' "$$f" >/dev/null || { echo "$$f: missing algalon tag"; exit 1; }; \
		jq -e '.refresh == "30s"' "$$f" >/dev/null || { echo "$$f: refresh != 30s"; exit 1; }; \
		jq -e '.templating.list | map(select(.type == "datasource")) | length >= 1' "$$f" >/dev/null || { echo "$$f: no datasource variable"; exit 1; }; \
		jq -e '[.panels[] | select(.targets) | .targets[] | .datasource.uid] | all(. == "$${datasource}")' "$$f" >/dev/null || { echo "$$f: panel target not using \$${datasource}"; exit 1; }; \
		jq -e '[.uid] as $$u | true' "$$f" >/dev/null; \
	done; \
	uids=$$(jq -r '.uid' monitoring/dashboards/*.json | sort | uniq -d); \
	test -z "$$uids" || { echo "duplicate uids: $$uids"; exit 1; }
	@echo "✅ dashboards valid"
```

Run: `make dashboards-validate` — Expected: FAIL (glob matches nothing → jq errors on literal path). This is the RED state.

- [ ] **Step 2: Write `monitoring/dashboards/alert-center.json`**

Grafana 13 dashboard JSON implementing exactly these panels (author the JSON by hand following current Grafana schema; grid is 24 columns wide):

Row 1 (four stat panels, h=4, w=6 each):
1. **Firing critical** — stat; query `count(ALERTS{alertstate="firing", severity="critical"}) or vector(0)`; thresholds: 0=green, 1=red; unit `none`.
2. **Firing warning** — stat; query `count(ALERTS{alertstate="firing", severity="warning"}) or vector(0)`; thresholds: 0=green, 1=orange.
3. **Pipeline (Watchdog)** — stat; query `count(ALERTS{alertname="Watchdog", alertstate="firing"}) or vector(0)`; value mappings: `1` → text `OK` (green), `0` → text `BROKEN` (red). Panel description: "Dead man's switch: 0 means vmalert→Alertmanager path is down."
4. **Exporters down** — stat; query `count(up == 0) or vector(0)`; thresholds: 0=green, 1=red.

Row 2:
5. **Active alerts** — table, h=10, w=24; instant query `ALERTS{alertstate="firing", alertname!="Watchdog"}` (format table, instant true); transformations: `labelsToFields` then `organize` keeping columns alertname, severity, action, node, instance, gpu, Value (hide Time, `__name__`, job, alertstate); severity column colored by value mapping (critical red, warning orange).

Row 3:
6. **Alerts firing over time** — timeseries, h=8, w=12; queries A `sum(ALERTS{alertstate="firing", severity="critical"}) or vector(0)` legend `critical` (fixed color red), B `sum(ALERTS{alertstate="firing", severity="warning", alertname!="Watchdog"}) or vector(0)` legend `warning` (fixed color orange); drawStyle bars, stacking off, fillOpacity 30, legend visible.
7. **Exporter up matrix** — state-timeline, h=8, w=12; query `up` legend `{{job}}/{{instance}}`; value mappings 1 → `up` (green), 0 → `down` (red); legend hidden; tooltip on.

Dashboard-level: uid `algalon-alerts`, title `Algalon / Alert Center`, plus the Global Constraints conventions (tags/refresh/timezone/datasource variable).

- [ ] **Step 3: Run to verify the harness passes**

Run: `make dashboards-validate` — Expected: PASS on this one file.
Then mutate to prove the harness bites: temporarily change `"refresh"` to `"1m"`, expect FAIL with `refresh != 30s`; restore byte-identically (sha256), re-run green.

- [ ] **Step 4: Wire provisioning**

Create `deploy/compose/host/grafana/provisioning/dashboards/algalon.yml`:

```yaml
apiVersion: 1

providers:
  - name: algalon
    folder: Algalon
    type: file
    disableDeletion: true
    updateIntervalSeconds: 30
    options:
      path: /var/lib/grafana/dashboards/algalon
```

In `deploy/compose/host/docker-compose.yml`, add to the grafana service volumes (keep existing lines):

```yaml
      - ../../../monitoring/dashboards:/var/lib/grafana/dashboards/algalon:ro
```

Run: `make compose-validate` — Expected: PASS.

- [ ] **Step 5: Add CI step**

In `.github/workflows/monitoring-test.yml`, after "Validate compose stacks":

```yaml
      - name: Validate dashboards
        run: make dashboards-validate
```

- [ ] **Step 6: Full gate + commit**

Run: `make rules-validate rules-test scrape-validate alertmanager-validate compose-validate dashboards-validate` — all PASS.

```bash
git add monitoring/dashboards/alert-center.json deploy/compose/host/ Makefile .github/workflows/monitoring-test.yml
git commit -m "feat: Add Alert Center dashboard with provisioning and validation harness"
```

---

### Task 2: GPU Fleet Overview dashboard

**Files:**
- Create: `monitoring/dashboards/gpu-fleet.json`

**Interfaces:** Consumes harness + conventions from Task 1. uid `algalon-fleet`.

- [ ] **Step 1: Author the dashboard** with exactly these panels:

Row 1 (stat tiles, h=4, w=6 each):
1. **GPUs reporting** — `count(DCGM_FI_DEV_GPU_UTIL)`; thresholds none (blue fixed).
2. **Avg GPU util** — `avg(DCGM_FI_DEV_GPU_UTIL)`; unit percent (0-100); thresholds none.
3. **Total power** — `sum(DCGM_FI_DEV_POWER_USAGE)`; unit watt.
4. **Hottest GPU** — `max(DCGM_FI_DEV_GPU_TEMP)`; unit celsius; thresholds 0=green, 85=orange, 92=red.

Row 2:
5. **Fleet utilization stripes** — state-timeline, h=12, w=24; query `DCGM_FI_DEV_GPU_UTIL` legend `{{node}} {{instance}} GPU {{gpu}}`; color mode `continuous-blues` (sequential single hue — the report Fig 18 heatmap form; NEVER a rainbow scheme); legend hidden; tooltip single; panel description: "Per-GPU utilization over time; stragglers appear as pale stripes."

Row 3 (timeseries, h=8, w=12 each; both filtered by `$node`):
6. **GPU temperature — $node** — `DCGM_FI_DEV_GPU_TEMP{node="$node"}` legend `GPU {{gpu}}`; unit celsius; threshold lines at 85 (orange) and 92 (red) drawn as thresholds with `line` display; single y-axis.
7. **FB memory used — $node** — `DCGM_FI_DEV_FB_USED{node="$node"}` legend `GPU {{gpu}}`; unit mbytes; single y-axis.

Template variables: `datasource` + `node` (per Global Constraints). Note: DCGM series carry the `node` label via the file_sd targets (Phase 2 contract).

- [ ] **Step 2: Validate + commit**

Run: `make dashboards-validate` (PASS; harness now checks 2 files).

```bash
git add monitoring/dashboards/gpu-fleet.json
git commit -m "feat: Add GPU Fleet Overview dashboard"
```

---

### Task 3: Node Health (Precursors) dashboard

**Files:**
- Create: `monitoring/dashboards/node-health.json`

**Interfaces:** uid `algalon-node`. Reproduces report Fig 2–3 peer-band views backing the node-precursor rule group.

- [ ] **Step 1: Author the dashboard** — four peer-band timeseries panels (h=9, w=12, 2×2 grid), all using the same pattern and the `$node` variable:

Peer-band pattern (apply per panel; EXPR is the per-instance expression below):
- Query A `quantile(0.05, EXPR)` legend `P5`; custom color gray (#B0B0B0), lineWidth 0, fillOpacity 0.
- Query B `quantile(0.95, EXPR)` legend `P95`; same gray, lineWidth 0, custom `fillBelowTo: "P5"`, fillOpacity 20.
- Query C `quantile(0.5, EXPR)` legend `median`; gray, lineWidth 1, lineStyle dash.
- Query D `EXPR` filtered to the selected node (`{node="$node"}` inside the selector) legend `$node`; fixed color blue, lineWidth 2.
- Legend visible (4 entries); tooltip mode all; single y-axis.

Panels:
1. **Interrupt rate** — EXPR `rate(node_intr_total[5m])`, selected-node query `rate(node_intr_total{node="$node"}[5m])`; unit `ops`; description "Report Fig 2: collapse below the band preceded/accompanied NVLink+Bus faults."
2. **Runnable processes** — EXPR `avg_over_time(node_procs_running[10m])`, selected `avg_over_time(node_procs_running{node="$node"}[10m])`; unit short.
3. **Page-out rate** — EXPR `rate(node_vmstat_pgpgout[5m])`, selected `rate(node_vmstat_pgpgout{node="$node"}[5m])`; unit `ops`.
4. **NFS GETATTR latency** — EXPR `sum by (instance) (rate(node_mountstats_nfs_operations_response_time_seconds_total{operation="GETATTR"}[5m])) / sum by (instance) (rate(node_mountstats_nfs_operations_requests_total{operation="GETATTR"}[5m]))`, selected-node variant adds `node="$node"` to both selectors; unit s; description "Report Fig 3: GETATTR spike then flatline at worker death."

- [ ] **Step 2: Validate + commit**

Run: `make dashboards-validate`.

```bash
git add monitoring/dashboards/node-health.json
git commit -m "feat: Add Node Health precursor dashboard with peer bands"
```

---

### Task 4: Checkpoint & Storage I/O dashboard

**Files:**
- Create: `monitoring/dashboards/checkpoint-io.json`

**Interfaces:** uid `algalon-checkpoint`. Consumes Phase 1 recording rules `algalon:*`.

- [ ] **Step 1: Author the dashboard** (report Fig 5 reproduction — aligned time axes top to bottom):

1. **Training phase** — state-timeline, h=4, w=24; queries A `algalon:checkpoint_save_phase` legend `Save`, B `algalon:checkpoint_load_phase` legend `Load`; value mappings per series: 1 → `Save` (orange) / `Load` (green), 0 → transparent (no text); description: "Absent series = unknown (NFS or DCGM data missing), not 'not training'."
2. **Cluster mean GPU util** — timeseries, h=6, w=24; `avg(DCGM_FI_DEV_GPU_UTIL)` legend `mean util`; unit percent; fixed blue; fillOpacity 15.
3. **NFS write throughput** — timeseries, h=6, w=12; `algalon:nfs_write_bytes_per_second` legend `write`; unit Bps; threshold line at 20000000000 (orange, "Save threshold 20 GB/s"); fixed blue.
4. **NFS read throughput** — timeseries, h=6, w=12; `algalon:nfs_read_bytes_per_second` legend `read`; unit Bps; y-axis scale log (base 10); fixed blue.
5. **RPC queue-time share** — timeseries, h=6, w=12; `sum by (instance) (rate(node_mountstats_nfs_operations_queue_time_seconds_total[5m])) / sum by (instance) (rate(node_mountstats_nfs_operations_request_time_seconds_total[5m]))` legend `{{instance}}`; unit percentunit, max 1; threshold line 0.9 (red); description "Report §4.2.5: 93.1% of WRITE latency was queueing."
6. **NFS major timeouts** — timeseries, h=6, w=12; `sum by (instance) (rate(node_mountstats_nfs_operations_major_timeouts_total[5m]))` legend `{{instance}}`; unit ops.

Template variables: `datasource` only (cluster-level dashboard).

- [ ] **Step 2: Validate + commit**

Run: `make dashboards-validate`.

```bash
git add monitoring/dashboards/checkpoint-io.json
git commit -m "feat: Add Checkpoint and Storage I/O dashboard"
```

---

### Task 5: all-smi dashboard port + docs + status

**Files:**
- Create: `monitoring/dashboards/all-smi.json`
- Modify: `deploy/compose/README.md` (dashboards section)
- Modify: `IMPLEMENTATION_PLAN.md` (Phase 3 done)

- [ ] **Step 1: Port the legacy all-smi dashboard**

Read `algalon_host/grafana/dashboards/all-smi-monitoring.json` (legacy; do NOT modify it). Recreate it as `monitoring/dashboards/all-smi.json` with: uid `algalon-allsmi`, title `Algalon / all-smi (Optional)`, the Task 1 conventions (tags/refresh/timezone/`${datasource}` on every target), and its existing `all_smi_*` panels/queries carried over unchanged where they are compatible with the conventions. Add a dashboard description: "Populated only when workers run the all-smi profile (see deploy/compose/README.md)."

- [ ] **Step 2: Update `deploy/compose/README.md`**

Append a `## Dashboards` section:

```markdown
## Dashboards

Provisioned automatically from `monitoring/dashboards/` into the Grafana
folder **Algalon** (see `host/grafana/provisioning/dashboards/algalon.yml`):

- **Alert Center** — firing alerts, severity counts, Watchdog pipeline
  check, exporter up matrix
- **GPU Fleet Overview** — fleet utilization stripes, temperature/memory
  per node
- **Node Health (Precursors)** — peer-band views (P5–P95 vs selected node)
  behind the node-precursor alert rules
- **Checkpoint & Storage I/O** — Save/Load phase bands, NFS throughput,
  RPC queue-time share
- **all-smi (Optional)** — populated only with the worker all-smi profile

Edit a dashboard JSON in `monitoring/dashboards/` and Grafana picks it up
within 30s (`updateIntervalSeconds`). UI edits are not persisted to git —
export and commit them.
```

- [ ] **Step 3: Update `IMPLEMENTATION_PLAN.md`**

Mark Phase 3 row `✅ done` with plan path `docs/superpowers/plans/2026-08-07-alert-center-phase3-dashboards.md`.

- [ ] **Step 4: Full gate + manual verification note + commit**

Run: `make rules-validate rules-test scrape-validate alertmanager-validate compose-validate dashboards-validate` — all PASS.

Manual verification (document actual results in your report; run only if docker resources allow): `cd deploy/compose/host && docker compose up -d victoriametrics grafana`, open Grafana :3000, confirm the Algalon folder shows 5 dashboards and panels render without JSON errors (empty data is expected without workers), then `docker compose down`.

```bash
git add monitoring/dashboards/all-smi.json deploy/compose/README.md IMPLEMENTATION_PLAN.md
git commit -m "feat: Port all-smi dashboard and document dashboard provisioning"
```

---

## Self-Review Notes

- Coverage vs agreed 5-dashboard set: Alert Center (T1), Fleet heatmap-style stripes (T2), precursor peer-bands (T3), checkpoint phase bands from `algalon:*` recording rules (T4), all-smi profile-only (T5). Carry-forward honored: `checkpoint_load_phase` absent = "unknown" (T4 panel description).
- dataviz compliance encoded: sequential single-hue stripes (no rainbow), status colors only for severity/thresholds/up-down, neutral gray peer bands + single accent, one y-axis everywhere (log-scale read panel is its own panel, not a second axis).
- Consistency: uid registry unique (harness enforces); every panel uses `${datasource}`; `node` label contract from Phase 2 used in $node-filtered queries.
- Judgment calls: state-timeline with continuous color for fleet stripes (Grafana's heatmap panel buckets values and cannot do entity×time stripes reliably); jq harness validates conventions rather than full schema (Grafana tolerates schema drift; conventions are what break provisioning portability); visual rendering is a documented manual step since CI has no Grafana.
