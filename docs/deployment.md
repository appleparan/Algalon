# Deployment

**English** | [한국어](ko/deployment.md)

Algalon ships three deployment paths. All three consume the same
`monitoring/` content, so the rules, dashboards and alerting policy are
identical no matter how you run it.

| Path | Best for | Guide |
| --- | --- | --- |
| Local k3s cluster | On-prem GPU clusters (**recommended**) | [`deploy/k3s/`](../deploy/k3s/README.md) |
| Kubernetes / Helm | Existing clusters | [`deploy/helm/algalon/`](../deploy/helm/algalon/README.md) |
| Docker Compose | Single node, development, small fleets | [`deploy/compose/`](../deploy/compose/README.md) |

## Local k3s cluster (recommended for on-prem)

The design assumption is that your training workloads keep running on
the host exactly as they do today — under Docker, under
Apptainer/Singularity, or as bare processes — and Algalon must not
disturb them. A k3s agent runs *alongside* whatever runtime each node
uses and schedules only the exporter DaemonSets: it ships its own
embedded containerd, so it shares no state with the host's container
stack; the kubelet cannot see or evict host workloads; and
dcgm-exporter never requests `nvidia.com/gpu`, so it never competes
with training jobs for GPU allocation. Docker gets the most attention
in the runbook only because it is the one runtime that also writes
iptables rules — exactly what the preflight script checks. Daemonless
runtimes like Apptainer share even less with k3s and need no special
handling.

What you gain over hand-managed Compose stacks: adding a node is one
`curl` command (the DaemonSets and scrape discovery pick it up
automatically), upgrades are a single `helm upgrade`, and there is no
target file to maintain.

The remaining conflict surface is host networking — ports, the flannel
CIDRs, iptables interplay — which is exactly what the shipped preflight
script checks before anything is installed. k3s's default addons
(Traefik, ServiceLB, metrics-server) are disabled at install time so
nothing grabs host ports 80/443.

```bash
./deploy/k3s/preflight.sh server      # read-only checks, PASS/WARN/FAIL
./deploy/k3s/install-server.sh        # k3s server, default addons disabled
helm install algalon oci://ghcr.io/appleparan/charts/algalon \
  --version <X.Y.Z> --namespace algalon \
  --create-namespace --set alertmanager.slack.existingSecret=algalon-slack
K3S_URL=https://<server>:6443 K3S_TOKEN=<token> \
  ./deploy/k3s/install-agent.sh       # on every GPU node
```

Released chart versions are published to `oci://ghcr.io/appleparan/charts/algalon`
(and attached to each GitHub release as a `.tgz`) by the release workflow —
no repo checkout is needed on the target host. To install from a source
checkout instead, run `make helm-sync` first (the chart's `files/` content
is generated), then point `helm install` at `deploy/helm/algalon`.

Both installers refuse to run when k3s is already present; removal is a
deliberate manual step documented in the
[runbook](../deploy/k3s/README.md).

## Kubernetes / Helm

For clusters you already operate: exporters run as DaemonSets on the GPU
nodes (targeted by the `nvidia.com/gpu.present` label), and the host
stack — VictoriaMetrics, vmagent, vmalert, Alertmanager, Grafana — runs
as Deployments. vmagent discovers exporter pods through the Kubernetes
API, so scrape targets never need manual maintenance.

Machines that are not cluster members — bare-metal GPU nodes running
their own exporters, a Slurm controller — are added statically via
`dcgmExporter.staticTargets` / `nodeExporter.staticTargets` (and the
`slurm.*Targets` values). Static entries carry the same `job` and `node`
label contract as the DaemonSet pods; see the
[chart README](../deploy/helm/algalon/README.md#scraping-and-labels).

One thing to remember: `make helm-sync` must run before the first
install. Helm cannot read files outside a chart, so the chart's `files/`
directory is generated from `monitoring/` and is git-ignored.

Sites that need alert rules, dashboards or scrape configs beyond what
`monitoring/` ships can inject them via `vmalert.extraRules`,
`grafana.extraDashboards` and `vmagent.extraScrapeConfigs` — see
[Site extensions](../deploy/helm/algalon/README.md#site-extensions) in the
chart README.

## Docker Compose

Two stacks: `deploy/compose/host` (storage, alerting, UI — one machine)
and `deploy/compose/worker` (exporters — every GPU node). Worker nodes
are registered by copying the target templates on the host; all-smi is
opt-in via `--profile all-smi`. This is the shortest path for a single
machine or a small, static fleet.

## CPU memory bandwidth (optional)

A GPU node whose host memory bus is saturated — data loaders, pinned-memory
copies — looks idle on every DCGM metric and normal on every node_exporter
metric: PSI measures stalls and NUMA counters measure placement, neither
measures bandwidth. The only kernel interface to it is resctrl MBM
(Memory Bandwidth Monitoring), so Algalon ships
`monitoring/exporters/resctrl-mbm-textfile.sh`, which writes the counters
as a node_exporter textfile for the Host Saturation dashboard. Like the
Slurm scripts it is a site-side artifact: Algalon never deploys or
schedules it.

**It is built to cost nothing on the workload.** Reading an MBM file makes
the kernel read one hardware counter per L3 domain, so the cost is
groups × domains × frequency. The script reads only the default monitor
group, once per run, with no daemon: a handful of reads every 30 s. It
never creates monitor groups, never writes `schemata`, and never mounts
resctrl itself. The price of that choice is resolution: you get bandwidth
per node and L3 domain, not per job. Per-job groups would add an RMID per
job and MSR writes on the workload's own context switches, which is the
overhead this design avoids.

Install on each node you want measured, as root:

```bash
grep -c cqm_mbm_total /proc/cpuinfo            # 0 = this CPU has no MBM
mount -t resctrl resctrl /sys/fs/resctrl       # do not add -o mba_MBps
install -m 0755 monitoring/exporters/resctrl-mbm-textfile.sh \
  /usr/local/bin/algalon-resctrl-mbm-textfile
```

```ini
# /etc/systemd/system/algalon-resctrl-mbm.service
[Unit]
Description=Algalon resctrl MBM textfile export
ConditionPathIsDirectory=/sys/fs/resctrl

[Service]
Type=oneshot
ExecStart=/usr/local/bin/algalon-resctrl-mbm-textfile
Nice=19
IOSchedulingClass=idle
```

```ini
# /etc/systemd/system/algalon-resctrl-mbm.timer
[Unit]
Description=Run the Algalon resctrl MBM export every 30 s

[Timer]
OnBootSec=30s
OnUnitActiveSec=30s
AccuracySec=1s

[Install]
WantedBy=timers.target
```

Then `systemctl daemon-reload && systemctl enable --now
algalon-resctrl-mbm.timer`. The resctrl mount does not survive a reboot
unless you add it to `/etc/fstab`.

node-exporter must read the directory the script writes to
(`/var/lib/node_exporter/textfile` by default). The compose worker stack
does so out of the box (`NODE_EXPORTER_TEXTFILE_DIR`); in the chart set
`nodeExporter.textfileDirectory`.

Limits, none of them verified on hardware by this project: AMD CPUs can
return `Unavailable` when hardware counters run out, which shows up as
gaps, never as zeros; Sub-NUMA Clustering needs a recent kernel for
correct values; and the dashboard draws no "100%" line because the
platform's peak bandwidth is not exported — compare against the node's
own history or a STREAM run. Where MBM is unavailable, Intel PCM or AMD
uProf measure the same thing outside this pipeline.

## Secrets

Slack webhook URLs are always injected at deploy time — a mounted secret
file for Compose, a Kubernetes Secret (or `existingSecret` reference)
for Helm. None are ever stored in git, and Alertmanager refuses to
render without them rather than shipping a silently broken notifier.
