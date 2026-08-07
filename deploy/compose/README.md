# Algalon Compose Deployment

Two stacks: **host** (storage + alerting + UI) and **worker** (exporters).
All rules/scrape/alerting content is bind-mounted from `monitoring/` —
edit there, restart the affected service.

## Host

    cd deploy/compose/host
    cp .env.example .env                       # adjust ports/retention
    # 1. targets:  see targets/README.md
    # 2. secrets:  see secrets/README.md
    docker compose up -d

Endpoints: Grafana :3000, VictoriaMetrics :8428, vmalert :8880,
Alertmanager :9093.

Change `GRAFANA_ADMIN_PASSWORD` from the default `admin` before exposing
Grafana beyond loopback.

## Worker (each GPU node)

    cd deploy/compose/worker
    cp .env.example .env
    docker compose up -d                       # dcgm-exporter + node-exporter
    docker compose --profile all-smi up -d     # + optional all-smi

Non-NVIDIA nodes: `docker compose up -d node-exporter` only.

`NODE_EXPORTER_PORT` changes the actual listening port (node-exporter runs
in host network mode), while `DCGM_EXPORTER_PORT` and `ALL_SMI_PORT` only
remap the host side of a published port. Either way, the host's target
files must use whichever port the host will reach.

## Smoke test (host, no GPU needed)

    docker compose up -d
    curl -s localhost:8880/api/v1/rules | grep -c '"name"'   # 6 rule groups
    curl -s localhost:9093/api/v2/alerts | grep Watchdog     # dead man's switch firing

`Watchdog` firing at Alertmanager proves the vmalert → Alertmanager path.
It is routed to a null receiver, so Slack stays quiet — configure your
real webhooks in `host/secrets/` and trigger a test alert to verify
Slack delivery end to end.

## Validation (CI-equivalent)

    make compose-validate alertmanager-validate dashboards-validate

## Dashboards

Provisioned automatically from `monitoring/dashboards/` into the Grafana
folder **Algalon** (see `host/grafana/provisioning/dashboards/algalon.yml`):

- **Alert Center** — firing alerts, severity counts, Watchdog pipeline
  check, exporter up matrix
- **GPU Fleet Overview** — fleet utilization stripes, temperature/memory
  per node
- **Node Health (Precursors)** — peer-band views (P5–P95 vs selected node)
  behind the node-precursor alert rules
- **Checkpoint & Storage I/O** — Save/Load phase bands, NFS throughput,
  RPC queue-time share
- **all-smi (Optional)** — populated only with the worker all-smi profile

Edit a dashboard JSON in `monitoring/dashboards/` and Grafana picks it up
within 30s (`updateIntervalSeconds`). UI edits are not persisted to git —
export and commit them.
