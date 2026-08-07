# Alert Center Phase 1: monitoring/ Single Source Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `monitoring/` as the single source of truth: 6 vmalert rule groups encoding the Lablup report's failure taxonomy, vmagent scrape config, dcgm-exporter counters CSV — all validated by unit tests runnable in CI without GPU hardware.

**Architecture:** Rules are plain vmalert YAML under `monitoring/rules/`, unit-tested with `vmalert-tool unittest` (promtool-compatible test format) via Docker. Scrape config lives in `monitoring/scrape/` and is validated with `vmagent -dryRun`. Nothing in this phase touches `deploy/` — compose/helm/terraform consume these files in later phases.

**Tech Stack:** VictoriaMetrics toolchain v1.149.0 (vmalert, vmalert-tool, vmagent) via Docker; MetricsQL; dcgm-exporter 4.6.0-4.8.3 metric names; node_exporter v1.12.1 metric names.

**Spec:** `docs/superpowers/specs/2026-08-07-alert-center-design.md` (approved)

## Global Constraints

- Component versions: VictoriaMetrics/vmagent/vmalert/vmalert-tool `v1.149.0`, dcgm-exporter `4.6.0-4.8.3`, node_exporter `v1.12.1`, all-smi `v0.25.0`.
- `monitoring/` is the ONLY home for rules/dashboards/exporter configs. Never copy them elsewhere.
- Alert labels: `severity` ∈ {`critical`, `warning`, `none`}; `action` ∈ {`restart_app`, `reset_gpu`, `restart_bm`, `replace_gpu`, `schedule_reset`, `watch_trend`, `investigate`}. Phase 2 Alertmanager routing keys off `severity`; do not invent other values.
- Alert names: PascalCase prefixed by layer — `Gpu*` (DCGM), `Node*` (node_exporter), `Nfs*` (mountstats), plus `ExporterDown`/`DcgmMetricsMissing`/`Watchdog` in meta.
- Recording rules are namespaced `algalon:*`.
- Rule annotations carry a single `summary`; operational context (report references, thresholds rationale) goes in YAML comments above each rule. Unit tests assert `exp_labels` and `exp_annotations` — summary strings in tests must match rules byte-for-byte after template resolution.
- XID severity mapping is fixed by the spec (§5.1): 31/43/94 → warning, 119/145/149 → critical, 79 → critical. Do not deviate.
- Evaluation/scrape interval: 30s (report Table 8).
- All work in worktree `.claude/worktrees/alert-center-redesign`, branch `feat/alert-center-redesign`. Commit after every task. English for code/commits.
- Run `make rules-validate rules-test` before every commit that touches `monitoring/rules/` or `tests/rules/`.

## File Structure (this phase)

```
monitoring/
├─ rules/
│  ├─ gpu-xid.yml         # XID classification (Task 2)
│  ├─ gpu-ecc.yml         # ECC / row-remap degradation (Task 3)
│  ├─ gpu-health.yml      # thermal / throttle (Task 4)
│  ├─ node-precursor.yml  # peer-relative OS anomalies (Task 5)
│  ├─ storage-nfs.yml     # checkpoint I/O + NFS/RPC (Task 6)
│  └─ meta.yml            # monitoring-of-monitoring (Task 1)
├─ exporters/
│  └─ dcgm-counters.csv   # dcgm-exporter field list (Task 7)
└─ scrape/
   ├─ prometheus.yml      # vmagent scrape config (Task 7)
   └─ targets/
      ├─ dcgm-targets.yml.example
      ├─ node-targets.yml.example
      └─ all-smi-targets.yml.example
tests/rules/
├─ meta.test.yml          # (Task 1)
├─ gpu-xid.test.yml       # (Task 2)
├─ gpu-ecc.test.yml       # (Task 3)
├─ gpu-health.test.yml    # (Task 4)
├─ node-precursor.test.yml# (Task 5)
└─ storage-nfs.test.yml   # (Task 6)
Makefile                  # + rules-validate, rules-test, scrape-validate (Tasks 1, 7)
.github/workflows/monitoring-test.yml  # (Task 8)
```

---

### Task 1: Rule test harness + `meta.yml`

Prove the whole toolchain (vmalert-tool unittest via Docker, Makefile targets) with the simplest rule group, so Tasks 2–6 only add rules and tests.

**Files:**
- Create: `monitoring/rules/meta.yml`
- Create: `tests/rules/meta.test.yml`
- Modify: `Makefile` (append targets; keep existing terraform targets untouched)

**Interfaces:**
- Produces: `make rules-validate` (syntax check all rule files), `make rules-test` (unit tests). Tasks 2–6 rely on both. Alert names `ExporterDown`, `DcgmMetricsMissing`, `Watchdog`.

- [ ] **Step 1: Write the failing test**

Create `tests/rules/meta.test.yml`:

```yaml
rule_files:
  - ../../monitoring/rules/meta.yml

evaluation_interval: 30s

tests:
  # Exporter target down for >5m fires critical
  - interval: 30s
    input_series:
      - series: 'up{job="dcgm", instance="worker1:9400"}'
        values: '1 1 0x20'
    alert_rule_test:
      - eval_time: 11m
        alertname: ExporterDown
        exp_alerts:
          - exp_labels:
              severity: critical
              job: dcgm
              instance: worker1:9400
            exp_annotations:
              summary: 'Exporter dcgm on worker1:9400 has been down for 5m'

  # dcgm job has live targets but publishes no GPU metrics
  - interval: 30s
    input_series:
      - series: 'up{job="dcgm", instance="worker1:9400"}'
        values: '1x20'
    alert_rule_test:
      - eval_time: 6m
        alertname: DcgmMetricsMissing
        exp_alerts:
          - exp_labels:
              severity: warning
            exp_annotations:
              summary: 'dcgm targets are up but no DCGM metrics are being published'

  # Watchdog always fires
  - interval: 30s
    input_series: []
    alert_rule_test:
      - eval_time: 1m
        alertname: Watchdog
        exp_alerts:
          - exp_labels:
              severity: none
            exp_annotations:
              summary: 'Alerting pipeline dead man''s switch; this alert is always firing'
```

- [ ] **Step 2: Add Makefile targets**

Append to `Makefile` (top: extend `.PHONY` line with `rules-validate rules-test scrape-validate`):

```make
# Monitoring / alert rules
VM_VERSION := v1.149.0

rules-validate: ## Validate vmalert rule file syntax
	@docker run --rm -v $(PWD)/monitoring/rules:/rules:ro \
		victoriametrics/vmalert:$(VM_VERSION) \
		-rule=/rules/*.yml -datasource.url=http://localhost:8428 -dryRun
	@echo "✅ vmalert rules valid"

rules-test: ## Run vmalert rule unit tests
	@docker run --rm -v $(PWD):/repo:ro -w /repo \
		victoriametrics/vmalert-tool:$(VM_VERSION) \
		unittest -files='tests/rules/*.test.yml'
	@echo "✅ rule unit tests passed"
```

- [ ] **Step 3: Run test to verify it fails**

Run: `make rules-test`
Expected: FAIL — `monitoring/rules/meta.yml` does not exist (error loading rule file).

- [ ] **Step 4: Write `monitoring/rules/meta.yml`**

```yaml
# Monitoring-of-monitoring (spec §5.6, Lablup report Table 15).
# The alert pipeline itself must be observable: a dead exporter looks like
# "no alerts", which is indistinguishable from "all healthy" without these.
groups:
  - name: meta
    interval: 30s
    rules:
      # Any scrape target down. severity=critical because a blind spot on a
      # GPU node means XID/ECC alerts silently stop working for that node.
      - alert: ExporterDown
        expr: up == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: 'Exporter {{ $labels.job }} on {{ $labels.instance }} has been down for 5m'

      # dcgm-exporter can be "up" while publishing nothing (driver wedged,
      # DCGM daemon dead). absent() alone would also fire on clusters with no
      # NVIDIA nodes, so gate on the dcgm job having live targets.
      - alert: DcgmMetricsMissing
        expr: absent(DCGM_FI_DEV_GPU_TEMP) and on() (count(up{job="dcgm"} == 1) > 0)
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: 'dcgm targets are up but no DCGM metrics are being published'

      # Dead man's switch: always firing; routed to a null receiver in
      # Alertmanager (Phase 2). If the receiver stops seeing it, the pipeline
      # (vmalert -> Alertmanager -> Slack) is broken.
      - alert: Watchdog
        expr: vector(1)
        labels:
          severity: none
        annotations:
          summary: "Alerting pipeline dead man's switch; this alert is always firing"
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `make rules-test` then `make rules-validate`
Expected: both PASS.
Contingency: if vmalert-tool reports it cannot find rule files, the tool resolved `rule_files` relative to CWD instead of the test file — change the test's `rule_files` entry to `monitoring/rules/meta.yml`. If `vmalert -dryRun` complains about the datasource flag, drop `-datasource.url=...` from `rules-validate`.

- [ ] **Step 6: Commit**

```bash
git add monitoring/rules/meta.yml tests/rules/meta.test.yml Makefile
git commit -m "feat: Add vmalert rule test harness and meta rule group"
```

---

### Task 2: `gpu-xid.yml` — XID classification

**Files:**
- Create: `monitoring/rules/gpu-xid.yml`
- Create: `tests/rules/gpu-xid.test.yml`

**Interfaces:**
- Consumes: `make rules-test` / `make rules-validate` from Task 1.
- Produces: alerts `GpuXidRestartApp`, `GpuXidResetGpu`, `GpuXidFellOffBus`, `GpuXidUnclassified` with labels `severity`, `action`. Source metric: `DCGM_FI_DEV_XID_ERRORS` (gauge; value = most recent XID, 0 = none).

- [ ] **Step 1: Write the failing test**

Create `tests/rules/gpu-xid.test.yml`:

```yaml
rule_files:
  - ../../monitoring/rules/gpu-xid.yml

evaluation_interval: 30s

tests:
  # XID 94 (contained ECC) -> app-level restart, warning
  - interval: 30s
    input_series:
      - series: 'DCGM_FI_DEV_XID_ERRORS{instance="worker1:9400", gpu="0"}'
        values: '0 0 94 94 94'
    alert_rule_test:
      - eval_time: 1m30s
        alertname: GpuXidRestartApp
        exp_alerts:
          - exp_labels:
              severity: warning
              action: restart_app
              instance: worker1:9400
              gpu: "0"
            exp_annotations:
              summary: 'XID 94 on worker1:9400 GPU 0: app-level error, restart job session'
      # No other class may fire for XID 94
      - eval_time: 1m30s
        alertname: GpuXidResetGpu
        exp_alerts: []
      - eval_time: 1m30s
        alertname: GpuXidUnclassified
        exp_alerts: []

  # XID 145 (NVLink RLW) -> GPU reset, critical
  - interval: 30s
    input_series:
      - series: 'DCGM_FI_DEV_XID_ERRORS{instance="worker2:9400", gpu="3"}'
        values: '0 145 145'
    alert_rule_test:
      - eval_time: 1m
        alertname: GpuXidResetGpu
        exp_alerts:
          - exp_labels:
              severity: critical
              action: reset_gpu
              instance: worker2:9400
              gpu: "3"
            exp_annotations:
              summary: 'XID 145 on worker2:9400 GPU 3: GPU reset required'

  # XID 79 (fell off bus) -> node reboot, critical
  - interval: 30s
    input_series:
      - series: 'DCGM_FI_DEV_XID_ERRORS{instance="worker3:9400", gpu="1"}'
        values: '0 79 79'
    alert_rule_test:
      - eval_time: 1m
        alertname: GpuXidFellOffBus
        exp_alerts:
          - exp_labels:
              severity: critical
              action: restart_bm
              instance: worker3:9400
              gpu: "1"
            exp_annotations:
              summary: 'XID 79 on worker3:9400 GPU 1: GPU fell off the bus, reboot node'

  # XID 63 (row-remap recording event) is not in the Table 3 mapping
  - interval: 30s
    input_series:
      - series: 'DCGM_FI_DEV_XID_ERRORS{instance="worker4:9400", gpu="2"}'
        values: '0 63 63'
    alert_rule_test:
      - eval_time: 1m
        alertname: GpuXidUnclassified
        exp_alerts:
          - exp_labels:
              severity: warning
              action: investigate
              instance: worker4:9400
              gpu: "2"
            exp_annotations:
              summary: 'Unclassified XID 63 on worker4:9400 GPU 2: consult NVIDIA XID catalog'

  # XID 0 (healthy) fires nothing
  - interval: 30s
    input_series:
      - series: 'DCGM_FI_DEV_XID_ERRORS{instance="worker5:9400", gpu="0"}'
        values: '0x10'
    alert_rule_test:
      - eval_time: 2m
        alertname: GpuXidRestartApp
        exp_alerts: []
      - eval_time: 2m
        alertname: GpuXidUnclassified
        exp_alerts: []
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make rules-test`
Expected: FAIL — cannot load `monitoring/rules/gpu-xid.yml`.

- [ ] **Step 3: Write `monitoring/rules/gpu-xid.yml`**

```yaml
# XID error classification (spec §5.1, Lablup report Table 3).
# DCGM_FI_DEV_XID_ERRORS is a gauge holding the most recent XID (0 = none).
# XID is a post-mortem signal: the GPU has already faulted when it appears.
# The mapping below drives Alertmanager routing (Phase 2) and tells the
# operator what recovery action is sufficient — do not change severities
# without updating the spec.
groups:
  - name: gpu-xid
    interval: 30s
    rules:
      # XID 31 = GPU memory page fault, 43 = GPU stopped processing,
      # 94 = contained ECC error. Application-level: restarting the job
      # session recovers; node exclusion is NOT required (report: these were
      # auto-retried without excluding the node).
      - alert: GpuXidRestartApp
        expr: >-
          DCGM_FI_DEV_XID_ERRORS == 31
          or DCGM_FI_DEV_XID_ERRORS == 43
          or DCGM_FI_DEV_XID_ERRORS == 94
        labels:
          severity: warning
          action: restart_app
        annotations:
          summary: 'XID {{ $value }} on {{ $labels.instance }} GPU {{ $labels.gpu }}: app-level error, restart job session'

      # XID 119 = GSP RPC timeout, 145 = NVLink RLW, 149 = NVLink NETIR.
      # Hardware-level: GPU reset required before the node rejoins scheduling.
      # NVLink errors were the most frequent failure class in the report
      # cluster (29.4% of events).
      - alert: GpuXidResetGpu
        expr: >-
          DCGM_FI_DEV_XID_ERRORS == 119
          or DCGM_FI_DEV_XID_ERRORS == 145
          or DCGM_FI_DEV_XID_ERRORS == 149
        labels:
          severity: critical
          action: reset_gpu
        annotations:
          summary: 'XID {{ $value }} on {{ $labels.instance }} GPU {{ $labels.gpu }}: GPU reset required'

      # XID 79 = GPU fell off the PCIe bus. Node reboot required; recurring
      # XID 79 on the same node means hardware replacement (contact support).
      - alert: GpuXidFellOffBus
        expr: DCGM_FI_DEV_XID_ERRORS == 79
        labels:
          severity: critical
          action: restart_bm
        annotations:
          summary: 'XID 79 on {{ $labels.instance }} GPU {{ $labels.gpu }}: GPU fell off the bus, reboot node'

      # Any other nonzero XID: not covered by the report's Table 3 mapping.
      - alert: GpuXidUnclassified
        expr: >-
          DCGM_FI_DEV_XID_ERRORS > 0
          and DCGM_FI_DEV_XID_ERRORS != 31
          and DCGM_FI_DEV_XID_ERRORS != 43
          and DCGM_FI_DEV_XID_ERRORS != 94
          and DCGM_FI_DEV_XID_ERRORS != 79
          and DCGM_FI_DEV_XID_ERRORS != 119
          and DCGM_FI_DEV_XID_ERRORS != 145
          and DCGM_FI_DEV_XID_ERRORS != 149
        labels:
          severity: warning
          action: investigate
        annotations:
          summary: 'Unclassified XID {{ $value }} on {{ $labels.instance }} GPU {{ $labels.gpu }}: consult NVIDIA XID catalog'
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make rules-test && make rules-validate`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add monitoring/rules/gpu-xid.yml tests/rules/gpu-xid.test.yml
git commit -m "feat: Add XID classification alert rules (Lablup Table 3 mapping)"
```

---

### Task 3: `gpu-ecc.yml` — ECC / row-remap degradation

**Files:**
- Create: `monitoring/rules/gpu-ecc.yml`
- Create: `tests/rules/gpu-ecc.test.yml`

**Interfaces:**
- Produces: alerts `GpuUncorrectableRowRemap`, `GpuRowRemapFailure`, `GpuRowRemapPending`, `GpuCorrectableRemapGrowth`, `GpuDoubleBitEccError`. Source metrics: `DCGM_FI_DEV_UNCORRECTABLE_REMAPPED_ROWS`, `DCGM_FI_DEV_CORRECTABLE_REMAPPED_ROWS`, `DCGM_FI_DEV_ROW_REMAP_FAILURE`, `DCGM_FI_DEV_ROW_REMAP_PENDING` (gauges), `DCGM_FI_DEV_ECC_DBE_VOL_TOTAL` (counter).

- [ ] **Step 1: Write the failing test**

Create `tests/rules/gpu-ecc.test.yml`:

```yaml
rule_files:
  - ../../monitoring/rules/gpu-ecc.yml

evaluation_interval: 30s

tests:
  # Uncorrectable remapped rows increased -> critical
  - interval: 30s
    input_series:
      - series: 'DCGM_FI_DEV_UNCORRECTABLE_REMAPPED_ROWS{instance="worker1:9400", gpu="1"}'
        values: '1 1 1 2 2 2'
    alert_rule_test:
      - eval_time: 2m30s
        alertname: GpuUncorrectableRowRemap
        exp_alerts:
          - exp_labels:
              severity: critical
              action: replace_gpu
              instance: worker1:9400
              gpu: "1"
            exp_annotations:
              summary: 'Uncorrectable remapped rows increased on worker1:9400 GPU 1: permanent memory damage accumulating'

  # Row remap failure flag -> critical (GPU must be replaced)
  - interval: 30s
    input_series:
      - series: 'DCGM_FI_DEV_ROW_REMAP_FAILURE{instance="worker1:9400", gpu="1"}'
        values: '0 0 1 1'
    alert_rule_test:
      - eval_time: 1m30s
        alertname: GpuRowRemapFailure
        exp_alerts:
          - exp_labels:
              severity: critical
              action: replace_gpu
              instance: worker1:9400
              gpu: "1"
            exp_annotations:
              summary: 'Row remap FAILURE on worker1:9400 GPU 1: remapping exhausted, replace GPU'

  # Remap pending for 5m -> warning (needs GPU reset to apply)
  - interval: 30s
    input_series:
      - series: 'DCGM_FI_DEV_ROW_REMAP_PENDING{instance="worker2:9400", gpu="0"}'
        values: '1x20'
    alert_rule_test:
      - eval_time: 6m
        alertname: GpuRowRemapPending
        exp_alerts:
          - exp_labels:
              severity: warning
              action: schedule_reset
              instance: worker2:9400
              gpu: "0"
            exp_annotations:
              summary: 'Row remap pending on worker2:9400 GPU 0: schedule a GPU reset to apply remapping'

  # Correctable remap growth: +100 rows within 24h window -> warning
  - interval: 30s
    input_series:
      - series: 'DCGM_FI_DEV_CORRECTABLE_REMAPPED_ROWS{instance="worker3:9400", gpu="2"}'
        values: '0+1x100'
    alert_rule_test:
      - eval_time: 50m
        alertname: GpuCorrectableRemapGrowth
        exp_alerts:
          - exp_labels:
              severity: warning
              action: watch_trend
              instance: worker3:9400
              gpu: "2"
            exp_annotations:
              summary: 'Correctable remapped rows on worker3:9400 GPU 2 grew by more than 8 in 24h: memory degrading'

  # Stable correctable count fires nothing
  - interval: 30s
    input_series:
      - series: 'DCGM_FI_DEV_CORRECTABLE_REMAPPED_ROWS{instance="worker4:9400", gpu="0"}'
        values: '25x100'
    alert_rule_test:
      - eval_time: 50m
        alertname: GpuCorrectableRemapGrowth
        exp_alerts: []

  # Volatile double-bit ECC error -> critical
  - interval: 30s
    input_series:
      - series: 'DCGM_FI_DEV_ECC_DBE_VOL_TOTAL{instance="worker5:9400", gpu="7"}'
        values: '0 0 0 1 1'
    alert_rule_test:
      - eval_time: 2m
        alertname: GpuDoubleBitEccError
        exp_alerts:
          - exp_labels:
              severity: critical
              action: restart_app
              instance: worker5:9400
              gpu: "7"
            exp_annotations:
              summary: 'Double-bit ECC error on worker5:9400 GPU 7'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make rules-test` — Expected: FAIL (rule file missing).

- [ ] **Step 3: Write `monitoring/rules/gpu-ecc.yml`**

```yaml
# ECC / row-remapping degradation (spec §5.2, Lablup report §4.1.2, Fig 4).
# Remapped-row counters are the GPU's permanent-damage ledger. Report case
# gpu122: uncorrectable remaps stepped up together with XID 94 until the GPU
# died. Report case gpu124: 254 CORRECTABLE remaps accumulated over 55 days
# with zero XID errors before the GPU vanished from the host — so the growth
# TREND matters, not the absolute count. NVIDIA flags ROW_REMAP_FAILURE at
# 8 uncorrectable remaps per memory bank.
groups:
  - name: gpu-ecc
    interval: 30s
    rules:
      # Any increase in uncorrectable remaps = new permanent defect.
      # delta() (not increase): these are gauges; GPU replacement resets the
      # count, and a negative delta must not fire.
      - alert: GpuUncorrectableRowRemap
        expr: delta(DCGM_FI_DEV_UNCORRECTABLE_REMAPPED_ROWS[10m]) > 0
        labels:
          severity: critical
          action: replace_gpu
        annotations:
          summary: 'Uncorrectable remapped rows increased on {{ $labels.instance }} GPU {{ $labels.gpu }}: permanent memory damage accumulating'

      # Remapping exhausted; NVIDIA docs: replace the GPU.
      - alert: GpuRowRemapFailure
        expr: DCGM_FI_DEV_ROW_REMAP_FAILURE > 0
        labels:
          severity: critical
          action: replace_gpu
        annotations:
          summary: 'Row remap FAILURE on {{ $labels.instance }} GPU {{ $labels.gpu }}: remapping exhausted, replace GPU'

      # Remap recorded but needs a GPU reset to take effect.
      - alert: GpuRowRemapPending
        expr: DCGM_FI_DEV_ROW_REMAP_PENDING > 0
        for: 5m
        labels:
          severity: warning
          action: schedule_reset
        annotations:
          summary: 'Row remap pending on {{ $labels.instance }} GPU {{ $labels.gpu }}: schedule a GPU reset to apply remapping'

      # Growth-trend rule (report gpu124). Threshold 8/24h mirrors the NVIDIA
      # per-bank failure threshold as a conservative "degrading fast" signal.
      - alert: GpuCorrectableRemapGrowth
        expr: delta(DCGM_FI_DEV_CORRECTABLE_REMAPPED_ROWS[24h]) > 8
        labels:
          severity: warning
          action: watch_trend
        annotations:
          summary: 'Correctable remapped rows on {{ $labels.instance }} GPU {{ $labels.gpu }} grew by more than 8 in 24h: memory degrading'

      # Volatile DBE counter: uncorrected memory error hit a running process.
      # Usually accompanied by XID 94 (contained) — app restart recovers.
      - alert: GpuDoubleBitEccError
        expr: increase(DCGM_FI_DEV_ECC_DBE_VOL_TOTAL[5m]) > 0
        labels:
          severity: critical
          action: restart_app
        annotations:
          summary: 'Double-bit ECC error on {{ $labels.instance }} GPU {{ $labels.gpu }}'
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make rules-test && make rules-validate` — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add monitoring/rules/gpu-ecc.yml tests/rules/gpu-ecc.test.yml
git commit -m "feat: Add ECC and row-remap degradation alert rules"
```

---

### Task 4: `gpu-health.yml` — thermal / throttle

**Files:**
- Create: `monitoring/rules/gpu-health.yml`
- Create: `tests/rules/gpu-health.test.yml`

**Interfaces:**
- Produces: alerts `GpuTempHigh`, `GpuTempCritical`, `GpuMemoryTempHigh`, `GpuClocksThrottled`. Source metrics: `DCGM_FI_DEV_GPU_TEMP`, `DCGM_FI_DEV_MEMORY_TEMP`, `DCGM_FI_DEV_CLOCKS_EVENT_REASONS` (dcgm-exporter 4.x name; 3.x called it `DCGM_FI_DEV_CLOCK_THROTTLE_REASONS`).

- [ ] **Step 1: Write the failing test**

Create `tests/rules/gpu-health.test.yml`:

```yaml
rule_files:
  - ../../monitoring/rules/gpu-health.yml

evaluation_interval: 30s

tests:
  # 88C sustained -> warning only, not critical
  - interval: 30s
    input_series:
      - series: 'DCGM_FI_DEV_GPU_TEMP{instance="worker1:9400", gpu="0"}'
        values: '88x20'
    alert_rule_test:
      - eval_time: 6m
        alertname: GpuTempHigh
        exp_alerts:
          - exp_labels:
              severity: warning
              action: investigate
              instance: worker1:9400
              gpu: "0"
            exp_annotations:
              summary: 'GPU temperature 88C on worker1:9400 GPU 0 (>85C for 5m)'
      - eval_time: 6m
        alertname: GpuTempCritical
        exp_alerts: []

  # 95C sustained -> critical fires (warning also fires; assert both)
  - interval: 30s
    input_series:
      - series: 'DCGM_FI_DEV_GPU_TEMP{instance="worker2:9400", gpu="1"}'
        values: '95x20'
    alert_rule_test:
      - eval_time: 6m
        alertname: GpuTempCritical
        exp_alerts:
          - exp_labels:
              severity: critical
              action: investigate
              instance: worker2:9400
              gpu: "1"
            exp_annotations:
              summary: 'GPU temperature 95C on worker2:9400 GPU 1 (>92C for 2m)'

  # HBM temperature high -> warning
  - interval: 30s
    input_series:
      - series: 'DCGM_FI_DEV_MEMORY_TEMP{instance="worker3:9400", gpu="2"}'
        values: '97x20'
    alert_rule_test:
      - eval_time: 6m
        alertname: GpuMemoryTempHigh
        exp_alerts:
          - exp_labels:
              severity: warning
              action: investigate
              instance: worker3:9400
              gpu: "2"
            exp_annotations:
              summary: 'HBM temperature 97C on worker3:9400 GPU 2 (>95C for 5m)'

  # Throttle bitmask 8 (HW slowdown) sustained 10m -> warning
  - interval: 30s
    input_series:
      - series: 'DCGM_FI_DEV_CLOCKS_EVENT_REASONS{instance="worker4:9400", gpu="3"}'
        values: '8x30'
    alert_rule_test:
      - eval_time: 11m
        alertname: GpuClocksThrottled
        exp_alerts:
          - exp_labels:
              severity: warning
              action: investigate
              instance: worker4:9400
              gpu: "3"
            exp_annotations:
              summary: 'GPU clocks throttled (reason bitmask 8) on worker4:9400 GPU 3 for 10m'

  # Benign reasons (idle 0x1, app clocks 0x2, SW power cap 0x4) never fire
  - interval: 30s
    input_series:
      - series: 'DCGM_FI_DEV_CLOCKS_EVENT_REASONS{instance="worker5:9400", gpu="0"}'
        values: '4x30'
    alert_rule_test:
      - eval_time: 11m
        alertname: GpuClocksThrottled
        exp_alerts: []
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make rules-test` — Expected: FAIL (rule file missing).

- [ ] **Step 3: Write `monitoring/rules/gpu-health.yml`**

```yaml
# Thermal / throttle health (spec §5.3, Lablup report Table 8).
# Thresholds are conservative defaults for datacenter NVIDIA parts; tune per
# fleet if your hardware documents different limits.
groups:
  - name: gpu-health
    interval: 30s
    rules:
      - alert: GpuTempHigh
        expr: DCGM_FI_DEV_GPU_TEMP > 85
        for: 5m
        labels:
          severity: warning
          action: investigate
        annotations:
          summary: 'GPU temperature {{ $value }}C on {{ $labels.instance }} GPU {{ $labels.gpu }} (>85C for 5m)'

      - alert: GpuTempCritical
        expr: DCGM_FI_DEV_GPU_TEMP > 92
        for: 2m
        labels:
          severity: critical
          action: investigate
        annotations:
          summary: 'GPU temperature {{ $value }}C on {{ $labels.instance }} GPU {{ $labels.gpu }} (>92C for 2m)'

      # HBM runs hotter than the die; sustained >95C accelerates memory wear
      # (and ECC/remap degradation tracked in gpu-ecc.yml).
      - alert: GpuMemoryTempHigh
        expr: DCGM_FI_DEV_MEMORY_TEMP > 95
        for: 5m
        labels:
          severity: warning
          action: investigate
        annotations:
          summary: 'HBM temperature {{ $value }}C on {{ $labels.instance }} GPU {{ $labels.gpu }} (>95C for 5m)'

      # CLOCKS_EVENT_REASONS is a bitmask. Bits <0x8 are benign (0x1 GPU
      # idle, 0x2 application clocks setting, 0x4 SW power cap — normal
      # during training). Bits >=0x8 (HW slowdown / thermal / power brake /
      # sync boost) indicate real performance loss: a fail-slow signal, the
      # straggler class the report says is harder to catch than fail-stop.
      - alert: GpuClocksThrottled
        expr: DCGM_FI_DEV_CLOCKS_EVENT_REASONS >= 8
        for: 10m
        labels:
          severity: warning
          action: investigate
        annotations:
          summary: 'GPU clocks throttled (reason bitmask {{ $value }}) on {{ $labels.instance }} GPU {{ $labels.gpu }} for 10m'
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make rules-test && make rules-validate` — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add monitoring/rules/gpu-health.yml tests/rules/gpu-health.test.yml
git commit -m "feat: Add GPU thermal and throttle alert rules"
```

---

### Task 5: `node-precursor.yml` — peer-relative OS anomalies

**Files:**
- Create: `monitoring/rules/node-precursor.yml`
- Create: `tests/rules/node-precursor.test.yml`

**Interfaces:**
- Produces: alerts `NodeInterruptRateCollapse`, `NodeRunnableProcsCollapse`, `NodePageOutBurst`. Source metrics: `node_intr_total`, `node_procs_running`, `node_vmstat_pgpgout`, guard on `up{job="node"}`.

- [ ] **Step 1: Write the failing test**

Create `tests/rules/node-precursor.test.yml`. Peer-relative rules need ≥3 node series plus `up{job="node"}` guards:

```yaml
rule_files:
  - ../../monitoring/rules/node-precursor.yml

evaluation_interval: 30s

tests:
  # worker3's interrupt rate collapses to 10% of peers -> warning
  # w1/w2: +300000 per 30s sample (rate 10000/s).
  # w3: same for 10m, then +30000 per sample (rate 1000/s) for 30m.
  - interval: 30s
    input_series:
      - series: 'node_intr_total{instance="w1:9100"}'
        values: '0+300000x80'
      - series: 'node_intr_total{instance="w2:9100"}'
        values: '0+300000x80'
      - series: 'node_intr_total{instance="w3:9100"}'
        values: '0+300000x20 6000000+30000x60'
      - series: 'up{job="node", instance="w1:9100"}'
        values: '1x80'
      - series: 'up{job="node", instance="w2:9100"}'
        values: '1x80'
      - series: 'up{job="node", instance="w3:9100"}'
        values: '1x80'
    alert_rule_test:
      - eval_time: 30m
        alertname: NodeInterruptRateCollapse
        exp_alerts:
          - exp_labels:
              severity: warning
              action: investigate
              instance: w3:9100
            exp_annotations:
              summary: 'Interrupt rate on w3:9100 collapsed below half the cluster median'
      # Healthy peers do not fire
      - eval_time: 8m
        alertname: NodeInterruptRateCollapse
        exp_alerts: []

  # worker3's runnable process count drops to 0 while peers stay ~30
  - interval: 30s
    input_series:
      - series: 'node_procs_running{instance="w1:9100"}'
        values: '30x80'
      - series: 'node_procs_running{instance="w2:9100"}'
        values: '30x80'
      - series: 'node_procs_running{instance="w3:9100"}'
        values: '30x10 0x70'
      - series: 'up{job="node", instance="w1:9100"}'
        values: '1x80'
      - series: 'up{job="node", instance="w2:9100"}'
        values: '1x80'
      - series: 'up{job="node", instance="w3:9100"}'
        values: '1x80'
    alert_rule_test:
      - eval_time: 26m
        alertname: NodeRunnableProcsCollapse
        exp_alerts:
          - exp_labels:
              severity: warning
              action: investigate
              instance: w3:9100
            exp_annotations:
              summary: 'Runnable processes on w3:9100 collapsed to near zero while cluster median is above 10'

  # worker3 page-out rate spikes to 40x the cluster median
  # w1/w2: +3000 per sample (rate 100/s); w3 jumps to +120000 (rate 4000/s).
  - interval: 30s
    input_series:
      - series: 'node_vmstat_pgpgout{instance="w1:9100"}'
        values: '0+3000x60'
      - series: 'node_vmstat_pgpgout{instance="w2:9100"}'
        values: '0+3000x60'
      - series: 'node_vmstat_pgpgout{instance="w3:9100"}'
        values: '0+3000x20 60000+120000x40'
      - series: 'up{job="node", instance="w1:9100"}'
        values: '1x60'
      - series: 'up{job="node", instance="w2:9100"}'
        values: '1x60'
      - series: 'up{job="node", instance="w3:9100"}'
        values: '1x60'
    alert_rule_test:
      - eval_time: 25m
        alertname: NodePageOutBurst
        exp_alerts:
          - exp_labels:
              severity: warning
              action: investigate
              instance: w3:9100
            exp_annotations:
              summary: 'Page-out rate on w3:9100 is more than 4x the cluster median'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make rules-test` — Expected: FAIL (rule file missing).

- [ ] **Step 3: Write `monitoring/rules/node-precursor.yml`**

```yaml
# Peer-relative OS anomaly signals (spec §5.4, Lablup report §4.1.2).
# Report finding F1: across 10 XID-tagged failures there was NO single
# dominant precursor metric — so these are conservative warning-only
# supporting signals, never critical pages.
# Report Fig 2 (gpu071, NVLink+Bus Fault): interrupts fell from ~300K to
# 70K-100K per 30s and runnable processes dropped to ~0 at the fault.
# Report Fig 3 (gpu096, ECC): NFS GETATTR latency and page-out spiked at the
# XID (the NFS side lives in storage-nfs.yml).
# All rules compare a node against the cluster median (works at any cluster
# size) and are gated on >=3 live node-exporter targets, below which a
# median is meaningless.
groups:
  - name: node-precursor
    interval: 30s
    rules:
      - alert: NodeInterruptRateCollapse
        expr: >-
          (
            rate(node_intr_total[5m])
              < scalar(0.5 * quantile(0.5, rate(node_intr_total[5m])))
          )
          and on() (count(up{job="node"} == 1) >= 3)
        for: 10m
        labels:
          severity: warning
          action: investigate
        annotations:
          summary: 'Interrupt rate on {{ $labels.instance }} collapsed below half the cluster median'

      - alert: NodeRunnableProcsCollapse
        expr: >-
          (
            avg_over_time(node_procs_running[10m]) < 2
            and on() (quantile(0.5, avg_over_time(node_procs_running[10m])) > 10)
          )
          and on() (count(up{job="node"} == 1) >= 3)
        for: 10m
        labels:
          severity: warning
          action: investigate
        annotations:
          summary: 'Runnable processes on {{ $labels.instance }} collapsed to near zero while cluster median is above 10'

      # +1 in the threshold keeps this quiet when the cluster median is ~0
      # (idle cluster: any small page-out would otherwise be "4x median").
      - alert: NodePageOutBurst
        expr: >-
          (
            rate(node_vmstat_pgpgout[5m])
              > scalar(4 * quantile(0.5, rate(node_vmstat_pgpgout[5m])) + 1)
          )
          and on() (count(up{job="node"} == 1) >= 3)
        for: 10m
        labels:
          severity: warning
          action: investigate
        annotations:
          summary: 'Page-out rate on {{ $labels.instance }} is more than 4x the cluster median'
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make rules-test && make rules-validate` — Expected: PASS.
Contingency: if a firing time is off by one evaluation step (peer-relative expressions cross thresholds gradually), adjust the test's `eval_time` by ±1–2m until green, but never weaken the `exp_alerts: []` negative assertions.

- [ ] **Step 5: Commit**

```bash
git add monitoring/rules/node-precursor.yml tests/rules/node-precursor.test.yml
git commit -m "feat: Add peer-relative node precursor alert rules"
```

---

### Task 6: `storage-nfs.yml` — checkpoint I/O + NFS/RPC

**Files:**
- Create: `monitoring/rules/storage-nfs.yml`
- Create: `tests/rules/storage-nfs.test.yml`

**Interfaces:**
- Produces: recording rules `algalon:nfs_write_bytes_per_second`, `algalon:nfs_read_bytes_per_second`, `algalon:checkpoint_save_phase`, `algalon:checkpoint_load_phase` (consumed by Phase 3 dashboards); alerts `NfsOperationSlow`, `NfsQueueTimeDominant`, `NfsMajorTimeouts`. Source metrics: `node_mountstats_nfs_operations_{requests_total,sent_bytes_total,received_bytes_total,queue_time_seconds_total,response_time_seconds_total,request_time_seconds_total,major_timeouts_total}` (all require node_exporter `--collector.mountstats`), `DCGM_FI_DEV_GPU_UTIL`.

- [ ] **Step 1: Write the failing test**

Create `tests/rules/storage-nfs.test.yml`:

```yaml
rule_files:
  - ../../monitoring/rules/storage-nfs.yml

evaluation_interval: 30s

tests:
  # Save-phase recording rule: cluster WRITE throughput 25 GB/s > 20 GB/s
  # (+750e9 bytes per 30s sample = 25e9 B/s)
  - interval: 30s
    input_series:
      - series: 'node_mountstats_nfs_operations_sent_bytes_total{instance="w1:9100", operation="WRITE"}'
        values: '0+750000000000x30'
    promql_expr_test:
      - expr: algalon:checkpoint_save_phase
        eval_time: 5m
        exp_samples:
          - labels: 'algalon:checkpoint_save_phase'
            value: 1

  # Load-phase recording rule: cluster READ 3 GB/s with mean GPU util 20%
  - interval: 30s
    input_series:
      - series: 'node_mountstats_nfs_operations_received_bytes_total{instance="w1:9100", operation="READ"}'
        values: '0+90000000000x30'
      - series: 'DCGM_FI_DEV_GPU_UTIL{instance="w1:9400", gpu="0"}'
        values: '20x30'
    promql_expr_test:
      - expr: algalon:checkpoint_load_phase
        eval_time: 5m
        exp_samples:
          - labels: 'algalon:checkpoint_load_phase'
            value: 1

  # Per-op latency: GETATTR at 200ms average (>100ms) -> warning
  # requests +300/sample (10/s), response_time +60s/sample (2 s/s) => 0.2s/op
  - interval: 30s
    input_series:
      - series: 'node_mountstats_nfs_operations_requests_total{instance="w1:9100", operation="GETATTR"}'
        values: '0+300x60'
      - series: 'node_mountstats_nfs_operations_response_time_seconds_total{instance="w1:9100", operation="GETATTR"}'
        values: '0+60x60'
    alert_rule_test:
      - eval_time: 15m
        alertname: NfsOperationSlow
        exp_alerts:
          - exp_labels:
              severity: warning
              action: investigate
              instance: w1:9100
              operation: GETATTR
            exp_annotations:
              summary: 'NFS GETATTR on w1:9100 averaging over 100ms per operation'

  # Queue time dominates request time (95%) at meaningful volume -> warning
  # requests 20/s; request_time 1 s/s; queue_time 0.95 s/s
  - interval: 30s
    input_series:
      - series: 'node_mountstats_nfs_operations_requests_total{instance="w2:9100", operation="WRITE"}'
        values: '0+600x60'
      - series: 'node_mountstats_nfs_operations_request_time_seconds_total{instance="w2:9100", operation="WRITE"}'
        values: '0+30x60'
      - series: 'node_mountstats_nfs_operations_queue_time_seconds_total{instance="w2:9100", operation="WRITE"}'
        values: '0+28.5x60'
    alert_rule_test:
      - eval_time: 20m
        alertname: NfsQueueTimeDominant
        exp_alerts:
          - exp_labels:
              severity: warning
              action: investigate
              instance: w2:9100
            exp_annotations:
              summary: 'NFS RPC queue time on w2:9100 exceeds 90% of total request time: transport-side bottleneck'

  # Major timeouts -> warning
  - interval: 30s
    input_series:
      - series: 'node_mountstats_nfs_operations_major_timeouts_total{instance="w3:9100", operation="READ"}'
        values: '0 0 0+3x30'
    alert_rule_test:
      - eval_time: 8m
        alertname: NfsMajorTimeouts
        exp_alerts:
          - exp_labels:
              severity: warning
              action: investigate
              instance: w3:9100
            exp_annotations:
              summary: 'NFS major timeouts occurring on w3:9100'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make rules-test` — Expected: FAIL (rule file missing).

- [ ] **Step 3: Write `monitoring/rules/storage-nfs.yml`**

```yaml
# Checkpoint I/O and NFS/RPC health (spec §5.5, Lablup report §4.2).
# Report: checkpoint saves are cluster-wide NFS WRITE bursts (>20 GB/s);
# restart loading shows sustained READ (>2 GB/s) while GPU util is low.
# 93.1% of WRITE request latency was QUEUE time (client/transport side),
# not server response time — so queue share is the first thing to check.
# ALL metrics here require node_exporter --collector.mountstats.
groups:
  - name: storage-nfs
    interval: 30s
    rules:
      # --- Recording rules: training-phase classification (report §4.2.1) ---
      # Consumed by Phase 3 dashboards (phase bands over GPU util timelines).
      - record: algalon:nfs_write_bytes_per_second
        expr: sum(rate(node_mountstats_nfs_operations_sent_bytes_total{operation="WRITE"}[1m]))

      - record: algalon:nfs_read_bytes_per_second
        expr: sum(rate(node_mountstats_nfs_operations_received_bytes_total{operation="READ"}[1m]))

      # Save phase: cluster NFS write above 20 GB/s.
      - record: algalon:checkpoint_save_phase
        expr: algalon:nfs_write_bytes_per_second > bool 20e9

      # Load phase: cluster NFS read above 2 GB/s while mean GPU util < 50%.
      - record: algalon:checkpoint_load_phase
        expr: >-
          (algalon:nfs_read_bytes_per_second > bool 2e9)
          * on() (avg(DCGM_FI_DEV_GPU_UTIL) < bool 50)

      # --- Alerts ---
      # Report Fig 3: GETATTR normally ~10ms; spikes preceded worker death.
      # 100ms sustained for 10m = metadata path / NFS server distress.
      - alert: NfsOperationSlow
        expr: >-
          (
            sum by (instance, operation) (rate(node_mountstats_nfs_operations_response_time_seconds_total[5m]))
              / sum by (instance, operation) (rate(node_mountstats_nfs_operations_requests_total[5m]))
          ) > 0.1
        for: 10m
        labels:
          severity: warning
          action: investigate
        annotations:
          summary: 'NFS {{ $labels.operation }} on {{ $labels.instance }} averaging over 100ms per operation'

      # Report §4.2.5: queueing dominated storage latency. Volume guard
      # (>10 req/s) keeps idle mounts from firing on tiny denominators.
      - alert: NfsQueueTimeDominant
        expr: >-
          (
            sum by (instance) (rate(node_mountstats_nfs_operations_queue_time_seconds_total[5m]))
              / sum by (instance) (rate(node_mountstats_nfs_operations_request_time_seconds_total[5m]))
          ) > 0.9
          and sum by (instance) (rate(node_mountstats_nfs_operations_requests_total[5m])) > 10
        for: 15m
        labels:
          severity: warning
          action: investigate
        annotations:
          summary: 'NFS RPC queue time on {{ $labels.instance }} exceeds 90% of total request time: transport-side bottleneck'

      - alert: NfsMajorTimeouts
        expr: sum by (instance) (rate(node_mountstats_nfs_operations_major_timeouts_total[5m])) > 0
        for: 5m
        labels:
          severity: warning
          action: investigate
        annotations:
          summary: 'NFS major timeouts occurring on {{ $labels.instance }}'
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make rules-test && make rules-validate` — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add monitoring/rules/storage-nfs.yml tests/rules/storage-nfs.test.yml
git commit -m "feat: Add checkpoint I/O and NFS/RPC alert rules"
```

---

### Task 7: Scrape config + dcgm counters CSV

**Files:**
- Create: `monitoring/scrape/prometheus.yml`
- Create: `monitoring/scrape/targets/dcgm-targets.yml.example`
- Create: `monitoring/scrape/targets/node-targets.yml.example`
- Create: `monitoring/scrape/targets/all-smi-targets.yml.example`
- Create: `monitoring/exporters/dcgm-counters.csv`
- Modify: `Makefile` (add `scrape-validate`)

**Interfaces:**
- Consumes: job names used by rules — `dcgm`, `node`, `all-smi` (meta.yml and node-precursor.yml filter on `job="dcgm"` / `job="node"`; the scrape config MUST use exactly these job names).
- Produces: `make scrape-validate`; Phase 2 compose mounts `prometheus.yml` into vmagent and generates real target files from the `.example` templates. The CSV is mounted into dcgm-exporter as `/etc/dcgm-exporter/counters.csv`.

- [ ] **Step 1: Add the validation target (test first)**

Append to `Makefile`:

```make
scrape-validate: ## Validate vmagent scrape config
	@docker run --rm -v $(PWD)/monitoring/scrape:/scrape:ro \
		victoriametrics/vmagent:$(VM_VERSION) \
		-promscrape.config=/scrape/prometheus.yml -dryRun
	@echo "✅ vmagent scrape config valid"
```

- [ ] **Step 2: Run to verify it fails**

Run: `make scrape-validate`
Expected: FAIL — `/scrape/prometheus.yml` does not exist.

- [ ] **Step 3: Write `monitoring/scrape/prometheus.yml`**

```yaml
# vmagent scrape configuration (spec §3; 30s interval per Lablup Table 8).
# Job names are contract: alert rules filter on job="dcgm" / job="node".
# Target files are generated per deployment (compose: bind mount;
# helm: ConfigMap) from the .example templates in scrape/targets/.
global:
  scrape_interval: 30s
  scrape_timeout: 10s

scrape_configs:
  - job_name: dcgm
    file_sd_configs:
      - files:
          - /etc/vmagent/targets/dcgm-targets.yml

  - job_name: node
    file_sd_configs:
      - files:
          - /etc/vmagent/targets/node-targets.yml

  # Optional cross-platform exporter; targets file is empty unless the
  # all-smi profile is enabled.
  - job_name: all-smi
    file_sd_configs:
      - files:
          - /etc/vmagent/targets/all-smi-targets.yml
```

- [ ] **Step 4: Write the target templates**

`monitoring/scrape/targets/dcgm-targets.yml.example`:

```yaml
# dcgm-exporter targets (port 9400). One entry per worker node.
- targets:
    - 'worker1.example.internal:9400'
  labels:
    node: worker1
```

`monitoring/scrape/targets/node-targets.yml.example`:

```yaml
# node_exporter targets (port 9100). One entry per worker node.
- targets:
    - 'worker1.example.internal:9100'
  labels:
    node: worker1
```

`monitoring/scrape/targets/all-smi-targets.yml.example`:

```yaml
# all-smi API-mode targets (port 9090). Only for nodes running the optional
# all-smi profile (cross-platform / process-level metrics).
- targets:
    - 'worker1.example.internal:9090'
  labels:
    node: worker1
```

- [ ] **Step 5: Write `monitoring/exporters/dcgm-counters.csv`**

Every metric referenced by `monitoring/rules/*.yml` MUST appear here; this
CSV is what dcgm-exporter actually publishes.

```csv
# Format: DCGM field, Prometheus metric type, help string
# Utilization / memory
DCGM_FI_DEV_GPU_UTIL,                      gauge,   GPU utilization (in %).
DCGM_FI_DEV_MEM_COPY_UTIL,                 gauge,   Memory utilization (in %).
DCGM_FI_DEV_FB_USED,                       gauge,   Framebuffer memory used (in MiB).
DCGM_FI_DEV_FB_FREE,                       gauge,   Framebuffer memory free (in MiB).
DCGM_FI_DEV_FB_TOTAL,                      gauge,   Framebuffer memory total (in MiB).
# Clocks / power / thermal
DCGM_FI_DEV_SM_CLOCK,                      gauge,   SM clock frequency (in MHz).
DCGM_FI_DEV_MEM_CLOCK,                     gauge,   Memory clock frequency (in MHz).
DCGM_FI_DEV_GPU_TEMP,                      gauge,   GPU temperature (in C).
DCGM_FI_DEV_MEMORY_TEMP,                   gauge,   Memory (HBM) temperature (in C).
DCGM_FI_DEV_POWER_USAGE,                   gauge,   Power draw (in W).
DCGM_FI_DEV_ENFORCED_POWER_LIMIT,          gauge,   Enforced power limit (in W).
DCGM_FI_DEV_TOTAL_ENERGY_CONSUMPTION,      counter, Total energy consumption since boot (in mJ).
DCGM_FI_DEV_CLOCKS_EVENT_REASONS,          gauge,   Current reasons for clock events (throttling bitmask).
# Failure detection (spec §5.1, §5.2)
DCGM_FI_DEV_XID_ERRORS,                    gauge,   Value of the last XID error encountered.
DCGM_FI_DEV_ECC_SBE_VOL_TOTAL,             counter, Total volatile single-bit ECC errors.
DCGM_FI_DEV_ECC_DBE_VOL_TOTAL,             counter, Total volatile double-bit ECC errors.
DCGM_FI_DEV_ECC_SBE_AGG_TOTAL,             counter, Total aggregate single-bit ECC errors.
DCGM_FI_DEV_ECC_DBE_AGG_TOTAL,             counter, Total aggregate double-bit ECC errors.
DCGM_FI_DEV_UNCORRECTABLE_REMAPPED_ROWS,   gauge,   Rows remapped due to uncorrectable errors.
DCGM_FI_DEV_CORRECTABLE_REMAPPED_ROWS,     gauge,   Rows remapped due to correctable errors.
DCGM_FI_DEV_ROW_REMAP_FAILURE,             gauge,   Whether row remapping has failed.
DCGM_FI_DEV_ROW_REMAP_PENDING,             gauge,   Whether row remapping is pending.
# Interconnect
DCGM_FI_DEV_PCIE_REPLAY_COUNTER,           counter, Total PCIe retries.
DCGM_FI_PROF_NVLINK_TX_BYTES,              counter, NVLink transmitted bytes.
DCGM_FI_PROF_NVLINK_RX_BYTES,              counter, NVLink received bytes.
```

- [ ] **Step 6: Run validation**

Run: `make scrape-validate`
Expected: PASS (vmagent tolerates missing file_sd target files at runtime; `-dryRun` validates config structure).
Contingency: if vmagent `-dryRun` demands `-remoteWrite.url`, append `-remoteWrite.url=http://localhost:8428/api/v1/write` to the docker command in the Makefile target.

- [ ] **Step 7: Commit**

```bash
git add monitoring/scrape/ monitoring/exporters/dcgm-counters.csv Makefile
git commit -m "feat: Add vmagent scrape config and dcgm-exporter counters CSV"
```

---

### Task 8: CI workflow for monitoring tests

**Files:**
- Create: `.github/workflows/monitoring-test.yml`

**Interfaces:**
- Consumes: `make rules-validate`, `make rules-test`, `make scrape-validate` (Tasks 1, 7).

- [ ] **Step 1: Write the workflow**

Create `.github/workflows/monitoring-test.yml`:

```yaml
name: Monitoring Tests

on:
  push:
    branches: [main]
    paths:
      - 'monitoring/**'
      - 'tests/rules/**'
      - 'Makefile'
      - '.github/workflows/monitoring-test.yml'
  pull_request:
    paths:
      - 'monitoring/**'
      - 'tests/rules/**'
      - 'Makefile'
      - '.github/workflows/monitoring-test.yml'

jobs:
  monitoring:
    name: Validate rules and scrape config
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Validate vmalert rules
        run: make rules-validate

      - name: Run rule unit tests
        run: make rules-test

      - name: Validate vmagent scrape config
        run: make scrape-validate
```

- [ ] **Step 2: Verify locally**

Run: `make rules-validate && make rules-test && make scrape-validate`
Expected: all PASS (same commands CI runs).

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/monitoring-test.yml
git commit -m "ci: Add monitoring rules validation workflow"
```

---

## Self-Review Notes

- Spec coverage: §5.1→Task 2, §5.2→Task 3, §5.3→Task 4, §5.4→Task 5, §5.5→Task 6, §5.6→Task 1, scrape/exporter config (§3, §4)→Task 7, CI (§7 rules row)→Task 8. Alertmanager config, compose, helm, terraform, dashboards are later phases by design.
- Type consistency: job names (`dcgm`, `node`, `all-smi`) match between rules (Tasks 1, 5) and scrape config (Task 7); every DCGM metric used in rules appears in the Task 7 CSV; severity/action label vocabulary fixed in Global Constraints.
- Known judgment calls encoded: `delta()` for gauge counters (GPU-replacement resets must not fire), `>= 8` bitmask floor for throttle reasons, `and on()` guards for peer-relative rules, `.example` suffix for target templates so real target files stay deployment-generated.
