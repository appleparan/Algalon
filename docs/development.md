# Development

**English** | [한국어](ko/development.md)

Everything validates against the repository, not against a live
cluster — each Make target below is a container invocation of the real
upstream validator, so CI and your laptop produce identical results and
no GPU is required.

## Validation targets

| Target | Checks |
| --- | --- |
| `make rules-validate` | `vmalert -dryRun` on the rule files |
| `make rules-test` | Rule unit tests from `tests/rules/` |
| `make scrape-validate` | `vmagent -promscrape.config -dryRun` |
| `make alertmanager-validate` | `amtool check-config` |
| `make compose-validate` | Both stacks, with and without profiles |
| `make dashboards-validate` | Dashboard JSON conventions |
| `make helm-validate` | `helm lint` + `helm template \| kubeconform` |

Run the full gate before committing:

```bash
make rules-validate rules-test scrape-validate alertmanager-validate \
  compose-validate dashboards-validate helm-validate
```

## Rule unit tests

The vmalert rule groups are tested with `vmalert-tool unittest`
(promtool-compatible test files in `tests/rules/`). Tests feed synthetic
series into each rule and assert both the positive case — the alert
fires with the exact labels and summary — and the negative case: healthy
peers stay silent. When you add a rule, add both cases; a test that can
never fail is worse than no test.

## End-to-end smoke test

`make e2e-k3d` brings the entire pipeline up in a disposable k3d
cluster and asserts four things: the seven core rule groups are loaded in
vmalert, the Watchdog alert reaches Alertmanager (proving the alerting
path end to end), node scraping through Kubernetes service discovery
works, and the GPU-only DaemonSets stay correctly unscheduled on a
GPU-less node.

```bash
make e2e-k3d      # requires docker, k3d, helm, kubectl; takes a few minutes
```

The cluster is deleted on exit, pass or fail.

## CI

Every push runs the validation gate; the k3d smoke test runs as a
follow-on job. Contributor conventions and the non-obvious constraints
of this codebase are documented in [`AGENTS.md`](../AGENTS.md).
