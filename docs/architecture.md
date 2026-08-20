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
| Grafana | Ten auto-provisioned dashboards |

VictoriaLogs is the one component nothing scrapes: it is written to, by
`monitoring/slurm/epilog-logpush.sh` running as `EpilogSlurmctld` on the
Slurm controller. It is off in both deployment paths until you ask for it
(compose profile `logs`, or `victorialogs.enabled` in the chart) — see
[Job logs](slurm.md#job-logs-optional).

Three optional Slurm-side pieces hang off the controller and the compute
nodes, each a separate opt-in and none of them deployed by Algalon: the
two exporters (`prometheus-slurm-exporter`, `slurm-job-exporter`), the
epilog log push above, and `monitoring/slurm/sacct-textfile.sh` — a cron
or timer job that turns Slurm accounting into a node_exporter textfile
for the Scheduler Analytics dashboard. See
[Slurm integration](slurm.md).

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

Ten Grafana dashboards in `monitoring/dashboards/`, auto-provisioned
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
- **Scheduler Analytics** — a 7-day policy view over Slurm accounting:
  queue-wait and runtime quantiles per partition, walltime accuracy,
  job outcomes and GPU-hours per account. Populated by the optional
  [sacct textfile collector](slurm.md#scheduler-analytics-optional).
  Nothing on it pages: there is deliberately no job success-ratio SLO,
  because most job failures are user error and burn-rate alerting on
  them would page operators for mistakes they cannot fix.
- **GPU Utilization Quality** — is the fleet's GPU time doing any work?
  See [GPU utilization quality](#gpu-utilization-quality) below.

## GPU utilization quality

`DCGM_FI_DEV_GPU_UTIL` is the number everyone reaches for and the
weakest signal on this page. It reports only that *a kernel was resident
on the device* during the sample. A job whose dataloader cannot keep up,
or one blocked in an NCCL all-reduce, keeps a kernel resident and reads
near 100% while computing nothing. Buying more GPUs on the strength of
that number buys more GPUs to wait with.

So Algalon treats utilization as four layers, each answering a narrower
question than the one above it. The gap between any two adjacent layers
is waste:

<!-- markdownlint-disable MD013 -->
| Layer | Question it answers | Metric(s) | Covered by |
| --- | --- | --- | --- |
| 1. Allocated | Is a job holding this GPU at all? | `slurm_job_utilization_gpu` (per-job cgroup) | `SlurmJobGpuIdle`; Slurm Job Explorer |
| 2. Busy | Is a kernel resident on the device? | `DCGM_FI_DEV_GPU_UTIL` | GPU Fleet Overview — **weak on its own**: resident is not the same as running, and a starved or blocked kernel still scores 100% |
| 3. Actually computing | Are warps executing? | `DCGM_FI_PROF_SM_ACTIVE`, `DCGM_FI_PROF_SM_OCCUPANCY` | GPU Utilization Quality; `GpuBusyButHollow` |
| 4. Computing efficiently | Is it using the units it was bought for? | `DCGM_FI_PROF_PIPE_TENSOR_ACTIVE`, `DCGM_FI_PROF_DRAM_ACTIVE`, `DCGM_FI_DEV_POWER_USAGE / DCGM_FI_DEV_ENFORCED_POWER_LIMIT` | GPU Utilization Quality |
<!-- markdownlint-enable MD013 -->

Power against the enforced limit deserves its own mention: it is a layer-4
signal that needs no profiling fields at all, because both metrics are in
the base counter set. Real training work sits around 0.7–1.0 of TDP; a
GPU held at idle clocks inside an allocation sits at 0.1–0.3. On a fleet
that cannot enable DCP, that ratio is the whole quality story.

### The four waste patterns

Each one is a *pair* of layers disagreeing, which is why no single metric
finds them:

- **Allocated-idle** — a job holds the GPU and no kernel is resident.
  Layers 1 high, 2 low. Surfaced by `SlurmJobGpuIdle`, the alert the
  per-node job exporter exists for.
- **Busy-but-hollow** — a kernel is resident but almost no warps
  execute. Layers 2 high, 3 low. The signature of an input pipeline,
  CPU-bound preprocessing or a collective wait. Surfaced by
  `GpuBusyButHollow` and by the claimed-vs-actual panel on GPU
  Utilization Quality.
- **Memory-holding** — the framebuffer is occupied while neither the SMs
  nor the memory interface are doing anything. `DCGM_FI_DEV_FB_USED`
  high with layers 3 and 4 near zero. Visible on the DRAM-active versus
  SM-active panel.
- **Throttled** — warps want to run and the hardware will not let them.
  `DCGM_FI_DEV_CLOCKS_EVENT_REASONS >= 8`, showing up as a tensor and SM
  activity dip with no code change behind it. Surfaced by
  `GpuClocksThrottled`; check it before blaming a model.

### Reading your own job

These are not operator-only numbers. A researcher opens **Slurm Job
Explorer**, picks their `job_id`, and reads the same layers for their own
run: per-GPU utilization from the cgroup, then *SM active on your job's
nodes* and *Power / TDP on your job's nodes* directly beneath it. High
utilization over low SM activity means the input pipeline, not the GPU,
is the bottleneck — and no amount of extra hardware will fix that.

Operators see the same truth fleet-wide on **GPU Utilization Quality**.
One vocabulary, two audiences: when an operator says a job is running
hollow and the owner opens their own dashboard, both are looking at layer
3 disagreeing with layer 2.

### Enabling the profiling fields

Layers 3 and 4 come from DCGM's DCP fields, added to
`monitoring/exporters/dcgm-counters.csv`. Three caveats:

- **Volta or newer.** Older parts do not expose them; the series are
  simply absent, and every rule and panel that reads them stays empty
  rather than wrong.
- **They conflict with a concurrent profiler.** An Nsight or `nvprof`
  session on the same GPU takes exclusive ownership of the profiling
  hardware, so DCP sampling stops for its duration.
- **A small sampling overhead**, which is the price of the only honest
  answer to "is this GPU working".

The counter set already carried `DCGM_FI_PROF_NVLINK_*`, so the
exporter's DCP path is proven on any fleet running this CSV — these are
new fields, not a new mechanism.

### Why this lives in the scheduler-analytics phase

Utilization quality is the **outcome measure** of QoS policy. Scheduler
Analytics says what the policy handed out — GPU-hours per account, waits
per partition, walltime accuracy. This says how much of it turned into
computation. A policy review that looks only at the first half optimises
for handing out hours; looking at both asks whether the hours did
anything. That is why the *Effective fleet utilization (7d)* tile sits on
Scheduler Analytics next to GPU-hours by account.

Per-account effective hours are deliberately **not** computed. That would
need per-job GPU attribution, which is only trustworthy on exclusive
nodes (see [the `on(node)` join
limits](slurm.md#the-onnode-join-contract)). Algalon does not publish a
number it cannot stand behind.
