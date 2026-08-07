# Algalon

*The Comprehensive Hardware Observer — a GPU cluster alert center.*

Algalon is an alert center for large GPU training clusters. It collects
DCGM, OS and (optionally) cross-platform hardware metrics from every GPU
node, stores them in VictoriaMetrics, evaluates six curated alert rule
groups with vmalert, routes the result through Alertmanager to Slack, and
renders the whole picture in five Grafana dashboards. The rules are not
generic thresholds: they encode failure signatures observed on a real
504-GPU pre-training run, so an operator is told *which recovery action*
a fault requires — restart the job, reset the GPU, or reboot the node.

## Origin & Attribution

**This project originated from, and directly references, the Lablup
technical report *From Detection to Recovery: Operational Analysis on LLM
Pre-training with 504 GPUs* and its accompanying dataset repository.**
Algalon's alert rules, thresholds, severity mapping and dashboard layouts
encode the operational findings of that report — the XID classification
table, the row-remap degradation cases, the checkpoint I/O phases and the
NFS queue-time analysis all come from it. Rule files carry inline
citations back to the specific report section, table or figure they
implement.

Sources:

- Dataset repository:
  <https://huggingface.co/datasets/lablup/from-detection-to-recovery>
- Report (PDF):
  <https://huggingface.co/datasets/lablup/from-detection-to-recovery/blob/main/Lablup_Technical_Report_2026_ko.pdf>
- arXiv: <https://arxiv.org/abs/2605.09370>

Please cite this work as **"Lablup Inc. (2026)"** (inquiries:
<https://www.lablup.com/contact>).

<!-- markdownlint-disable MD013 -->
```bibtex
@misc{arxiv2605.09370,
  title        = {From Detection to Recovery: Operational Analysis on LLM Pre-training with 504 GPUs},
  author       = {{Lablup Inc.}},
  year         = {2026},
  eprint       = {2605.09370},
  archivePrefix = {arXiv},
  primaryClass = {cs.AI},
  note         = {Daemyung Kang, Eunjin Hwang, Hanjeong Lee, HyeokJin Kim, Hyunhoi Koo, Jeongkyu Shin, Jeongseok Kang, Jihyun Kang, Jinho Heo, Joongi Kim, Junbum Lee, Jungseung Yang, Kyujin Cho, and Youngsook Song},
  url          = {https://arxiv.org/abs/2605.09370}
}
```
<!-- markdownlint-enable MD013 -->

The optional cross-platform exporter Algalon integrates,
[all-smi](https://github.com/lablup/all-smi), is also a Lablup project.

## Architecture

```text
  GPU worker nodes (Docker Compose stacks or k3s DaemonSets)
  ┌───────────────┬───────────────┬──────────────────┐
  │ dcgm-exporter │ node-exporter │  all-smi (opt.)  │
  │         :9400 │         :9100 │            :9090 │
  └───────────────┴───────────────┴──────────────────┘
                         │ scrape (30s, file_sd targets)
                         ▼
                   ┌───────────┐
                   │  vmagent  │
                   └─────┬─────┘
                         │ remote write
                         ▼
             ┌───────────────────────┐      ┌───────────┐
             │ VictoriaMetrics :8428 │◀────▶│  Grafana  │
             └───────────┬───────────┘      │     :3000 │
                         │ query            └───────────┘
                         ▼
                ┌────────────────┐
                │ vmalert  :8880 │  6 rule groups
                └───────┬────────┘
                        │ fired alerts
                        ▼
              ┌─────────────────────┐
              │ Alertmanager  :9093 │──▶ Slack (critical / warning)
              └─────────────────────┘
```

`monitoring/` is the single source of truth for rules, dashboards, the
scrape config, the Alertmanager policy and the DCGM counter set. Compose
bind-mounts that directory; Helm packages it into ConfigMaps. Nothing is
ever copied into `deploy/`.

Alertmanager routes `severity="critical"` and `severity="warning"` to
separate Slack webhooks, groups by `alertname`/`node`, and inhibits
warnings for a node that is already paging critical.

## What Algalon watches

Six rule groups in `monitoring/rules/`, each grounded in the report:

- **`gpu-xid`** — XID error classification per report Table 3; severity
  *is* the required recovery action (31/43/94 restart the app,
  119/145/149 reset the GPU, 79 reboot the node), plus a catch-all for
  unclassified XIDs.
- **`gpu-ecc`** — row-remap degradation: uncorrectable remaps,
  `ROW_REMAP_FAILURE`, pending remaps, double-bit ECC — and a 24h
  *growth trend* rule, because report case gpu124 accumulated 254
  correctable remaps over 55 days with zero XIDs before the GPU vanished.
- **`gpu-health`** — thermal and clock-throttle health (report Table 8):
  GPU and memory temperature bands, sustained hardware throttling.
- **`node-precursor`** — peer-relative early signals from node_exporter
  (interrupt-rate collapse, runnable-process collapse, page-out bursts)
  per report §4.1.2, Figs 2–3. Warning-only and median-gated: finding F1
  found no single dominant precursor across the tagged failures.
- **`storage-nfs`** — checkpoint I/O phase detection (save/load bursts)
  and NFS/RPC queueing per report §4.2: 93.1% of WRITE latency was
  client-side queue time, so queue share is alerted directly. Requires
  node_exporter `--collector.mountstats`.
- **`meta`** — monitoring-of-monitoring: the `Watchdog` dead-man's
  switch, exporter-down, and DCGM metrics missing while the target is up.

Rule unit tests for these groups live in `tests/rules/`.

## Deployment

Three supported paths. All three consume the same `monitoring/` content.

| Path | Best for | Guide |
| --- | --- | --- |
| Local k3s cluster | On-prem GPU clusters (**recommended**) | [`deploy/k3s/README.md`](deploy/k3s/README.md) |
| Kubernetes / Helm | Existing clusters | [`deploy/helm/algalon/README.md`](deploy/helm/algalon/README.md) |
| Docker Compose | Single node, development, small fleets | [`deploy/compose/README.md`](deploy/compose/README.md) |

### Local k3s cluster (recommended for on-prem)

Training workloads keep running under Docker; a k3s agent runs
*alongside* Docker on each GPU node and schedules only the exporter
DaemonSets. The two container stacks share no state — k3s ships its own
embedded containerd — so the entire conflict surface is host networking,
which the shipped preflight script checks before anything is installed.

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
deliberate manual step documented in the runbook.

### Kubernetes / Helm

Exporters as DaemonSets on the GPU nodes, the host stack
(VictoriaMetrics, vmagent, vmalert, Alertmanager, Grafana) as
Deployments. `make helm-sync` must run before the first install — the
chart's `files/` directory is generated from `monitoring/` and is
git-ignored.

### Docker Compose

Two stacks: `deploy/compose/host` (storage, alerting, UI) and
`deploy/compose/worker` (exporters, one per GPU node). all-smi is opt-in
via `--profile all-smi`.

Slack webhook URLs are always injected as secrets or environment
variables. None are stored in git, and Alertmanager refuses to render
without them rather than shipping a silently broken notifier.

## Dashboards

Five Grafana dashboards in `monitoring/dashboards/`, auto-provisioned
into the **Algalon** folder:

- **Alert Center** — live `ALERTS` table: what is firing right now, by
  severity and node.
- **GPU Fleet Overview** — node × GPU heatmaps for utilization,
  temperature and ECC/remap state.
- **Node Health (Precursors)** — peer-band views of the precursor
  metrics, showing each node against the cluster median.
- **Checkpoint & Storage I/O** — checkpoint save/load phase bands from
  the `algalon:checkpoint_*` recording rules, plus the NFS queue-time
  breakdown.
- **all-smi (Optional)** — cross-platform hardware view; populated only
  when the all-smi profile is enabled.

## Development

Validation runs against the repo, not against a live cluster — every
target below is a container invocation of the real upstream validator.

| Target | Checks |
| --- | --- |
| `make rules-validate` | `vmalert -dryRun` on the rule files |
| `make rules-test` | Rule unit tests from `tests/rules/` |
| `make scrape-validate` | `vmagent -promscrape.config -dryRun` |
| `make alertmanager-validate` | `amtool check-config` |
| `make compose-validate` | Both stacks, with and without profiles |
| `make dashboards-validate` | Dashboard JSON conventions |
| `make helm-validate` | `helm lint` + `template \| kubeconform` |

Run all seven before committing:

```bash
make rules-validate rules-test scrape-validate alertmanager-validate \
  compose-validate dashboards-validate helm-validate
```

An end-to-end smoke test brings the whole pipeline up in a disposable
k3d cluster and asserts that rules are loaded, the watchdog reaches
Alertmanager, node scraping works and the GPU-only DaemonSets stay
unscheduled:

```bash
make e2e-k3d      # requires docker, k3d, helm, kubectl; takes a few minutes
```

CI runs the validation gate on every push and the k3d smoke test as a
follow-on job. Contributor conventions and the non-obvious constraints of
this codebase are documented in [`AGENTS.md`](AGENTS.md).

## License

Licensed under the Apache License, Version 2.0. See
[`LICENSE`](LICENSE) for the full text.

---

*Named after Algalon the Observer — watching over your GPUs with cosmic
precision.*
