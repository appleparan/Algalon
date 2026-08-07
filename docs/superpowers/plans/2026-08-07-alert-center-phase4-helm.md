# Alert Center Phase 4: Helm Chart Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A single Helm chart `deploy/helm/algalon` deploying worker DaemonSets (dcgm-exporter, node-exporter, optional all-smi) and the host stack (VictoriaMetrics, vmagent, vmalert, Alertmanager, Grafana), packaging `monitoring/` content via a sync step, validated by `helm lint` + kubeconform in Make/CI.

**Architecture:** Helm cannot template files outside the chart, so `make helm-sync` copies `monitoring/{rules,dashboards,alerting,exporters}` into the chart's gitignored `files/` dir before lint/template/package; ConfigMaps are built with `.Files.Glob`. On k8s, vmagent uses `kubernetes_sd` (pod role) instead of file_sd — the *contracts* survive: scrape jobs named exactly `dcgm`/`node`/`all-smi` and a `node` label on every series, driven by pod labels `algalon.io/scrape` + `algalon.io/job` and `__meta_kubernetes_pod_node_name`.

**Tech Stack:** Helm 3 (local binary), kubeconform via docker (`ghcr.io/yannh/kubeconform`), same pinned images as compose (VM stack v1.149.0, alertmanager v0.33.1, node-exporter v1.12.1, dcgm-exporter 4.6.0-4.8.3-ubi9, all-smi v0.25.0, grafana 13.1.3).

**Spec:** design spec §6.2. Contracts: Phase 1 rules/scrape (job names), Phase 2 alertmanager secret paths, Phase 3 dashboard conventions.

## Global Constraints

- `monitoring/` stays the single source: chart `files/` is GENERATED (gitignored), produced only by `make helm-sync` (fixed-path `rsync -a --delete` into `deploy/helm/algalon/files/` — scoped to that generated dir). Never commit `files/`; never hand-copy monitoring content into `templates/`.
- Chart identity: name `algalon`, `Chart.yaml` version `0.1.0`, appVersion `"0.4.0"`, apiVersion v2.
- Naming/labels via `_helpers.tpl`: resources named `{{ include "algalon.fullname" . }}-<component>`; common labels `app.kubernetes.io/name`, `app.kubernetes.io/instance`, `app.kubernetes.io/component`; scrape-targeted pods additionally carry `algalon.io/scrape: "true"` and `algalon.io/job: <dcgm|node|all-smi>` (exact values — alert rules filter on these job names).
- Alertmanager mounts the synced policy unchanged; the Slack secret exposes keys named exactly `slack_webhook_critical` and `slack_webhook_warning`, mounted at `/etc/alertmanager/secrets` (paths hard-coded in `monitoring/alerting/alertmanager.yml`).
- Every container image tag pinned via values (no `latest`); every workload sets resources requests (modest defaults) and readiness probes where the service has an HTTP port.
- Validation: `make helm-validate` = helm-sync → `helm lint` → `helm template | kubeconform -strict`. Both must pass before every commit, plus the Phase 1–3 gate (`rules-validate rules-test scrape-validate alertmanager-validate compose-validate dashboards-validate`) when non-helm files are touched.
- helm is installed locally; kubeconform runs via docker image `ghcr.io/yannh/kubeconform` (a local copy exists — check `docker image ls ghcr.io/yannh/kubeconform --format '{{.Tag}}'` and use that tag, else pull `v0.7.0`; record which).
- Work in worktree `.claude/worktrees/alert-center-phase4`, branch `feat/alert-center-phase4-helm`. Commit per task; never --no-verify.

## File Structure (this phase)

```
deploy/helm/algalon/
├─ Chart.yaml  values.yaml  .helmignore  README.md      # Task 1 (README Task 5)
├─ files/                                                # generated, gitignored (Task 1)
└─ templates/
   ├─ _helpers.tpl  NOTES.txt                            # Task 1
   ├─ worker-dcgm-daemonset.yaml                         # Task 2
   ├─ worker-dcgm-counters-configmap.yaml                # Task 2
   ├─ worker-node-exporter-daemonset.yaml                # Task 2
   ├─ worker-all-smi-daemonset.yaml                      # Task 2 (conditional)
   ├─ host-victoriametrics-{statefulset,service}.yaml    # Task 3
   ├─ host-vmagent-{deployment,configmap,rbac}.yaml      # Task 3
   ├─ host-vmalert-{deployment,service}.yaml             # Task 4
   ├─ host-rules-configmap.yaml                          # Task 4
   ├─ host-alertmanager-{deployment,service,configmap,secret}.yaml  # Task 4
   ├─ host-grafana-{deployment,service}.yaml             # Task 5
   └─ host-grafana-{provisioning,dashboards}-configmap.yaml         # Task 5
Makefile                       # Task 1: helm-sync, helm-validate
.gitignore                     # Task 1: files/ ignore
.github/workflows/monitoring-test.yml   # Task 1: step + deploy/helm path
IMPLEMENTATION_PLAN.md         # Task 5: Phase 4 done
```

---

### Task 1: Chart scaffold + sync + validation harness

**Files:**
- Create: `deploy/helm/algalon/{Chart.yaml,values.yaml,.helmignore}`, `templates/{_helpers.tpl,NOTES.txt}`
- Modify: `Makefile` (`helm-sync`, `helm-validate`; extend `.PHONY`), `.gitignore`, `.github/workflows/monitoring-test.yml`

**Interfaces:**
- Produces: `make helm-validate` (Tasks 2–5 gate on it); helper names `algalon.fullname`, `algalon.labels`, `algalon.selectorLabels` (component-parameterized); the complete `values.yaml` all later tasks consume.

- [ ] **Step 1: Makefile targets (test first)** — append (extend `.PHONY` with `helm-sync helm-validate`):

```make
helm-sync: ## Sync monitoring/ content into the Helm chart files/ dir (generated)
	@mkdir -p deploy/helm/algalon/files
	@rsync -a --delete monitoring/rules monitoring/dashboards monitoring/alerting monitoring/exporters deploy/helm/algalon/files/
	@echo "✅ helm files synced"

helm-validate: helm-sync ## Lint and schema-validate the Helm chart
	@helm lint deploy/helm/algalon
	@helm template algalon deploy/helm/algalon --set allSmi.enabled=true \
		| docker run --rm -i ghcr.io/yannh/kubeconform:$(KUBECONFORM_TAG) -strict -summary
	@echo "✅ helm chart valid"
```

with `KUBECONFORM_TAG := <tag determined per Global Constraints>` next to `VM_VERSION`.

Run: `make helm-validate` — Expected: FAIL (no Chart.yaml). RED confirmed.

- [ ] **Step 2: `.gitignore` append**

```gitignore
# Helm chart generated content (make helm-sync)
deploy/helm/algalon/files/
```

- [ ] **Step 3: `Chart.yaml`**

```yaml
apiVersion: v2
name: algalon
description: Multi-platform GPU cluster monitoring and alert center (DCGM + node-exporter + VictoriaMetrics + vmalert + Alertmanager + Grafana)
type: application
version: 0.1.0
appVersion: "0.4.0"
```

- [ ] **Step 4: `values.yaml`** (complete; later tasks consume these exact keys):

```yaml
# -- Worker exporters (DaemonSets) --
dcgmExporter:
  enabled: true
  image: nvcr.io/nvidia/k8s/dcgm-exporter:4.6.0-4.8.3-ubi9
  port: 9400
  # gpu-operator labels GPU nodes with nvidia.com/gpu.present
  nodeSelector:
    nvidia.com/gpu.present: "true"
  tolerations:
    - key: nvidia.com/gpu
      operator: Exists
  runtimeClassName: ""
  resources:
    requests: {cpu: 100m, memory: 256Mi}

nodeExporter:
  enabled: true
  image: prom/node-exporter:v1.12.1
  port: 9100
  tolerations:
    - operator: Exists
  resources:
    requests: {cpu: 50m, memory: 64Mi}

allSmi:
  enabled: false
  image: ghcr.io/inureyes/all-smi:v0.25.0
  port: 9090
  interval: 5
  nodeSelector:
    nvidia.com/gpu.present: "true"
  tolerations:
    - key: nvidia.com/gpu
      operator: Exists
  resources:
    requests: {cpu: 100m, memory: 128Mi}

# -- Host stack --
host:
  enabled: true

victoriametrics:
  image: victoriametrics/victoria-metrics:v1.149.0
  retentionMonths: 3
  storage:
    size: 50Gi
    storageClassName: ""
  resources:
    requests: {cpu: 500m, memory: 1Gi}

vmagent:
  image: victoriametrics/vmagent:v1.149.0
  scrapeInterval: 30s
  resources:
    requests: {cpu: 200m, memory: 256Mi}

vmalert:
  image: victoriametrics/vmalert:v1.149.0
  evaluationInterval: 30s
  resources:
    requests: {cpu: 100m, memory: 128Mi}

alertmanager:
  image: prom/alertmanager:v0.33.1
  resources:
    requests: {cpu: 50m, memory: 64Mi}
  slack:
    # Either reference an existing Secret with keys
    # slack_webhook_critical / slack_webhook_warning...
    existingSecret: ""
    # ...or set URLs here and the chart creates the Secret (not recommended
    # for GitOps — values files end up in git).
    criticalUrl: ""
    warningUrl: ""

grafana:
  image: grafana/grafana:13.1.3
  adminUser: admin
  adminPassword: admin
  resources:
    requests: {cpu: 100m, memory: 256Mi}
```

- [ ] **Step 5: `templates/_helpers.tpl`** — define `algalon.fullname` (release-name-based, truncated 63), `algalon.labels` (name/instance/managed-by + `app.kubernetes.io/component` from a passed dict), `algalon.selectorLabels` (name/instance/component). Also `templates/NOTES.txt` (one paragraph: endpoints and the secret requirement when `host.enabled`). `.helmignore`: standard defaults.

- [ ] **Step 6: GREEN + CI**

Run: `make helm-validate` — Expected: PASS (lint OK; template renders only NOTES → kubeconform sees empty input, exits 0).
Contingency: if kubeconform errors on empty stdin, append `--set host.enabled=true` output check later; for now allow the summary to show 0 resources.
CI: add `- 'deploy/helm/**'` to both `paths:` lists and step `- name: Validate helm chart` / `run: make helm-validate` after dashboards. Note: ubuntu-latest runners ship helm.

- [ ] **Step 7: Commit**

```bash
git add deploy/helm/algalon .gitignore Makefile .github/workflows/monitoring-test.yml
git commit -m "feat: Scaffold algalon Helm chart with sync and validation harness"
```

---

### Task 2: Worker DaemonSets

**Files:** Create `templates/worker-dcgm-daemonset.yaml`, `templates/worker-dcgm-counters-configmap.yaml`, `templates/worker-node-exporter-daemonset.yaml`, `templates/worker-all-smi-daemonset.yaml`.

**Interfaces:** Pod labels `algalon.io/scrape: "true"` + `algalon.io/job: dcgm|node|all-smi` (Task 3's vmagent relabeling consumes them). Container ports: dcgm 9400, node-exporter 9100 (hostNetwork), all-smi 9090.

- [ ] **Step 1: Author the three DaemonSets + ConfigMap** to these specs (all gated on their `.enabled`; all use helpers for names/labels and add the two `algalon.io/*` pod labels):

1. **dcgm** — image/nodeSelector/tolerations/resources from `.Values.dcgmExporter`; optional `runtimeClassName` (if non-empty); env `NVIDIA_VISIBLE_DEVICES=all`; `securityContext.capabilities.add: [SYS_ADMIN]`; args `["-f", "/etc/dcgm-exporter/counters.csv"]`; mounts ConfigMap `...-dcgm-counters` at `/etc/dcgm-exporter/counters.csv` (subPath `counters.csv`); containerPort 9400 named `metrics`.
2. **dcgm-counters ConfigMap** — data key `counters.csv` from `.Files.Get "files/exporters/dcgm-counters.csv"` (synced).
3. **node-exporter** — `hostNetwork: true`, `hostPID: true`, `dnsPolicy: ClusterFirstWithHostNet`; tolerations from values (default: run everywhere); mounts `/proc→/host/proc`, `/sys→/host/sys`, `/→/rootfs` all read-only; args exactly as compose: `--path.procfs=/host/proc --path.sysfs=/host/sys --path.rootfs=/rootfs --collector.mountstats --web.listen-address=:9100`; containerPort 9100.
4. **all-smi** — mirrors dcgm (runtime env/caps/nodeSelector), args `["api", "--port", "9090", "--interval", "<.Values.allSmi.interval>", "--processes"]`, containerPort 9090.

- [ ] **Step 2: Validate with assertions**

`make helm-validate` green, then assert the contracts:

```bash
helm template algalon deploy/helm/algalon --set allSmi.enabled=true > /tmp/algalon-render.yaml
grep -c 'algalon.io/job: dcgm' /tmp/algalon-render.yaml      # >=1
grep -c 'algalon.io/job: node' /tmp/algalon-render.yaml      # >=1
grep -c 'algalon.io/job: all-smi' /tmp/algalon-render.yaml   # >=1
grep -c 'collector.mountstats' /tmp/algalon-render.yaml      # >=1
helm template algalon deploy/helm/algalon | grep -c 'all-smi' # 0 (default off)
```

(Adjust only eval commands, never the specs, if a grep needs anchoring.)

- [ ] **Step 3: Commit**

```bash
git add deploy/helm/algalon/templates/
git commit -m "feat: Add worker DaemonSets to Helm chart"
```

---

### Task 3: VictoriaMetrics + vmagent (kubernetes_sd)

**Files:** Create `templates/host-victoriametrics-statefulset.yaml`, `host-victoriametrics-service.yaml`, `host-vmagent-deployment.yaml`, `host-vmagent-configmap.yaml`, `host-vmagent-rbac.yaml`. All gated on `.Values.host.enabled`.

- [ ] **Step 1: Author** to these specs:

1. **VM StatefulSet** — single replica, args `--storageDataPath=/storage --retentionPeriod=<retentionMonths>`, volumeClaimTemplate (`size`, optional `storageClassName`), containerPort 8428, readinessProbe HTTP `/health` on 8428. **Service** `...-victoriametrics` port 8428 (Tasks 4–5 reference DNS `<fullname>-victoriametrics:8428`).
2. **vmagent RBAC** — ServiceAccount + ClusterRole (`pods`,`nodes`: get/list/watch, apiGroups [""]) + ClusterRoleBinding.
3. **vmagent ConfigMap** — key `prometheus.yml`, templated scrape config: `global.scrape_interval: {{ .Values.vmagent.scrapeInterval }}`; ONE `kubernetes_sd_configs: [{role: pod}]` job with relabel_configs: keep pods where `__meta_kubernetes_pod_label_algalon_io_scrape == "true"`; set `job` from `__meta_kubernetes_pod_label_algalon_io_job`; set `node` from `__meta_kubernetes_pod_node_name`; keep only the container port named `metrics` (`__meta_kubernetes_pod_container_port_name == "metrics"` — give ALL exporter ports that name in Task 2). Job must land as exactly `dcgm`/`node`/`all-smi` per pod.
4. **vmagent Deployment** — mounts the ConfigMap; args `--promscrape.config=/etc/vmagent/prometheus.yml --remoteWrite.url=http://<fullname>-victoriametrics:8428/api/v1/write`; serviceAccountName from RBAC.

- [ ] **Step 2: Validate**

`make helm-validate` green; assertions on rendered output: `source_labels.*algalon_io_job`, `target_label: node`, `target_label: job` present; `remoteWrite.url` points at the VM service name.

- [ ] **Step 3: Commit**

```bash
git add deploy/helm/algalon/templates/
git commit -m "feat: Add VictoriaMetrics and vmagent with kubernetes_sd to Helm chart"
```

---

### Task 4: vmalert + Alertmanager

**Files:** Create `templates/host-rules-configmap.yaml`, `host-vmalert-deployment.yaml`, `host-vmalert-service.yaml`, `host-alertmanager-deployment.yaml`, `host-alertmanager-service.yaml`, `host-alertmanager-configmap.yaml`, `host-alertmanager-secret.yaml`. Gated on `.Values.host.enabled`.

- [ ] **Step 1: Author** to these specs:

1. **rules ConfigMap** — one key per file via `(.Files.Glob "files/rules/*.yml")`, content verbatim (`.AsConfig` or range+`indent`).
2. **vmalert Deployment** — mounts rules CM at `/rules`; args exactly: `--rule=/rules/*.yml --datasource.url=http://<fullname>-victoriametrics:8428 --remoteWrite.url=... --remoteRead.url=... --notifier.url=http://<fullname>-alertmanager:9093 --evaluationInterval={{ .Values.vmalert.evaluationInterval }} --httpListenAddr=:8880`; port 8880 + Service.
3. **alertmanager ConfigMap** — key `alertmanager.yml` from `.Files.Get "files/alerting/alertmanager.yml"` VERBATIM (no templating of its contents).
4. **alertmanager Secret** — rendered only when `alertmanager.slack.existingSecret` is empty AND both URLs set; keys `slack_webhook_critical`, `slack_webhook_warning` (stringData). If existingSecret empty and URLs empty: `fail` with a clear message (`required`-style) so installs never silently ship a broken notifier.
5. **alertmanager Deployment** — mounts config CM at `/etc/alertmanager/alertmanager.yml` (subPath) and the Secret (existingSecret name or the chart's) at `/etc/alertmanager/secrets`; args `--config.file=/etc/alertmanager/alertmanager.yml --storage.path=/alertmanager` with emptyDir at `/alertmanager`; port 9093 + Service; readinessProbe HTTP `/-/ready`.

- [ ] **Step 2: Validate**

`make helm-validate` must now pass Slack values — update the Makefile `helm template`/`helm lint` invocations (both) to add `--set alertmanager.slack.criticalUrl=https://hooks.example/x --set alertmanager.slack.warningUrl=https://hooks.example/y` (record this Makefile change in the commit). Assertions: rendered rules CM contains `gpu-xid` group; alertmanager.yml appears verbatim (`api_url_file: /etc/alertmanager/secrets/slack_webhook_critical`); `helm template` WITHOUT slack values FAILS with the clear error.

- [ ] **Step 3: Commit**

```bash
git add deploy/helm/algalon/templates/ Makefile
git commit -m "feat: Add vmalert and Alertmanager to Helm chart"
```

---

### Task 5: Grafana + chart README + status

**Files:** Create `templates/host-grafana-deployment.yaml`, `host-grafana-service.yaml`, `host-grafana-provisioning-configmap.yaml`, `host-grafana-dashboards-configmap.yaml`, `deploy/helm/algalon/README.md`. Modify `IMPLEMENTATION_PLAN.md`.

- [ ] **Step 1: Author** to these specs:

1. **provisioning ConfigMap** — two keys: `datasources.yml` (Prometheus type, url `http://<fullname>-victoriametrics:8428`, isDefault, editable false) and `dashboards.yml` (file provider `algalon`, folder `Algalon`, path `/var/lib/grafana/dashboards/algalon`, same shape as the compose provider).
2. **dashboards ConfigMap** — all five JSONs via `.Files.Glob "files/dashboards/*.json"`.
3. **Grafana Deployment** — env GF_SECURITY_ADMIN_USER/PASSWORD from values; mounts: provisioning CM keys into `/etc/grafana/provisioning/datasources/datasources.yml` and `/etc/grafana/provisioning/dashboards/dashboards.yml` (subPath each), dashboards CM at `/var/lib/grafana/dashboards/algalon`, emptyDir at `/var/lib/grafana`; port 3000 + Service; readinessProbe `/api/health`.
4. **Chart README** — install quickstart (`make helm-sync` first!), the Slack secret requirement with a `kubectl create secret generic` example, values table for the keys in Task 1, worker-only install (`--set host.enabled=false`), all-smi enable, and the "files/ is generated — run make helm-sync after editing monitoring/" rule.

- [ ] **Step 2: Full validation + wrap-up**

`make helm-validate` green; full gate green; `helm template` assertion: dashboards CM contains `algalon-alerts`. Update `IMPLEMENTATION_PLAN.md`: Phase 4 row `✅ done` with this plan's path.

- [ ] **Step 3: Commit**

```bash
git add deploy/helm/algalon IMPLEMENTATION_PLAN.md
git commit -m "feat: Add Grafana and chart documentation to Helm chart"
```

---

## Self-Review Notes

- Spec §6.2 coverage: worker DaemonSets with GPU nodeSelector/tolerations (T2), host Deployments/StatefulSet+PVC (T3–T5), ConfigMaps generated from `monitoring/` (sync mechanism, T1; consumed T2/T4/T5), values control for retention/interval/secret ref/all-smi toggle (T1), `helm lint`+kubeconform gate (T1, CI).
- Contract preservation: job names + `node` label via pod-label relabeling (T3) — same names the Phase 1 rules filter on; alertmanager secret key names = the exact `api_url_file` paths; dashboards/rules/alerting shipped byte-verbatim from `monitoring/` via sync.
- Judgment calls: `files/` generated+gitignored over committed copies (single source wins; cost: `helm-sync` required before packaging — enforced as a Make dependency); kubernetes_sd over file_sd on k8s (file_sd would need manual pod IPs); port-name `metrics` keep-filter avoids scraping non-metric ports; secret `fail` guard over silent broken notifier; scoped `rsync --delete` into the generated dir only.
- Not in scope: NetworkPolicies, Ingress, HA replicas, PodMonitors/ServiceMonitors (no prometheus-operator dependency by design).
