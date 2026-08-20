# algalon Helm chart

GPU cluster monitoring and alert center on Kubernetes: DCGM exporter +
node-exporter (and optional all-smi) as DaemonSets on the GPU nodes,
VictoriaMetrics + vmagent + vmalert + Alertmanager + Grafana as the host
stack.

Rules, dashboards, the Alertmanager policy and the DCGM counter set all
come from `monitoring/` at the repo root — the chart never holds a second
copy (see [Generated content](#generated-content-filesmust-be-synced)).

## Install

`files/` is generated and git-ignored, so **sync it first** — a fresh
clone has no `files/` and the chart renders empty ConfigMaps without it:

    make helm-sync
    helm install algalon deploy/helm/algalon \
      --namespace algalon --create-namespace \
      --set alertmanager.slack.existingSecret=algalon-slack

Endpoints are ClusterIP Services named after the release (no Ingress is
shipped):

    kubectl -n algalon port-forward svc/algalon-grafana 3000:3000

| Service | Port | |
|---|---|---|
| `<release>-grafana` | 3000 | UI, dashboards in the **Algalon** folder |
| `<release>-victoriametrics` | 8428 | TSDB / query API |
| `<release>-vmalert` | 8880 | rule evaluation |
| `<release>-alertmanager` | 9093 | routing + Slack |

Change `grafana.adminPassword` from the default `admin` before exposing
Grafana beyond a port-forward.

## Slack webhooks are required

Alertmanager reads the webhook URLs as files, so a missing Secret means a
permanently broken notifier. The chart refuses to render rather than ship
that silent outage — configure one of the two options below.

**Bring your own Secret (recommended).** The key names are a contract with
the Alertmanager policy's `api_url_file` paths:

    kubectl -n algalon create secret generic algalon-slack \
      --from-literal=slack_webhook_critical='https://hooks.slack.com/services/T.../B.../xxx' \
      --from-literal=slack_webhook_warning='https://hooks.slack.com/services/T.../B.../yyy'

then `--set alertmanager.slack.existingSecret=algalon-slack`.

**Or let the chart create it** with `alertmanager.slack.criticalUrl` and
`alertmanager.slack.warningUrl` (both required). Avoid this under GitOps:
values files get committed, and these are credentials.

## Worker-only install

GPU nodes in a cluster that already has an Algalon host stack (or a
compose host) only need the exporters:

    helm install algalon-workers deploy/helm/algalon \
      --namespace algalon --create-namespace \
      --set host.enabled=false

`host.enabled=false` drops VictoriaMetrics, vmagent, vmalert, Alertmanager
and Grafana — including the Slack Secret requirement. The exporters keep
their contract-fixed ports: DCGM `9400`, node-exporter `9100`
(hostNetwork), all-smi `9090`, slurm-job-exporter `9798` (hostNetwork,
opt-in).

## all-smi (optional)

Off by default; it duplicates DCGM's coverage and only pays for itself on
mixed NVIDIA/Apple/Rebellions fleets or when you want its unified view:

    --set allSmi.enabled=true

It powers the `algalon-allsmi` dashboard, which stays empty otherwise.

## Values

<!-- markdownlint-disable MD013 -->
| Key | Default | What it does |
|---|---|---|
| `dcgmExporter.enabled` | `true` | GPU metrics DaemonSet |
| `dcgmExporter.image` | `nvcr.io/nvidia/k8s/dcgm-exporter:4.6.0-4.8.3-ubi9` | 4.x metric names; 3.x renames the clocks-event metric |
| `dcgmExporter.port` | `9400` | scraped port (name `metrics`) |
| `dcgmExporter.nodeSelector` | `nvidia.com/gpu.present: "true"` | gpu-operator's node label |
| `dcgmExporter.tolerations` | `nvidia.com/gpu` Exists | run on tainted GPU nodes |
| `dcgmExporter.runtimeClassName` | `""` | set for `nvidia` RuntimeClass clusters |
| `dcgmExporter.extraArgs` | `[]` | extra CLI args; main use is `["-r", "localhost:5555"]` to attach to a host-side nv-hostengine |
| `dcgmExporter.hostNetwork` | `false` | share the host netns so `extraArgs` can reach that engine on localhost |
| `dcgmExporter.staticTargets` | `[]` | out-of-cluster dcgm-exporters, `{address, node}` entries |
| `nodeExporter.enabled` | `true` | host metrics DaemonSet (hostNetwork/hostPID) |
| `nodeExporter.port` | `9100` | host port, not just a container port |
| `nodeExporter.staticTargets` | `[]` | out-of-cluster node-exporters, `{address, node}` entries |
| `nodeExporter.textfileDirectory` | `""` | hostPath with `*.prom` files; enables `--collector.textfile.directory` |
| `allSmi.enabled` | `false` | optional unified GPU exporter |
| `allSmi.interval` | `5` | sampling interval, seconds |
| `slurm.jobExporter.enabled` | `false` | in-cluster slurm-job-exporter DaemonSet; alternative to `slurm.jobTargets` |
| `slurm.jobExporter.image` | `ghcr.io/appleparan/slurm-job-exporter:0.4.12` | required when enabled; built from `docker/slurm-job-exporter/` |
| `slurm.jobExporter.port` | `9798` | container **and** host port (name `metrics`) |
| `slurm.jobExporter.dcgmUpdateInterval` | `10` | DCGM sampling interval, seconds |
| `slurm.jobExporter.runtimeClassName` | `""` | set to `nvidia` where the runtime is behind a RuntimeClass — required for per-job GPU metrics |
| `slurm.jobExporter.nodeSelector` | `{}` | restrict to the Slurm compute nodes |
| `slurm.jobExporter.tolerations` | `[]` | tolerate the compute nodes' taints |
| `slurm.jobExporter.resources` | `cpu 100m / mem 128Mi` | requests only |
| `host.enabled` | `true` | set `false` for a worker-only install |
| `victoriametrics.retentionMonths` | `3` | `--retentionPeriod` (VM's unitless default is months) |
| `victoriametrics.storage.size` | `50Gi` | PVC size (StatefulSet) |
| `victoriametrics.storage.storageClassName` | `""` | `""` = cluster default |
| `vmagent.scrapeInterval` | `30s` | global scrape interval |
| `vmagent.extraScrapeConfigs` | `""` | site-supplied `scrape_configs` YAML fragment, appended verbatim — see [Site extensions](#site-extensions) |
| `vmalert.evaluationInterval` | `30s` | rule evaluation interval |
| `vmalert.extraRules` | `{}` | site-supplied rule files, `<name>` → content — see [Site extensions](#site-extensions) |
| `alertmanager.slack.existingSecret` | `""` | Secret with `slack_webhook_critical` / `slack_webhook_warning` |
| `alertmanager.slack.criticalUrl` | `""` | chart-created Secret instead (not for GitOps) |
| `alertmanager.slack.warningUrl` | `""` | as above; both URLs required together |
| `grafana.adminUser` | `admin` | `GF_SECURITY_ADMIN_USER` |
| `grafana.adminPassword` | `admin` | `GF_SECURITY_ADMIN_PASSWORD` — change it |
| `grafana.extraDashboards` | `{}` | site-supplied dashboards, `<name>` → JSON — see [Site extensions](#site-extensions) |
<!-- markdownlint-enable MD013 -->

Every component also takes `image` and `resources`; see `values.yaml`.

## Generated content: `files/` must be synced

`deploy/helm/algalon/files/` is **generated and git-ignored**. It is an
rsync mirror of `monitoring/{rules,dashboards,alerting,exporters}`, which
is the single source of truth for both the compose and Helm deployments.

    make helm-sync      # after ANY edit under monitoring/

Never edit `files/` and never commit it — the next sync deletes your
changes. `make helm-validate` depends on `helm-sync`, so validation always
sees fresh content; `helm package` and `helm install` do not, so run the
sync yourself before either.

## Scraping and labels

vmagent uses one `kubernetes_sd` pod job. It keeps pods labelled
`algalon.io/scrape=true`, keeps only the container port named `metrics`
(one target per pod), copies `algalon.io/job` into the `job` label and the
node name into `node` — the exact labels the alert rules filter and
Alertmanager groups on. There is no prometheus-operator dependency: no
ServiceMonitors, no PodMonitors, no CRDs.

Machines that are not cluster members — bare-metal GPU nodes next to the
cluster, a Slurm controller — are listed statically instead, in
`dcgmExporter.staticTargets` / `nodeExporter.staticTargets` and the
`slurm.queueTargets` / `slurm.jobTargets` values. Static entries produce
the same `job` labels as the DaemonSet pods, so rules and dashboards make
no distinction; the `node` label comes from the entry and must be the
exact same string across every job scraping that machine — it is the join
key, and a mismatch shows up not as an error but as silently empty
dashboard panels.

The Slurm *job* exporter is the one case with both paths. When the compute
nodes are cluster members, `slurm.jobExporter.enabled` runs it as a
DaemonSet and the `algalon-pods` job discovers it like any other pod, with
`node` derived from `__meta_kubernetes_pod_node_name`; when they are not,
`slurm.jobTargets` enumerates them statically. Pick one per node set —
enabling both scrapes the same jobs twice. The queue exporter
(`slurm.queueTargets`) is always static: it belongs on the slurmctld or a
login node, which is not part of the cluster.

## Site extensions

Three values let a site attach content the chart doesn't know about, without
forking it:

- `vmalert.extraRules` — map of `<name>` → full rule-file content. Each
  entry renders as ConfigMap key `extra-<name>.yml`, alongside (not
  replacing) the chart's own rule files.
- `grafana.extraDashboards` — map of `<name>` → dashboard JSON. Each entry
  renders as ConfigMap key `extra-<name>.json`.
- `vmagent.extraScrapeConfigs` — a single string: a raw `scrape_configs`
  list fragment (starting at `- job_name: ...`), appended verbatim to the
  generated `prometheus.yml`.

Inject at install/upgrade time with `--set-file`, one entry per file:

    helm upgrade algalon deploy/helm/algalon \
      --set-file 'vmalert.extraRules.h100-serving=path/to/rules.yaml' \
      --set-file 'grafana.extraDashboards.h100-serving=path/to/dashboard.json' \
      --set-file 'vmagent.extraScrapeConfigs=path/to/scrape.yaml'

Supply the files with LF line endings — CRLF content keeps literal `\r`
bytes in the rendered manifest.

Validating injected content is the site's responsibility: the chart's
`rules-test` / `dashboards-validate` targets cover only the chart's own
`monitoring/` files, not whatever a site injects through these values.

The vmagent, vmalert and Grafana Deployments already carry `checksum/*`
annotations on their respective ConfigMaps, so a plain `helm upgrade` with
updated extra values is enough to roll the pods — no manual restart needed.

## Validate

    make helm-validate      # helm lint + kubeconform -strict, after helm-sync

Not shipped by design: Ingress, NetworkPolicies, HA replicas,
prometheus-operator CRDs, and a Grafana PVC (Grafana is stateless here —
all datasources and dashboards are provisioned from ConfigMaps).
