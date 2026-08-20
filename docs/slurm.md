# Slurm integration

**English** | [한국어](ko/slurm.md)

Algalon can read the Slurm scheduler's view of the cluster alongside its
hardware view: which jobs are queued, which nodes the scheduler has
given up on, and — per job — who owns it and whether the GPUs it holds
are doing any work. The integration is entirely opt-in: it adds two
scrape jobs, and with no targets registered it produces no series, no
alerts and two empty dashboards.

Nothing here is deployed by Algalon. Both exporters need Slurm CLI or
cgroup access on the host, so they run as ordinary host services on your
Slurm machines and Algalon only scrapes them.

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

The exporters live outside the cluster, so `kubernetes_sd` cannot find
them; they are enumerated statically in values instead. Everything is
gated on `slurm.enabled`, which defaults to `false`:

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

```yaml
slurm:
  jobExporter:
    enabled: true
    image: ghcr.io/appleparan/slurm-job-exporter:0.4.12
    port: 9798
    dcgmUpdateInterval: 10
    nodeSelector: {}
    tolerations: []
    resources:
      requests: {cpu: 100m, memory: 128Mi}
```

`jobExporter` renders on `slurm.jobExporter.enabled: true` alone; it
does not require `slurm.enabled: true`, which only gates the static
`queueTargets`/`jobTargets` scrape jobs described above. The pods carry
`algalon.io/scrape: "true"` and `algalon.io/job: slurm-job`, so the
`algalon-pods` kubernetes_sd job picks them up the same way it picks up
`dcgm-exporter` and `node-exporter` pods — no scrape-config change is
needed. `job` comes from the `algalon.io/job` pod label and `node` from
`__meta_kubernetes_pod_node_name`, exactly the relabelling `jobTargets`
gets by hand for its static entries, so the resulting series carry the
same `job="slurm-job"` and `node` labels either way and every rule,
dashboard and join above applies unchanged.

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

Two dashboards, auto-provisioned into the **Algalon** folder like the
others:

- **Algalon / Slurm Queue** (`algalon-slurm-queue`) — the scheduler
  view: pending and running job counts, nodes down and drained, jobs by
  state over time, a node-state timeline (alloc / idle / drain / down)
  and a per-partition table.
- **Algalon / Slurm Job Explorer** (`algalon-slurm-jobs`) — one job at a
  time, selected with the `job_id` variable: owner and account, cgroup
  memory, process count and GPU count; per-GPU utilization, memory and
  power; and the node-joined panels described below.

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

## See also

- [Architecture](architecture.md) — the pipeline these targets feed
- [Deployment](deployment.md) — choosing a deployment path
