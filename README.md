# Algalon

*The Comprehensive Hardware Observer — a GPU cluster alert center.*

**English** | [한국어](README.ko.md)

Algalon watches large GPU training clusters and tells operators not just
*that* something broke, but *which recovery action the failure actually
requires* — restart the job, reset the GPU, or reboot the node. It
collects DCGM, OS and (optionally) cross-platform hardware metrics from
every GPU node, stores them in VictoriaMetrics, evaluates seven curated
rule groups with vmalert, routes the results through Alertmanager
to Slack, and renders the whole picture in six Grafana dashboards.
Optional [Slurm integration](docs/slurm.md) adds an eighth rule group and
two more dashboards covering scheduler queue state and per-job accounting,
so an idle GPU can be named with the job and the user holding it. An
optional job-log pipeline pairs those dashboards with logs: a Slurm
epilog ships each finished job's stdout into VictoriaLogs, so the Job
Explorer shows a failed job's output right next to its metrics.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/architecture-dark.svg">
  <img alt="Algalon architecture" src="docs/images/architecture.svg">
</picture>

## Why Algalon exists

In 2026, Lablup published *From Detection to Recovery: Operational
Analysis on LLM Pre-training with 504 GPUs*
([arXiv:2605.09370](https://arxiv.org/abs/2605.09370)) — a technical
report that walks through 73 days of production logs from a 504-GPU
NVIDIA B200 cluster: which hardware failures actually occurred, what the
metrics looked like around each one, and how much of the recovery could
be automated.

Algalon began as an attempt to turn that analysis into something you can
run. The report's XID-to-recovery-action mapping, its row-remap
degradation cases, its checkpoint save/load phase thresholds and its NFS
queue-time findings are all encoded here as alert rules and dashboards,
and every rule file cites the section, table or figure it implements.
The report and its companion data live in the
[from-detection-to-recovery](https://huggingface.co/datasets/lablup/from-detection-to-recovery)
repository on Hugging Face, including the original
[report PDF](https://huggingface.co/datasets/lablup/from-detection-to-recovery/blob/main/Lablup_Technical_Report_2026_ko.pdf).
[all-smi](https://github.com/lablup/all-smi), the optional
cross-platform exporter Algalon can deploy, is another Lablup project.

If you build on this analysis in academic work, cite the report as
Lablup Inc. (2026) — inquiries go to
[lablup.com/contact](https://www.lablup.com/contact):

<details>
<summary>BibTeX</summary>

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

</details>

## Getting started

Pick a deployment path — all three consume the same `monitoring/`
content, so the rules and dashboards are identical everywhere:

| Path | Best for | Guide |
| --- | --- | --- |
| Local k3s cluster | On-prem GPU clusters (**recommended**) | [`deploy/k3s/`](deploy/k3s/README.md) |
| Kubernetes / Helm | Existing clusters | [`deploy/helm/algalon/`](deploy/helm/algalon/README.md) |
| Docker Compose | Single node, development, small fleets | [`deploy/compose/`](deploy/compose/README.md) |

The [deployment guide](docs/deployment.md) compares the three paths and
explains how the k3s path coexists with the host's training workloads
(Docker, Apptainer, or bare processes).

## Documentation

| Document | Contents |
| --- | --- |
| [Architecture](docs/architecture.md) | Component pipeline, the seven rule groups, the alerting policy, the eight dashboards |
| [Deployment](docs/deployment.md) | Choosing a path, k3s + Docker coexistence, secrets handling |
| [Development](docs/development.md) | Validation targets, rule unit tests, the k3d end-to-end smoke test |
| [Slurm integration](docs/slurm.md) | The two Slurm exporters, target registration, the Slurm alerts and dashboards, the `on(node)` join, the optional job log pipeline |

한국어 문서는 [`docs/ko/`](docs/ko/)에 있습니다.

Contributor conventions and the non-obvious constraints of this codebase
are documented in [`AGENTS.md`](AGENTS.md).

## License

Licensed under the Apache License, Version 2.0. See
[`LICENSE`](LICENSE) for the full text.

---

*Named after Algalon the Observer — watching over your GPUs with cosmic
precision.*
