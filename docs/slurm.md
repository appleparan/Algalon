# Slurm integration

**English** | [한국어](ko/slurm.md)

Algalon can read the Slurm scheduler's view of the cluster alongside its
hardware view: which jobs are queued, which nodes the scheduler has
given up on, and — per job — who owns it and whether the GPUs it holds
are doing any work. The integration is entirely opt-in: it adds two
scrape jobs, and with no targets registered it produces no series, no
alerts and three empty dashboards.

Nothing here is deployed by Algalon, except the optional in-cluster
[jobExporter DaemonSet](#in-cluster-jobexporter-daemonset). Both exporters
need Slurm CLI or cgroup access on the host, so by default they run as
ordinary host services on your Slurm machines and Algalon only scrapes
them.

## Two exporters, two jobs

Slurm answers two different questions, and no single exporter answers
both well:

| Exporter | Runs on | Port | Scrape job | Answers |
| --- | --- | --- | --- | --- |
| [prometheus-slurm-exporter](https://github.com/rivosinc/prometheus-slurm-exporter) | slurmctld or a login node, one per cluster | 9092 | `slurm` | Is the *scheduler* healthy? Queue depth, job states, node states, partitions |
| [slurm-job-exporter](https://github.com/guilbaults/slurm-job-exporter) | every compute node | 9798 | `slurm-job` | Is the *allocated hardware* being used? Per-job cgroup CPU/memory and per-GPU utilization, memory and power |

The queue exporter is cluster-wide, so its series carry no `node` label.
The job exporter is per-node, so its targets **must** carry one — that
label is the whole reason both exporters are here (see
[The `on(node)` join contract](#the-onnode-join-contract)).

## Installing the exporters

### Queue exporter

Run [prometheus-slurm-exporter](https://github.com/rivosinc/prometheus-slurm-exporter)
on the slurmctld host or a login node — anywhere `sinfo` and `squeue`
work, since in its recommended mode (`-slurm.cli-fallback`) it shells out
to the Slurm CLI rather than to slurmrestd. One instance per cluster is
enough; a second one would only duplicate the same cluster-wide series.
Listen on `:9092` and make that port reachable from the host that runs
vmagent.

### Job exporter

Run [slurm-job-exporter](https://github.com/guilbaults/slurm-job-exporter)
on **every** compute node, listening on `:9798`. It reads Slurm's cgroup
hierarchy directly, which means two prerequisites:

- `JobAcctGatherType=jobacct_gather/cgroup` in `slurm.conf` — without
  cgroup accounting there are no per-job cgroups to read, and the
  exporter reports nothing at all.
- A GPU data source for the per-device metrics: DCGM (the default,
  `--monitor dcgm`, and the upstream recommendation) or NVML through the
  optional `nvidia-ml-py` module (`--monitor nvml`). Either way the
  exporter runs `nvidia-smi -L` inside each cgroup to learn which GPUs
  the job was given. Without one of the two, CPU and memory metrics still
  work, but `slurm_job_utilization_gpu`, `slurm_job_memory_usage_gpu` and
  `slurm_job_power_gpu` are absent — and `SlurmJobGpuIdle`, the alert this
  exporter exists for, never fires.

Note that this DCGM instance is the exporter's own data source and is
independent of Algalon's `dcgm-exporter`; the two coexist on a node.

## Registering targets

### Docker Compose

Copy the two templates into the host stack's target directory
(the file names are fixed — vmagent watches exactly these):

```bash
cd deploy/compose/host/targets
cp ../../../../monitoring/scrape/targets/slurm-targets.yml.example \
   slurm-targets.yml
cp ../../../../monitoring/scrape/targets/slurm-job-targets.yml.example \
   slurm-job-targets.yml
```

`slurm-targets.yml` holds the single queue exporter and needs no labels.
`slurm-job-targets.yml` holds one entry per compute node, and every
entry **must** carry a `node` label whose value matches the one used for
the same machine in `dcgm-targets.yml` and `node-targets.yml`:

```yaml
- targets:
    - 'gpu01.example.internal:9798'
  labels:
    node: gpu01
```

If you are not using Slurm, leave both files as an empty list (`[]`) or
do not create them at all. See
[`deploy/compose/host/targets/README.md`](../deploy/compose/host/targets/README.md)
for the full target-file reference.

### Helm and k3s

When the exporters live outside the cluster, `kubernetes_sd` cannot find
them; they are enumerated statically in values instead. (Compute nodes
that *are* cluster members get the DaemonSet path in the
[next section](#in-cluster-jobexporter-daemonset) — no static list.)
Everything below is gated on `slurm.enabled`, which defaults to `false`:

```yaml
slurm:
  enabled: true
  queueTargets:
    - "slurmctld.example.internal:9092"
  jobTargets:
    - {address: "gpu01.example.internal:9798", node: "gpu01"}
    - {address: "gpu02.example.internal:9798", node: "gpu02"}
```

Each `jobTargets` entry renders into a `static_configs` block carrying
its `node` label. In the Helm path the exporter pods get their `node`
label from `__meta_kubernetes_pod_node_name`, so the value you write
here must be the **Kubernetes node name**, not an arbitrary hostname —
otherwise the join silently matches nothing. Chart reference:
[`deploy/helm/algalon/`](../deploy/helm/algalon/README.md).

### In-cluster jobExporter (DaemonSet)

`jobTargets` above assumes the compute nodes live outside the cluster.
When they are cluster members instead, run slurm-job-exporter as a
DaemonSet with `slurm.jobExporter.enabled: true` rather than
enumerating them statically. Enable either `jobTargets` or
`jobExporter` for a given node set, not both — running both scrapes
the same jobs twice.

The DaemonSet still needs a DCGM engine to read per-GPU metrics, and it
needs that engine on the host rather than embedded in its own pod: each
node must already run a host-side `nv-hostengine` listening on `:5555`,
with the exporter attaching to it as a remote client over
`hostNetwork`. If the node's `dcgm-exporter` DaemonSet also runs there,
point it at the same engine with `dcgmExporter.extraArgs: ["-r",
"localhost:5555"]` and `dcgmExporter.hostNetwork: true` — two DCGM
engines on one node cannot both watch the `DCGM_FI_PROF_*` fields, so
`dcgm-exporter` and `slurm-job-exporter` must share the single
host-side engine.

#### Prerequisites on every selected node

Beyond the host-side `nv-hostengine` above, the DaemonSet path has two
prerequisites that the static host-service path does not:

- **nvidia-container-toolkit, and the `nvidia` RuntimeClass if your
  cluster gates the runtime behind one.** Per-job GPU attribution is not
  something the exporter can do from DCGM alone: DCGM says *this GPU is
  busy*, and the mapping from GPU to job comes from running
  `nvidia-smi -L` inside the job's own cgroup. `nvidia-smi` is injected
  into the container by the nvidia container runtime — it is deliberately
  not baked into the image, because the binary must match the host driver.
  So the pod declares `NVIDIA_VISIBLE_DEVICES=all` and
  `NVIDIA_DRIVER_CAPABILITIES=utility`, and where the runtime is not the
  node default you must also set
  `slurm.jobExporter.runtimeClassName: nvidia`. Without the toolkit the
  pod still starts and still reports cgroup CPU and memory, but every
  `slurm_job_*_gpu` series is missing — and `SlurmJobGpuIdle`, the alert
  this exporter exists for, never fires.
- **Slurm users resolvable from `/etc/passwd`.** The exporter turns a uid
  into the `user` label by shelling out to `id --name --user <uid>`, and
  the pod gets only a read-only bind mount of the host's `/etc/passwd`. At
  a site that resolves Slurm users through LDAP or SSSD rather than local
  accounts, that lookup raises and the *whole* collection fails — not just
  the `user` label, the entire scrape. Either make the users visible to
  the container (e.g. additionally mount the host's `/var/lib/sss` so the
  NSS path works inside the pod) or keep the exporter on the host as a
  systemd service via `jobTargets`, where it uses the node's own NSS
  stack. Algalon does not patch upstream to soften this.

Cgroup v2 note: the collector creates a short-lived `gpu_probe` child
cgroup under each job to run that probe, so the `/sys/fs/cgroup` mount is
deliberately **writable**. Mounting it read-only makes every collection
with a running GPU job fail.

```yaml
slurm:
  jobExporter:
    enabled: true
    image: ghcr.io/appleparan/slurm-job-exporter:0.4.12
    port: 9798
    dcgmUpdateInterval: 10
    # "nvidia" where the runtime is behind a RuntimeClass; leave empty
    # only if the nvidia runtime is already the node default.
    runtimeClassName: nvidia
    nodeSelector: {}
    tolerations: []
    resources:
      requests: {cpu: 100m, memory: 128Mi}
```

The port is a **host** port (`hostNetwork` plus an explicit `hostPort`),
so anything else already bound to `:9798` on the node — most likely a
leftover host-service copy of this same exporter — surfaces as a pod that
will not schedule.

`jobExporter` renders on `slurm.jobExporter.enabled: true` alone; it
does not require `slurm.enabled: true`, which only gates the static
`queueTargets`/`jobTargets` scrape jobs described above. The pods carry
`algalon.io/scrape: "true"` and `algalon.io/job: slurm-job`, so the
`algalon-pods` kubernetes_sd job picks them up the same way it picks up
`dcgm-exporter` and `node-exporter` pods — no scrape-config change is
needed. `job` comes from the `algalon.io/job` pod label and `node` from
`__meta_kubernetes_pod_node_name`, exactly the relabelling `jobTargets`
gets by hand for its static entries, so the resulting series carry the
same `job="slurm-job"` and `node` labels either way.

Labels being identical is what makes the rules and dashboards portable
across the two paths, but it is a statement about *labels*, not about
coverage: every rule, dashboard and join above applies unchanged **to the
metrics the pod actually produces**. Meet the two prerequisites above and
that is all of them; miss the nvidia runtime and the GPU-derived half —
the Job Explorer's per-GPU panels and `SlurmJobGpuIdle` — stays empty
while the CPU and memory half looks perfectly healthy.

## What you get

### Alerts

One new rule group, [`monitoring/rules/slurm.yml`](../monitoring/rules/slurm.yml),
evaluated every 30 s like the rest. Rules 1–4 come from the queue
exporter, rule 5 from the job exporter:

<!-- markdownlint-disable MD013 -->
| Alert | Severity | Fires when | Why |
| --- | --- | --- | --- |
| `SlurmNodeDown` | critical | a node is `down` for 5 m | Unusable capacity, and unlike drain it was nobody's decision |
| `SlurmNodeDrained` | warning | a node is `drain` for 10 m | Drains are expected; *persistent* drains quietly shrink the cluster |
| `SlurmJobFailureSpike` | warning | more than 3 jobs enter `failed` in 30 m | The scheduler-side echo of a bad node, a broken filesystem or an exhausted quota |
| `SlurmQueueStalledWithIdleNodes` | warning | jobs pending 30 m while nodes sit idle | Partition/QOS/GRES misconfiguration — capacity shortage looks different (pending with *no* idle nodes) |
| `SlurmJobGpuIdle` | warning | a job averages below 10 % GPU utilization for 30 m | Allocation waste: a healthy GPU held idle by a job |
<!-- markdownlint-enable MD013 -->

`SlurmJobGpuIdle` is the one that justifies the per-node exporter. DCGM
can see an idle GPU but has no idea who is holding it; the cgroup labels
supply the attribution, so the alert reaches Slack already carrying
`node`, `user` and `slurmjobid` — the operator gets the owner and the job
id without opening a dashboard.

Note on inhibition: only **node-scoped** criticals suppress warnings on
the same node. The Alertmanager inhibit rule was narrowed in this phase
with a `node!=""` guard on the source side, because under `equal`
Alertmanager treats an absent label as matching an absent label — without
the guard a cluster-wide critical such as `SlurmNodeDown` (which carries
no `node` label) would blanket-suppress every node-less warning,
including the other three Slurm warnings and `DcgmMetricsMissing`. Those
are independent signals, so node-less criticals now deliberately inhibit
nothing.

### Dashboards

Three dashboards, auto-provisioned into the **Algalon** folder like the
others:

- **Algalon / Slurm Queue** (`algalon-slurm-queue`) — the scheduler
  view: pending and running job counts, nodes down and drained, jobs by
  state over time, a node-state timeline (alloc / idle / drain / down)
  and a per-partition table.
- **Algalon / Slurm Job Explorer** (`algalon-slurm-jobs`) — one job at a
  time, selected with the `job_id` variable: owner and account, cgroup
  memory, process count and GPU count; per-GPU utilization, memory and
  power; and the node-joined panels described below.
- **Algalon / Scheduler Analytics** (`algalon-scheduler`) — a 7-day
  policy view rather than an ops view, fed by the optional accounting
  collector described in
  [Scheduler analytics](#scheduler-analytics-optional). Only its
  pending-versus-idle panel works without that collector.

The Job Explorer also carries two panels that answer a question the
scheduler cannot — *are the GPUs this job holds actually computing?* They
are written for the job's owner rather than for an operator; see
[GPU utilization quality](architecture.md#gpu-utilization-quality) for
the four-layer hierarchy they belong to.

### Metrics and labels

A few details worth knowing before you write your own queries:

- The Slurm job id label is **`slurmjobid`** (not `jobid` or `job_id`) —
  `job` is already taken by the scrape job name. Every rule, dashboard
  variable and join in Algalon uses that exact name.
- `slurm_job_power_gpu` is reported in **milliwatts**. The dashboard
  panels divide by 1000 to display watts; do the same in any query of
  your own.
- `slurm_job_memory_usage` is in bytes and is the metric used as the
  "this job is present on this node" existence probe in every join,
  because it exists for CPU-only jobs too.
- `user` and `account` come from the cgroup, so they are available on
  every job series without a lookup against Slurm.

## The `on(node)` join contract

Job series and hardware series meet through one shared label: `node`.
Because every `slurm-job` target carries the same `node` value that the
machine's dcgm and node-exporter targets carry, any node-level series can
be restricted to the nodes of a given job:

```promql
avg by (node) (DCGM_FI_DEV_GPU_UTIL)
  and on(node)
  (count by (node) (slurm_job_memory_usage{slurmjobid="$job_id"}) > 0)
```

The right-hand side is an existence probe — it yields one sample per node
where the job has a cgroup — and `and on(node)` keeps only the matching
left-hand series. The Job Explorer uses this for DCGM utilization, NFS
GETATTR latency and the table of alerts firing on the job's nodes.

**The limit, stated plainly:** those are *node*-level signals. They read
as job signal only when the job owns the whole node. On a shared node,
DCGM utilization mixes every tenant, and an alert in that table may
belong to somebody else's job. When nodes are shared, trust only the
cgroup metrics (`slurm_job_utilization_gpu`, `slurm_job_memory_usage`,
`slurm_job_core_usage_total`), which are per-job by construction.

If the join produces nothing, the `node` labels do not match. Compare
`up{job="slurm-job"}` against `up{job="dcgm"}` — the label values must be
identical strings, not merely the same machine.

## Job logs (optional)

Metrics tell you a job ran hot and then stopped. They do not tell you it
died on a CUDA OOM in the third epoch. Algalon can keep the tail of each
job's stdout next to its metrics, so the Job Explorer answers both
questions in one place.

This is a separate opt-in from the exporters above, with three moving
parts:

```text
slurmctld  --EpilogSlurmctld-->  epilog-logpush.sh
                                        |
                                        | HTTP POST /insert/jsonline
                                        v
                                  VictoriaLogs  <---- Grafana logs panel
```

### Why a push at job end, and not a tailer

The obvious design is a log agent that watches the output directories and
follows files as they grow. On a GPU cluster that design is actively
harmful: job outputs live on shared NFS, and a follower has to glob those
trees and re-stat every candidate file on every poll. That is a
continuous stream of NFS `GETATTR` operations against the same filer the
training jobs are reading checkpoints from.

Algalon's own `storage-nfs` and `node-precursor` rules alert on rising
NFS `GETATTR` latency, because the Lablup report identifies it as an
early indicator of checkpoint I/O trouble. A tailer would raise the exact
metric its own alerts watch — the collector would poison the signal it
was deployed to protect, and every operator would learn to ignore that
alert.

So nothing watches the filesystem. The log is read once, when the job is
already over, and only its last 10 MiB are shipped.

### Turning on the store

VictoriaLogs is off by default in both deployment paths.

Docker Compose — the `logs` profile:

```bash
cd deploy/compose/host
docker compose --profile logs up -d
```

`VLOGS_PORT` (default `9428`) and `VLOGS_RETENTION_MONTHS` (default `3`,
matching `VM_RETENTION_MONTHS`) are in `.env.example`.

Helm:

```bash
helm upgrade --install algalon deploy/helm/algalon \
  --set victorialogs.enabled=true
```

Two notes on Grafana. The VictoriaLogs datasource plugin is **always**
installed (`GF_INSTALL_PLUGINS`), whether or not the store is enabled, so
the panel below can render as soon as you flip the store on; Grafana
downloads it on first start, which means that container needs outbound
internet once — on an air-gapped host, set `grafana.installPlugins` to
`[]` and bake the plugin into a derived image. And in the compose stack
the datasource itself is provisioned unconditionally, so with the profile
down you will see a `VictoriaLogs` datasource whose health check fails.
That is expected; the Helm chart, which can gate on a value, only
provisions it when `victorialogs.enabled`.

### Installing the epilog hook

Put `monitoring/slurm/epilog-logpush.sh` somewhere the slurmctld host can
execute it, and register it as **`EpilogSlurmctld`** in `slurm.conf`:

```conf
EpilogSlurmctld=/etc/slurm/epilog-logpush.sh
```

`EpilogSlurmctld` — not `Epilog` — is the whole point. `Epilog` runs on
every allocated node, so a 64-node job would push the same shared output
file 64 times. `EpilogSlurmctld` runs **once per job, on the
controller**, as `SlurmUser`. There is no dedup logic in the script
because the hook makes dedup unnecessary.

The trade is that the controller must be able to read the job's `StdOut`
path, which on a typical cluster means it mounts the same shared
filesystem the users write to. If it cannot, the script exits silently
and you get no logs — not an error.

Point it at the store, in `/etc/default/slurmctld` or the unit's
`Environment=`:

```bash
VLOGS_URL=http://algalon-host.example.internal:9428
ALGALON_LOG_MAX_BYTES=10485760   # 10 MiB of trailing output per job
CURL_TIMEOUT=10
```

The script needs `curl` and `jq` on the controller alongside Slurm's own
`scontrol`. `jq` is what turns arbitrary log bytes into valid JSON;
hand-rolled escaping is a correctness trap and this script does not
attempt it.

**It cannot fail your jobs.** A non-zero `EpilogSlurmctld` makes
slurmctld drain nodes, so every path in the script — missing `jq`, an
unreadable output file, a VictoriaLogs that is down — ends in `exit 0`
with a line on stderr for the slurmctld log. That property matters more
than any log ever delivered, so treat it as load-bearing if you edit the
script.

### What you see

The **Algalon / Slurm Job Explorer** dashboard gains a full-width **Job
output (stdout)** panel at the bottom, bound to the `logs_datasource`
variable and querying the LogsQL stream filter:

```logsql
{slurmjobid="$job_id"}
```

`slurmjobid` and `user` are the ingest-time stream fields, which is what
makes that filter a stream lookup rather than a full scan. Each line also
carries `jobname`, `exitcode` and `nodelist` as ordinary fields, so
`{slurmjobid="123"} | exitcode:!="0:0"` and friends work in Explore.

The panel is empty — not broken — in three ordinary cases: the job is
still running (output is pushed at the end, not live), the job finished
before you installed the hook, or the store is off.

## Scheduler analytics (optional)

The two exporters above answer *what is the scheduler doing right now*.
Neither can tell you whether the partition layout is any good, because
both publish gauges: an hour after the fact, a job that queued for six
hours is indistinguishable from one that started immediately. Every
question a policy review actually asks — should this partition's time
limit go up, is anyone waiting too long, which account is consuming the
fleet — needs per-job history, and that lives in Slurm's own accounting
database.

`monitoring/slurm/sacct-textfile.sh` reads it. The script runs on the
controller from cron or a systemd timer, folds each window of finished
jobs into cumulative counters, and writes them where node_exporter will
publish them. Like the epilog hook, Algalon ships the script and the
rules and dashboards that read it, but never deploys or schedules it.

This is a third, separate opt-in. It needs neither exporter above,
though the Scheduler Analytics dashboard is more useful with the queue
exporter running alongside it.

### Why a textfile collector and not another exporter

`sacct` is a database query, not a cheap read. An exporter would put a
synchronous slurmdbd round-trip inside every 30-second scrape, and the
first time the accounting database got slow it would surface as an
exporter outage rather than as what it is. A cron job writing a `.prom`
file decouples the two: node_exporter serves the last good snapshot at
memory speed, and a hung `sacct` delays data instead of breaking scrapes.

It also means the collector holds its own state. The `.prom` file is a
pure rendering of a state file the script owns, which is what keeps the
counters monotonic across runs and across reboots — see
[State, resets and restarts](#state-resets-and-restarts).

### What it emits, and what each metric decides

<!-- markdownlint-disable MD013 -->
| Metric | Type | Labels | The decision it informs |
| --- | --- | --- | --- |
| `slurm_jobs_completed_total` | counter | `state`, `partition`, `account` | Where outcomes cluster. A `timeout` share that keeps climbing is a walltime limit set below what the work needs. The `account` breakdown is what makes [failure breadth](#failure-counts-failure-distribution) visible |
| `slurm_job_node_failures_total` | counter | `node` | **Which node is sick.** FAILED and NODE_FAIL jobs charged to every node they held, with Slurm's compressed nodelists expanded. Flat is normal; a node hoarding failures is a drain candidate |
| `slurm_job_wait_seconds` | histogram | `partition` | **Partition and QOS limits.** p50 tells you what a typical user experiences, p90 tells you who is being starved. A flat p50 under a climbing p90 means the limits, not the capacity, are the constraint |
| `slurm_job_runtime_seconds` | histogram | `partition` | **Partition layout.** A partition whose p90 runtime is minutes does not need a multi-day maximum time; one whose p50 already sits near its limit will keep producing timeouts |
| `slurm_job_timelimit_used_ratio` | histogram | `partition` | **Backfill efficiency.** `Elapsed / Timelimit`. Mass at the low end is padded walltime, and the scheduler cannot backfill a job into a gap it believes is too short — so over-requesting leaves nodes idle in front of a full queue. Mass above 1.0 is the jobs the limit killed |
| `slurm_job_gpu_seconds_total` | counter | `partition`, `account` | **Fairshare.** Allocated GPU-seconds per account. An account far above its intended share is an argument for a fairshare or QOS change rather than for buying hardware |
| `slurm_sacct_collector_last_run_timestamp_seconds` | gauge | — | Whether the timer is still running. Stale means the cron job died, not that the cluster went quiet |
| `slurm_sacct_collector_errors_total` | counter | — | Rows the parser could not read. A rising value means `sacct` output drifted from what the script expects — see [What could still surprise you](#what-could-still-surprise-you) |
<!-- markdownlint-enable MD013 -->

`slurm_job_gpu_seconds_total` counts **allocated** GPU-seconds, not used
ones: a job holding an idle GPU is counted in full. That is exactly why
`SlurmJobGpuIdle` exists next to it — one metric says what was handed
out, the other says whether it was put to work.

The wait histogram also feeds one recording rule,
`algalon:sli:job_wait_ok_1h` in
[`monitoring/rules/slo.yml`](../monitoring/rules/slo.yml): the share of
jobs that started within 30 minutes of submission. The 30-day version of
that ratio is a stat tile on **SLO Overview**, recomputed there from the
raw histogram rather than averaged from the hourly rule, so a busy
afternoon weighs more than a quiet night. It has no alert — see
[Failure counts, failure distribution](#failure-counts-failure-distribution).

### Installing it on the controller

Put the script somewhere the controller can execute it, and give it a
state directory:

```bash
install -m 0755 monitoring/slurm/sacct-textfile.sh \
  /usr/local/bin/algalon-sacct-textfile
install -d -m 0755 /var/lib/algalon-sacct
install -d -m 0755 /var/lib/node_exporter/textfile
```

It reads three optional environment variables:

```bash
SACCT_STATE_DIR=/var/lib/algalon-sacct
TEXTFILE_DIR=/var/lib/node_exporter/textfile
ALGALON_SACCT_LOOKBACK_S=3600   # first run only; later runs resume
```

`ALGALON_SACCT_LOOKBACK_S` is used **only** when no state exists yet. Every
later run resumes from the end of the previous window, so the schedule
below and that value are independent — changing the cron period does not
create a gap or a double count.

Run it as a user `sacct` will answer for. The script passes `--allusers`,
which needs the caller to be a Slurm operator or admin; without that
privilege `sacct` silently reports only the caller's own jobs, and the
collector would cheerfully publish near-zero counters.

Cron, every five minutes. The two paths above are the script's own
defaults, so nothing needs to be passed unless you moved them:

```cron
*/5 * * * * root /usr/local/bin/algalon-sacct-textfile
```

Or a systemd timer, which is easier to inspect when it misbehaves.
`/etc/systemd/system/algalon-sacct.service`:

```ini
[Unit]
Description=Algalon sacct textfile collector
After=slurmdbd.service

[Service]
Type=oneshot
User=root
Environment=SACCT_STATE_DIR=/var/lib/algalon-sacct
Environment=TEXTFILE_DIR=/var/lib/node_exporter/textfile
ExecStart=/usr/local/bin/algalon-sacct-textfile
```

`/etc/systemd/system/algalon-sacct.timer`:

```ini
[Unit]
Description=Run the Algalon sacct textfile collector every 5 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
AccuracySec=30s

[Install]
WantedBy=timers.target
```

```bash
systemctl daemon-reload
systemctl enable --now algalon-sacct.timer
```

Unlike the epilog, this script **exits non-zero on failure** — a drained
node is not at stake here, and a cron job that fails silently is a cron
job nobody notices. `systemctl status algalon-sacct.service` or cron's
mail will show what went wrong.

### Publishing the file

The `.prom` file is only useful if a node_exporter on the same host reads
it. That means the controller needs its own node_exporter started with:

```bash
node_exporter --collector.textfile.directory=/var/lib/node_exporter/textfile
```

and a scrape target for it. In the Compose path, add the controller to
`deploy/compose/host/targets/node-targets.yml` like any other machine.

In the Helm path, where the controller is a cluster node running
Algalon's own node-exporter DaemonSet, set the chart's
`nodeExporter.textfileDirectory` to the host directory instead of running
a second exporter:

```yaml
nodeExporter:
  textfileDirectory: /var/lib/node_exporter/textfile
```

The DaemonSet then mounts that host path read-only at the same location
and enables the textfile collector. It is empty by default, which is what
keeps the collector off for everyone who has not opted in. Note that the
value applies to *every* node the DaemonSet covers — nodes without a
`.prom` file simply contribute nothing.

If the controller is not a Kubernetes node, keep a host node_exporter
there and list it under `nodeExporter.staticTargets` instead.

### State, resets and restarts

`$SACCT_STATE_DIR/state` holds the end of the last processed window plus
every cumulative counter and bucket. Three consequences worth knowing:

- **Counters survive reboots.** Nothing is recomputed from a time window,
  so a controller restart does not reset a single counter — the next run
  simply resumes from where the last one stopped.
- **Deleting the state directory resets everything to zero.** That is a
  normal counter reset, and `increase()` and `rate()` handle it: you lose
  history, not correctness. Every query in the rules and dashboards is
  written in those terms for exactly this reason.
- **A failed run does not lose jobs.** The window end only advances after
  every job in the window has been folded in, so an aborted run makes the
  next one re-query the same jobs. Overlap is deduplicated by each job's
  end time, so re-querying counts nothing twice.

The `.prom` file is written to a temporary file and renamed, so
node_exporter never reads a half-written exposition — it sees either the
previous snapshot or the new one.

### Cardinality

The only labels are `partition` (a handful per cluster), `account` (tens)
and the histograms' own `le`. That is a few hundred series at most, and
it does not grow with cluster usage.

`user` is deliberately **not** a label. User counts grow without bound,
and every user would multiply three histograms — the one dimension that
would turn this collector into a cardinality problem is the one it
refuses to add. Per-user attribution is an `sacct` query, not a time
series. (The per-job exporter does carry `user`, but only for jobs that
are running right now, which is a bounded set.)

### Failure counts, failure distribution

The obvious thing to build on `slurm_jobs_completed_total` is a success
ratio with burn-rate alerts, and Algalon deliberately does not.

On a shared research cluster most `FAILED` jobs are user error: a typo in
a batch script, an OOM from a batch size the user chose, a bad module
load. That is as true of one intermittent failure as it is of one user
failing forty times in a row — the second is not an incident, it is
somebody debugging. Paging an operator for that ratio pages them for a
mistake they cannot fix, and an operator who cannot act on a page learns
to ignore every page from the same source, including the ones that mean a
node is on fire. The cost is not the wasted alert; it is the trust spent
on it.

That argument is airtight, and it only covers the **total**. What user
error cannot explain is a change in the *distribution* of those failures,
and there are two axes of it.

**Concentration — one node collecting a disproportionate share.** Users
do not choose their nodes; the scheduler does, so mistakes land roughly
uniformly across the fleet. A node that starts hoarding failures is not
being picked by unluckier people, it is broken: a dying GPU, a bad
driver, a full local disk, a NIC that drops under load. That is a drain
candidate, and it is exactly what an operator can act on. Hence
`slurm_job_node_failures_total{node}` and `SlurmNodeFailureConcentration`,
which asks for both an absolute floor and a majority share so that
ordinary attrition landing on one node stays quiet.

The `node` label deliberately carries the same values as every other
`node` label in Algalon (see [The `on(node)` join
contract](#the-onnode-join-contract)). Two things follow. The suspect
node can be looked up immediately in Node Health and DCGM for the
corroborating hardware evidence; and the Alertmanager inhibit rule —
node-scoped criticals suppress warnings on the same node — silences the
concentration warning automatically when a critical such as
`GpuXidFellOffBus` has already named the cause. The failures are that
critical's symptom, not a second incident.

**Breadth — failures across many accounts at once.** One user's mistake
is confined to that user's account by construction. It cannot make three
unrelated teams fail in the same half hour. Shared infrastructure can: a
filesystem that went away, a sick slurmctld, an expired credential, a bad
module update. Hence the `account` label and
`SlurmFailureSpreadAcrossAccounts`, which requires both several accounts
*and* real volume — three accounts failing one job each is a quiet
afternoon.

And one case needs no inference at all: `SlurmNodeFailJobs` fires on
Slurm's own `NODE_FAIL` verdict. No user can put a job into that state,
so it is never user error by definition.

All four signals are warnings with `action: investigate`, all live in
`monitoring/rules/slurm.yml` next to the other scheduler alerts, and all
are silent on a cluster without the collector.

The principle in one line: **failure counts measure users; failure
distribution measures the cluster.**

### What could still surprise you

- **Accounting lag.** The window ends at "now", so a job that finished
  seconds ago and has not yet been committed to slurmdbd falls outside
  both this window and the next. On a busy cluster this is a handful of
  jobs per run; if it matters to you, widen the schedule rather than the
  window.
- **Typed GRES.** GPU counts come from the untyped `gres/gpu=N` token in
  `AllocTRES`. Slurm emits it alongside typed entries
  (`gres/gpu:a100=2`), so a typed request is still counted once — but a
  site that has suppressed the untyped token will see zero GPU-seconds.
- **Jobs that never started.** `CANCELLED` while pending gives a job no
  start time. Those jobs are counted in `slurm_jobs_completed_total` and
  excluded from all three histograms, because a zero wait for a job that
  never ran would drag every quantile toward the floor.
- **`UNLIMITED` and `Partition_Limit` walltimes** have no used-ratio and
  are absent from `slurm_job_timelimit_used_ratio` entirely.
- **Node names must match your `node` labels.** `slurm_job_node_failures_total`
  takes its node names from Slurm's own nodelist. If your scrape targets
  label the same machines differently, the failure counter will not line
  up with DCGM or node-exporter — the same caveat that applies to
  slurm-job-exporter targets, and the same fix: make the label values
  identical strings.
- **Array and heterogeneous jobs** are counted per allocation
  (`--allocations`), so a 1000-task array contributes 1000 rows, one per
  task, and no separate row for the array as a whole.

## See also

- [Architecture](architecture.md) — the pipeline these targets feed
- [Deployment](deployment.md) — choosing a deployment path
