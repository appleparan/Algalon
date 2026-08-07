# Algalon Alert Center Redesign

- **Date**: 2026-08-07
- **Status**: Approved (design), pending implementation
- **Basis**: Lablup Technical Report 2026, *"이상 탐지에서 자동 복구까지: 504-GPU LLM 학습의 운영 분석 보고"*
  (<https://huggingface.co/datasets/lablup/from-detection-to-recovery>)

## 1. Goal

Turn Algalon from a metrics-collection + dashboard stack into a **comprehensive
alert center** for GPU cluster operations. Encode the operational knowledge from
the Lablup report (XID classification, multi-layer precursor signals, checkpoint
I/O bottleneck patterns) as versioned vmalert rules, evaluated against
VictoriaMetrics and routed through Alertmanager.

Key motivation from the report (Table 7): DCGM alone records XID errors only
*after* the GPU has already stopped. Multi-layer monitoring (scheduler + OS +
GPU) surfaces failures earlier via system-level metrics — interrupts, runnable
processes, NFS latency — collected by node_exporter.

## 2. Decisions

| Topic | Decision |
|---|---|
| Alert evaluation/routing | **vmalert + Alertmanager** (VictoriaMetrics-native; rules as YAML, code-reviewable) |
| Worker exporters | **dcgm-exporter + node_exporter by default; all-smi as opt-in profile** |
| Notification channel | **Slack webhook** default, severity-split channels; secrets via env/secret injection |
| Kubernetes | **Own Helm chart** (`deploy/helm/algalon`): worker DaemonSets + host Deployments |
| Repo structure | **Full restructure**: single source of truth in `monitoring/`, consumed by compose/helm/terraform |
| AGENTS.md | Lightweight rewrite per Claude 5 context-engineering rules; Fable-as-orchestrator → Opus 5 subagents |

## 3. Architecture

```
[Worker node (compose service / k8s DaemonSet)]      [Host (compose / k8s Deployments)]
 dcgm-exporter  ── GPU, XID, ECC, remap ──┐
 node_exporter  ── OS, NFS, interrupts ───┼──→ VMAgent ──→ VictoriaMetrics
 all-smi (opt)  ── cross-platform GPU ────┘                    │
                                                    vmalert ── monitoring/rules/*.yml
                                                        │ fire
                                                    Alertmanager ──→ Slack (critical/warning)
                                                        │
                                                    Grafana (dashboards + alert overview)
```

### Component versions (resolved 2026-08-07)

| Component | Version | Role |
|---|---|---|
| dcgm-exporter | `4.6.0-4.8.3` | Failure detection backbone: XID, ECC, remapped rows, thermal/power/throttle |
| node_exporter | `v1.12.1` | Precursor layer: `node_intr_total`, `node_procs_running`, `node_vmstat_pgpgout`, NFS `mountstats` |
| all-smi | `v0.25.0` | Optional: cross-platform (NVIDIA/Apple/NPU) + process-level metrics |
| VictoriaMetrics / vmagent / vmalert | `v1.149.0` | TSDB, scraping, rule evaluation |
| Alertmanager | `v0.33.1` | Routing, grouping, inhibition, silences |
| Grafana | `v13.1.3` | Dashboards + alert status view |

**node_exporter must run with `--collector.mountstats`** (NFS operation
latency metrics are off by default). Report §4.2.5 relies on
`node_mountstats_nfs_operations_*` (queue vs response time).

## 4. Repository layout (target)

```
Algalon/
├─ AGENTS.md                  # lightweight; orchestration policy + gotchas
├─ README.md
├─ monitoring/                # SINGLE SOURCE OF TRUTH
│  ├─ rules/                  # vmalert rule groups (see §5)
│  ├─ dashboards/             # Grafana JSON
│  ├─ exporters/              # dcgm-exporter counters CSV, node_exporter flags
│  └─ scrape/                 # vmagent scrape configs / target templates
├─ deploy/
│  ├─ compose/
│  │  ├─ host/                # VM + vmagent + vmalert + alertmanager + grafana
│  │  └─ worker/              # dcgm-exporter + node_exporter (+ all-smi profile)
│  ├─ helm/algalon/           # single chart; rules/dashboards packaged from monitoring/
│  └─ terraform/              # migrated GCP modules, startup scripts use new compose
├─ docs/
│  └─ superpowers/specs/      # this document
└─ tests/                     # rule validation, compose/helm/terraform checks
```

Compose mounts `monitoring/` as volumes; Helm packages the same files into
ConfigMaps at chart build; Terraform startup scripts deploy the compose stack.
No copies of rules/dashboards may live inside `deploy/`.

## 5. Alert rule taxonomy (`monitoring/rules/`)

Grounded in the report; each rule carries `severity`, `action` (what the
operator/automation should do), and a `runbook` annotation.

### 5.1 `gpu-xid.yml` — XID classification (report Table 3)

| XID | Class | Severity | Action annotation |
|---|---|---|---|
| 31, 43, 94 | `RESTART_APP` | warning | Restart the job session; node exclusion not required |
| 119, 145, 149 | `RESET_GPU` | critical | GPU reset required (GSP RPC timeout / NVLink RLW / NETIR) |
| 79 | `RESTART_BM` | critical | GPU fell off the bus — reboot node, contact support |

Source metric: dcgm-exporter XID error counters (`DCGM_FI_DEV_XID_ERRORS`).

### 5.2 `gpu-ecc.yml` — memory degradation (report §4.1.2, Fig 4)

- Uncorrectable remapped rows **increase** → critical (memory permanently damaged).
- `DCGM_FI_DEV_ROW_REMAP_FAILURE` → critical (GPU must be replaced; NVIDIA
  threshold: 8 uncorrectable remaps per bank).
- Correctable remapped rows **growth trend** over 24h → warning
  (report gpu124 case: 254 rows accumulated with zero XID errors before the
  GPU disappeared from the host — trend matters more than absolute value).
- Volatile DBE (double-bit error) counter increase → critical.

### 5.3 `gpu-health.yml` — thermal/power/throttle (report Table 8)

GPU temperature, HBM temperature, power draw sustained near limit, clock
throttle reasons (HW slowdown / thermal). Severity: warning → critical tiers.

### 5.4 `node-precursor.yml` — pre-XID anomaly signals (report Fig 2–3)

Report finding F1: no single dominant precursor exists; these rules are
*supporting signals*, tuned conservatively (warning only):

- `rate(node_intr_total)` collapse vs own baseline (report: ~300K → 70K–100K
  after NVLink/Bus Fault).
- `node_procs_running` collapse to ~0 while the node is expected active.
- `node_vmstat_pgpgout` spike (page-out burst around worker death).

Peer-relative evaluation (node vs cluster median) is expressed with
aggregation-over-`job` queries so rules work at any cluster size.

### 5.5 `storage-nfs.yml` — checkpoint I/O and NFS/RPC (report §4.2)

- NFS per-op response time (GETATTR and friends):
  `rate(node_mountstats_nfs_operations_response_time_seconds_total[5m]) /
  rate(...requests_total[5m])` above threshold → warning.
- RPC **queue-time share**: queue time / total request time sustained high
  (report: 93.1% of WRITE latency was queueing) → warning.
- Recording rules for training-phase classification (report §4.2.1):
  - `algalon:nfs_write_gbps` — cluster NFS write; `> 20 GB/s` ⇒ *Save* phase
  - `algalon:nfs_read_gbps` — cluster NFS read; `> 2 GB/s` with low GPU util ⇒ *Load* phase
  These feed dashboards (phase bands) rather than paging anyone.

### 5.6 `meta.yml` — monitoring-of-monitoring (report Table 15)

- `up == 0` per scrape job (exporter down) → critical after grace period.
- `absent()` guards for key metric families (DCGM stopped publishing ≠ node down).
- `Watchdog` always-firing rule (dead man's switch for the alert pipeline).

### Alertmanager policy

- Route by `severity`: critical / warning → separate Slack channels.
- Group by `alertname, node`; inhibition: node-level critical suppresses
  same-node warnings; `Watchdog` routed to a null receiver.
- Slack webhook URL injected via env (`SLACK_WEBHOOK_URL`) — never committed.

## 6. Deployment targets

### 6.1 Docker Compose

- `deploy/compose/worker`: dcgm-exporter (NVIDIA runtime) + node_exporter
  (host PID/rootfs mounts, `--collector.mountstats`); `--profile all-smi`
  enables the all-smi container (`ghcr.io/inureyes/all-smi:v0.25.0`).
- `deploy/compose/host`: VictoriaMetrics, vmagent, vmalert, Alertmanager,
  Grafana; `monitoring/` bind-mounted read-only.

### 6.2 Helm (`deploy/helm/algalon`)

- Worker DaemonSets: dcgm-exporter + node-exporter; GPU nodes targeted via
  `nvidia.com/gpu` nodeSelector/tolerations (works alongside gpu-operator);
  all-smi DaemonSet behind `allSmi.enabled` value.
- Host: Deployments/StatefulSet (VictoriaMetrics with PVC), ConfigMaps
  generated from `monitoring/` (chart packaging includes the files; helper
  script syncs them pre-package).
- Values control: retention, scrape interval (default 30s per report Table 8),
  Slack secret ref, severity routing.

### 6.3 Terraform (GCP)

Existing `terraform/modules/{algalon-host,algalon-worker,network}` migrate to
`deploy/terraform/` with startup scripts updated for the new compose stack.
Module interfaces (variables/outputs) preserved where possible.

## 7. Testing & quality gate

| Layer | Check | Where |
|---|---|---|
| Rules | `vmalert -dryRun -rule=...` + promtool syntax check; unit tests for rule expressions | CI + `tests/unit` |
| Compose | `docker compose config` on host/worker (+ all-smi profile) | CI + `tests/integration` |
| Helm | `helm lint`, `helm template \| kubeconform` | CI |
| Terraform | `terraform fmt -check`, `terraform validate` | existing CI, path updated |
| Docs | markdownlint (existing hook) | local |

## 8. Phased execution plan

| Phase | Deliverable | Notes |
|---|---|---|
| 0 | This spec + **AGENTS.md rewrite** | current branch `feat/alert-center-redesign` |
| 1 | `monitoring/` single source: 6 rule groups + exporter configs + rule tests | rules are the product core |
| 2 | `deploy/compose/{worker,host}` | worker first, then host; parity with §6.1 |
| 3 | Dashboards: DCGM-based GPU overview, node/system, checkpoint-I/O phases, alert-center view; all-smi dashboard kept behind profile | migrate metric names from `all_smi_*` to `DCGM_FI_*`/`node_*` |
| 4 | Helm chart | lint + kubeconform gated |
| 5 | Terraform migration, old layout removal (`algalon_host/`, `algalon_worker/`, root *.md consolidation), README/docs/CI refresh | rollback docs updated |

Each phase: own worktree branch, staged commits, quality gate before PR.
Implementation subtasks are dispatched by the Fable orchestrator to Opus 5
subagents per AGENTS.md policy.

## 9. Out of scope (YAGNI)

- Automatic remediation (node reboot / GPU reset execution) — alert annotations
  describe the action; execution stays with operators or external automation.
- ML-based precursor detection (report lists it as ongoing work; no stable
  recipe to encode).
- Backend.AI/scheduler-layer metrics (report Table 8 row 4) — Algalon targets
  generic Prometheus stacks without a Backend.AI dependency.
- Non-GCP terraform providers.
