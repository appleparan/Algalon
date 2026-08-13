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
make helm-sync
helm install algalon deploy/helm/algalon --namespace algalon \
  --create-namespace --set alertmanager.slack.existingSecret=algalon-slack
K3S_URL=https://<server>:6443 K3S_TOKEN=<token> \
  ./deploy/k3s/install-agent.sh       # on every GPU node
```

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

## Docker Compose

Two stacks: `deploy/compose/host` (storage, alerting, UI — one machine)
and `deploy/compose/worker` (exporters — every GPU node). Worker nodes
are registered by copying the target templates on the host; all-smi is
opt-in via `--profile all-smi`. This is the shortest path for a single
machine or a small, static fleet.

## Secrets

Slack webhook URLs are always injected at deploy time — a mounted secret
file for Compose, a Kubernetes Secret (or `existingSecret` reference)
for Helm. None are ever stored in git, and Alertmanager refuses to
render without them rather than shipping a silently broken notifier.
