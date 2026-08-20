# Architecture

**English** | [한국어](ko/architecture.md)

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="images/architecture-dark.svg">
  <img alt="Algalon architecture" src="images/architecture.svg">
</picture>

Every GPU node runs a small set of exporters; a central host runs the
storage, evaluation and alerting pipeline. Workers never push — the
central vmagent scrapes them every 30 seconds, so a worker's only job is
to keep its exporters listening.

## Components

| Component | Role |
| --- | --- |
| dcgm-exporter | GPU telemetry: XID errors, ECC and row-remap counters, temperature, power, throttling |
| node-exporter | OS telemetry: interrupts, runnable processes, page-outs, NFS `mountstats` |
| all-smi *(optional)* | Cross-platform accelerator and process-level view |
| vmagent | Scrapes the exporters and remote-writes into VictoriaMetrics |
| VictoriaMetrics | Time series storage |
| VictoriaLogs *(optional)* | Job stdout, pushed at job end by the epilog |
| vmalert | Evaluates the rule groups every 30 s; writes recording rules back |
| Alertmanager | Routes, groups and inhibits alerts; delivers to Slack |
| Grafana | Eight auto-provisioned dashboards |

VictoriaLogs is the one component nothing scrapes: it is written to, by
`monitoring/slurm/epilog-logpush.sh` running as `EpilogSlurmctld` on the
Slurm controller. It is off in both deployment paths until you ask for it
(compose profile `logs`, or `victorialogs.enabled` in the chart) — see
[Job logs](slurm.md#job-logs-optional).

`monitoring/` is the single source of truth for the rules, dashboards,
scrape config, Alertmanager policy and the DCGM counter set. Docker
Compose bind-mounts that directory and Helm packages it into ConfigMaps —
nothing is ever copied into `deploy/`.

## The seven core rule groups

Each group in `monitoring/rules/` encodes a finding from the Lablup
report, and each rule carries an inline citation to the section, table or
figure it implements.

### `gpu-xid` — XID classification

The report's Table 3 maps NVIDIA XID error codes to the recovery action
they actually require, and Algalon's severity levels follow that mapping
directly: XIDs 31/43/94 mean the application must restart (warning),
119/145/149 mean the GPU needs a reset (critical), and 79 — GPU fell off
the bus — means the node must be rebooted (critical). Unclassified
nonzero XIDs get their own catch-all alert.

### `gpu-ecc` — memory degradation

Row-remap counters are a GPU's permanent damage ledger. Beyond the
obvious alerts (uncorrectable remaps, `ROW_REMAP_FAILURE`, pending
remaps, double-bit ECC), this group watches the *growth trend* of
correctable remaps over 24 hours — because in the report's gpu124 case, a
GPU accumulated 254 correctable remaps over 55 days with zero XID errors
before disappearing from the host entirely.

### `gpu-health` — thermal and throttling

Temperature bands for the GPU die and HBM, plus sustained hardware
throttling (report Table 8). The throttle rule masks out benign reasons
(idle, application clocks, software power cap) and fires only on the
bits that indicate real performance loss — the "fail-slow" class the
report calls harder to catch than outright failures.

### `node-precursor` — early warning signals

XID errors are post-mortem: by the time one is logged, the GPU has
already stopped. The report (§4.1.2, Figs 2–3) shows OS-level metrics
moving *before* failures surface, so this group compares each node
against the cluster median: interrupt-rate collapse, runnable-process
collapse and page-out bursts. All three are warning-only and gated on at
least three live nodes — the report's finding F1 is precisely that no
single dominant precursor exists, so these are supporting signals, not
pages.

### `storage-nfs` — checkpoint I/O

Recording rules classify the training loop into save/load phases from
NFS throughput (a save is a cluster-wide write burst above 20 GB/s; a
load is sustained reads with low GPU utilization). The alerts target
NFS/RPC queueing, because the report's §4.2.5 found that 93.1 % of WRITE
latency was client-side queue time, not server response time. This whole
group requires node-exporter's `--collector.mountstats`.

### `slo` — service level indicators

The other groups answer *what broke*. This one answers *is the cluster
serving its users* — the symptom layer at the top of Google's SRE
golden-signals hierarchy, and the only group with no alerts in it. Four
recording rules publish instantaneous 0–1 ratios as `algalon:sli:*`:
exporter availability (`avg(up)`, the SLI for Algalon itself), Slurm node
availability (DOWN and DRAIN both count as unusable), GPU health (below
92 °C *and* not hardware-throttled) and NFS latency (active
`(instance, operation)` paths inside the 100 ms/op budget; an idle
filesystem counts as served). A fifth rule records newly failed jobs in
the trailing hour — a count, not a ratio, because the queue exporter
publishes gauges only; the exact success ratio waits on the sacct
collector.

The thresholds are reused verbatim from the alert groups — 92 °C is
`GpuTempCritical`, bitmask ≥ 8 is `GpuClocksThrottled`, 100 ms/op is
`NfsOperationSlow` — so the SLIs and the pages never disagree about what
"unhealthy" means. SLO targets, 30-day windows and error budgets live in
the dashboard instead of here: they are per-fleet decisions, and a window
baked into a recording rule cannot be re-asked at query time. The
Slurm-derived SLIs produce no series at all when the optional Slurm
exporters are absent, so the dashboard shows them as unmeasured rather
than as a defaulted 0 or 1.

### `meta` — monitoring the monitoring

Exporter-down alerts, a "DCGM silent while the target is up" guard, and
the `Watchdog` dead-man's switch: an always-firing alert routed to a null
receiver, whose *absence* at the receiver proves the alerting pipeline
itself is broken.

Rule unit tests for all seven groups live in `tests/rules/` and run
without any GPU hardware.

With Slurm integration enabled, an optional eighth group (`slurm`) adds
queue and job-accounting alerts — see [Slurm integration](slurm.md).

## Alerting policy

Alertmanager routes `severity="critical"` and `severity="warning"` to
separate Slack webhooks, groups alerts by `alertname` and `node`, and
inhibits warnings on a node that is already paging critical. Webhook
URLs are always injected as secret files — none are stored in git, and
the deployment fails loudly rather than shipping a silently broken
notifier.

## Dashboards

Eight Grafana dashboards in `monitoring/dashboards/`, auto-provisioned
into the **Algalon** folder:

- **SLO Overview** — the symptom-first entry point: 30-day compliance
  for each SLI against its SLO target, the error budget left to spend,
  what is firing right now, and the node-availability burn rate.
- **Alert Center** — what is firing right now, by severity and node,
  plus the Watchdog pipeline check and an exporter up/down matrix.
- **GPU Fleet Overview** — per-GPU utilization stripes over time (pale
  stripes reveal stragglers), fleet stat tiles, per-node temperature and
  memory.
- **Node Health (Precursors)** — each precursor metric drawn as a
  P5–P95 peer band with the selected node overlaid, reproducing the
  report's Figs 2–3.
- **Checkpoint & Storage I/O** — save/load phase bands from the
  `algalon:checkpoint_*` recording rules above throughput and queue-time
  panels, reproducing the report's Fig 5.
- **all-smi (Optional)** — cross-platform hardware view; populated only
  when the all-smi profile is enabled.
- **Slurm Queue / Slurm Job Explorer** — queue state and per-job
  accounting views; populated only with
  [Slurm integration](slurm.md).
