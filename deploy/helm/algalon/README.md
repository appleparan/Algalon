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
(hostNetwork), all-smi `9090`.

## all-smi (optional)

Off by default; it duplicates DCGM's coverage and only pays for itself on
mixed NVIDIA/Apple/Rebellions fleets or when you want its unified view:

    --set allSmi.enabled=true

It powers the `algalon-allsmi` dashboard, which stays empty otherwise.

## Values

| Key | Default | What it does |
|---|---|---|
| `dcgmExporter.enabled` | `true` | GPU metrics DaemonSet |
| `dcgmExporter.image` | `nvcr.io/nvidia/k8s/dcgm-exporter:4.6.0-4.8.3-ubi9` | 4.x metric names; 3.x renames the clocks-event metric |
| `dcgmExporter.port` | `9400` | scraped port (name `metrics`) |
| `dcgmExporter.nodeSelector` | `nvidia.com/gpu.present: "true"` | gpu-operator's node label |
| `dcgmExporter.tolerations` | `nvidia.com/gpu` Exists | run on tainted GPU nodes |
| `dcgmExporter.runtimeClassName` | `""` | set for `nvidia` RuntimeClass clusters |
| `dcgmExporter.staticTargets` | `[]` | out-of-cluster dcgm-exporters, `{address, node}` entries |
| `nodeExporter.enabled` | `true` | host metrics DaemonSet (hostNetwork/hostPID) |
| `nodeExporter.port` | `9100` | host port, not just a container port |
| `nodeExporter.staticTargets` | `[]` | out-of-cluster node-exporters, `{address, node}` entries |
| `nodeExporter.textfileDirectory` | `""` | hostPath with `*.prom` files; enables `--collector.textfile.directory` |
| `allSmi.enabled` | `false` | optional unified GPU exporter |
| `allSmi.interval` | `5` | sampling interval, seconds |
| `host.enabled` | `true` | set `false` for a worker-only install |
| `victoriametrics.retentionMonths` | `3` | `--retentionPeriod` (VM's unitless default is months) |
| `victoriametrics.storage.size` | `50Gi` | PVC size (StatefulSet) |
| `victoriametrics.storage.storageClassName` | `""` | `""` = cluster default |
| `vmagent.scrapeInterval` | `30s` | global scrape interval |
| `vmalert.evaluationInterval` | `30s` | rule evaluation interval |
| `alertmanager.slack.existingSecret` | `""` | Secret with `slack_webhook_critical` / `slack_webhook_warning` |
| `alertmanager.slack.criticalUrl` | `""` | chart-created Secret instead (not for GitOps) |
| `alertmanager.slack.warningUrl` | `""` | as above; both URLs required together |
| `grafana.adminUser` | `admin` | `GF_SECURITY_ADMIN_USER` |
| `grafana.adminPassword` | `admin` | `GF_SECURITY_ADMIN_PASSWORD` — change it |

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
`dcgmExporter.staticTargets` / `nodeExporter.staticTargets` (and the
`slurm.*Targets` values for the Slurm exporters). Static entries produce
the same `job` labels as the DaemonSet pods, so rules and dashboards make
no distinction; the `node` label comes from the entry and must be the
exact same string across every job scraping that machine — it is the join
key, and a mismatch shows up not as an error but as silently empty
dashboard panels.

## Validate

    make helm-validate      # helm lint + kubeconform -strict, after helm-sync

Not shipped by design: Ingress, NetworkPolicies, HA replicas,
prometheus-operator CRDs, and a Grafana PVC (Grafana is stateless here —
all datasources and dashboards are provisioned from ConfigMaps).
