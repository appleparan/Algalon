# Alert Center Phase 2: Compose Stacks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deployable Docker Compose stacks — worker (dcgm-exporter + node-exporter, all-smi profile) and host (VictoriaMetrics + vmagent + vmalert + Alertmanager + Grafana) — consuming `monitoring/` as the single source, plus the Alertmanager routing policy and validation targets/CI.

**Architecture:** `monitoring/alerting/alertmanager.yml` is the routing policy single source (severity-split Slack via `api_url_file` secrets, Watchdog blackhole, same-node inhibition). Compose files bind-mount `monitoring/` read-only via relative paths. Validation is config-level (`docker compose config`, `amtool check-config`) so CI needs no GPU and starts no containers.

**Tech Stack:** Docker Compose v2; images pinned: victoriametrics/{victoria-metrics,vmagent,vmalert}:v1.149.0, prom/alertmanager:v0.33.1, prom/node-exporter:v1.12.1, nvcr.io/nvidia/k8s/dcgm-exporter:4.6.0-4.8.3-ubi9, ghcr.io/inureyes/all-smi:v0.25.0, grafana/grafana:13.1.3 (Grafana docker tags have NO `v` prefix).

**Spec:** `docs/superpowers/specs/2026-08-07-alert-center-design.md` §5 (Alertmanager policy), §6.1 (compose). Carry-forward notes: `IMPLEMENTATION_PLAN.md` §Notes.

## Global Constraints

- Never copy rules/dashboards/scrape/alerting files into `deploy/` — bind-mount or reference `monitoring/` (relative paths `../../../monitoring/...` from the compose file's directory).
- No secrets in git: Slack webhooks are files under `deploy/compose/host/secrets/` (gitignored), consumed via Alertmanager `api_url_file`.
- Job-name and label contracts from Phase 1: scrape jobs `dcgm`/`node`/`all-smi`; file_sd target entries carry a `node` label; Alertmanager groups and inhibits on `node`.
- Alertmanager policy (spec §5 + Phase 1 notes): route by `severity` (critical/warning receivers), `group_by: [alertname, node]`, Watchdog → blackhole receiver, inhibition critical→warning on same node. `repeat_interval: 4h` absorbs the ~10m latching of delta-window alerts (GpuUncorrectableRowRemap).
- Every `${VAR}` in compose files must have a `:-default` so `docker compose config` passes without a `.env`.
- Worker GPU access uses `runtime: nvidia` + `NVIDIA_VISIBLE_DEVICES=all` (matches legacy repo convention; requires nvidia-container-toolkit).
- node-exporter MUST run with `network_mode: host`, `pid: host`, and `--collector.mountstats` — without mountstats the entire storage-nfs rule group is inert.
- All work in worktree `.claude/worktrees/alert-center-phase2`, branch `feat/alert-center-phase2-compose`. Commit per task; never --no-verify. Run `make alertmanager-validate compose-validate` (once they exist) plus `make rules-validate rules-test scrape-validate` before each commit that could affect them.

## File Structure (this phase)

```
monitoring/alerting/alertmanager.yml            # Task 1 — routing policy single source
deploy/compose/
├─ README.md                                    # Task 4 — quickstart + smoke test
├─ worker/
│  ├─ docker-compose.yml                        # Task 2
│  └─ .env.example                              # Task 2
└─ host/
   ├─ docker-compose.yml                        # Task 3
   ├─ .env.example                              # Task 3
   ├─ grafana/provisioning/datasources/victoriametrics.yml  # Task 3
   ├─ targets/README.md                         # Task 3 (real *.yml gitignored)
   └─ secrets/README.md                         # Task 3 (contents gitignored)
Makefile                                        # Tasks 1–3: alertmanager-validate, compose-validate
.github/workflows/monitoring-test.yml           # Task 4: new steps + paths
.gitignore                                      # Task 4: secrets/targets ignores
IMPLEMENTATION_PLAN.md                          # Task 4: Phase 2 done + Phase 5 CI-deferral note
```

---

### Task 1: Alertmanager routing policy + validation target

**Files:**
- Create: `monitoring/alerting/alertmanager.yml`
- Modify: `Makefile` (extend `.PHONY`; add `alertmanager-validate` after `scrape-validate`)

**Interfaces:**
- Produces: `make alertmanager-validate`; receiver names `blackhole`/`slack-critical`/`slack-warning`; secret paths `/etc/alertmanager/secrets/slack_webhook_critical` and `.../slack_webhook_warning` (Task 3's host compose mounts `./secrets` at `/etc/alertmanager/secrets`).

- [ ] **Step 1: Add the validation target (test first)**

Append to `Makefile` (and add `alertmanager-validate` to the `.PHONY` line):

```make
alertmanager-validate: ## Validate Alertmanager routing config
	@docker run --rm -v $(CURDIR)/monitoring/alerting:/config:ro \
		--entrypoint /bin/amtool prom/alertmanager:v0.33.1 \
		check-config /config/alertmanager.yml
	@echo "✅ alertmanager config valid"
```

- [ ] **Step 2: Run to verify it fails**

Run: `make alertmanager-validate`
Expected: FAIL — `/config/alertmanager.yml` does not exist.

- [ ] **Step 3: Write `monitoring/alerting/alertmanager.yml`**

```yaml
# Alertmanager routing policy (spec §5; Phase 1 carry-forward notes).
# Single source: compose bind-mounts this file, Helm packages it.
# Slack webhooks arrive as FILES (api_url_file) mounted from the
# deployment's secrets dir — never inline URLs in this file.
# repeat_interval 4h absorbs delta-window latching (GpuUncorrectableRowRemap
# re-fires for ~10m per increase; grouping must not page repeatedly).
route:
  receiver: slack-warning
  group_by: ['alertname', 'node']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  routes:
    # Dead man's switch: always firing by design; never notify a human.
    - matchers:
        - alertname="Watchdog"
      receiver: blackhole
    - matchers:
        - severity="critical"
      receiver: slack-critical

inhibit_rules:
  # A critical alert on a node suppresses warnings on the same node —
  # the page already covers it (spec §5). Alerts without a node label
  # (Watchdog, cluster-wide) are not affected: empty label must match on
  # both sides for inhibition to apply.
  - source_matchers:
      - severity="critical"
    target_matchers:
      - severity="warning"
    equal: ['node']

receivers:
  - name: blackhole

  - name: slack-critical
    slack_configs:
      - api_url_file: /etc/alertmanager/secrets/slack_webhook_critical
        send_resolved: true
        title: '[CRITICAL] {{ .GroupLabels.alertname }} {{ if .GroupLabels.node }}on {{ .GroupLabels.node }}{{ end }}'
        text: '{{ range .Alerts }}{{ .Annotations.summary }}{{ "\n" }}{{ end }}'

  - name: slack-warning
    slack_configs:
      - api_url_file: /etc/alertmanager/secrets/slack_webhook_warning
        send_resolved: true
        title: '[WARN] {{ .GroupLabels.alertname }} {{ if .GroupLabels.node }}on {{ .GroupLabels.node }}{{ end }}'
        text: '{{ range .Alerts }}{{ .Annotations.summary }}{{ "\n" }}{{ end }}'
```

- [ ] **Step 4: Run to verify it passes**

Run: `make alertmanager-validate`
Expected: PASS (`Checking '/config/alertmanager.yml'  SUCCESS`).
Contingency: if amtool errors because the `api_url_file` paths do not exist at check time, record the exact error and change nothing else — instead add `mkdir -p /tmp` style dummy handling is NOT allowed; report BLOCKED with the error text (the controller will decide; amtool is expected to validate paths lazily).

- [ ] **Step 5: Commit**

```bash
git add monitoring/alerting/alertmanager.yml Makefile
git commit -m "feat: Add Alertmanager routing policy and validation target"
```

---

### Task 2: Worker compose stack

**Files:**
- Create: `deploy/compose/worker/docker-compose.yml`
- Create: `deploy/compose/worker/.env.example`
- Modify: `Makefile` (add `compose-validate` covering the worker stack; extend `.PHONY`)

**Interfaces:**
- Consumes: `monitoring/exporters/dcgm-counters.csv` (Phase 1).
- Produces: worker endpoints scraped by the host — dcgm :9400, node-exporter :9100, all-smi :9090 (profile `all-smi`). `make compose-validate` (Task 3 extends it with the host stack).

- [ ] **Step 1: Add the validation target (test first)**

Append to `Makefile` (add `compose-validate` to `.PHONY`):

```make
compose-validate: ## Validate compose stacks
	@docker compose -f deploy/compose/worker/docker-compose.yml config -q
	@docker compose -f deploy/compose/worker/docker-compose.yml --profile all-smi config -q
	@echo "✅ compose stacks valid"
```

- [ ] **Step 2: Run to verify it fails**

Run: `make compose-validate`
Expected: FAIL — worker compose file does not exist.

- [ ] **Step 3: Write `deploy/compose/worker/docker-compose.yml`**

```yaml
# Algalon worker stack: exporters scraped remotely by the host's vmagent.
# GPU containers use the NVIDIA container runtime (nvidia-container-toolkit).
# Non-NVIDIA nodes: run only node-exporter (and optionally all-smi):
#   docker compose up -d node-exporter
services:
  # Failure-detection backbone: XID, ECC, remapped rows, thermal (spec §3).
  # Publishes exactly the fields listed in monitoring/exporters/dcgm-counters.csv.
  dcgm-exporter:
    image: nvcr.io/nvidia/k8s/dcgm-exporter:4.6.0-4.8.3-ubi9
    container_name: algalon-dcgm-exporter
    restart: unless-stopped
    runtime: nvidia
    environment:
      - NVIDIA_VISIBLE_DEVICES=all
    cap_add:
      - SYS_ADMIN
    ports:
      - "${DCGM_EXPORTER_PORT:-9400}:9400"
    volumes:
      - ../../../monitoring/exporters/dcgm-counters.csv:/etc/dcgm-exporter/counters.csv:ro
    command: ["-f", "/etc/dcgm-exporter/counters.csv"]

  # Precursor layer: interrupts, runnable procs, vmstat, NFS mountstats
  # (spec §3). host network+pid so /proc reflects the node, not the
  # container. --collector.mountstats is REQUIRED — without it the entire
  # storage-nfs rule group is silently inert.
  node-exporter:
    image: prom/node-exporter:v1.12.1
    container_name: algalon-node-exporter
    restart: unless-stopped
    network_mode: host
    pid: host
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--path.rootfs=/rootfs'
      - '--collector.mountstats'
      - '--web.listen-address=:${NODE_EXPORTER_PORT:-9100}'

  # Optional cross-platform / process-level exporter (spec §2: opt-in
  # profile, pinned tag — never latest).
  all-smi:
    profiles: ["all-smi"]
    image: ghcr.io/inureyes/all-smi:v0.25.0
    container_name: algalon-all-smi
    restart: unless-stopped
    runtime: nvidia
    environment:
      - NVIDIA_VISIBLE_DEVICES=all
    cap_add:
      - SYS_ADMIN
    ports:
      - "${ALL_SMI_PORT:-9090}:9090"
    command: ["api", "--port", "9090", "--interval", "${ALL_SMI_INTERVAL:-5}", "--processes"]
```

- [ ] **Step 4: Write `deploy/compose/worker/.env.example`**

```bash
# Algalon worker stack configuration. Copy to .env and adjust.

# Exporter ports (host side). Must match the host's target files
# (deploy/compose/host/targets/*.yml).
DCGM_EXPORTER_PORT=9400
NODE_EXPORTER_PORT=9100

# all-smi profile only (docker compose --profile all-smi up -d)
ALL_SMI_PORT=9090
ALL_SMI_INTERVAL=5
```

- [ ] **Step 5: Run to verify it passes**

Run: `make compose-validate`
Expected: PASS for both invocations (with and without the all-smi profile).
Note: `docker compose config` does not require the nvidia runtime to be installed — it only validates structure.

- [ ] **Step 6: Commit**

```bash
git add deploy/compose/worker/ Makefile
git commit -m "feat: Add worker compose stack (dcgm-exporter, node-exporter, all-smi profile)"
```

---

### Task 3: Host compose stack

**Files:**
- Create: `deploy/compose/host/docker-compose.yml`
- Create: `deploy/compose/host/.env.example`
- Create: `deploy/compose/host/grafana/provisioning/datasources/victoriametrics.yml`
- Create: `deploy/compose/host/targets/README.md`
- Create: `deploy/compose/host/secrets/README.md`
- Modify: `Makefile` (extend `compose-validate` with the host stack)

**Interfaces:**
- Consumes: `monitoring/scrape/prometheus.yml`, `monitoring/rules/`, `monitoring/alerting/alertmanager.yml` (Task 1 receiver secret paths), target `.example` templates.
- Produces: host services on ports VM 8428, vmalert 8880, Alertmanager 9093, Grafana 3000.

- [ ] **Step 1: Extend the validation target (test first)**

In the `Makefile` `compose-validate` target, add the host line before the echo:

```make
	@docker compose -f deploy/compose/host/docker-compose.yml config -q
```

Run: `make compose-validate` — Expected: FAIL (host compose file missing).

- [ ] **Step 2: Write `deploy/compose/host/docker-compose.yml`**

```yaml
# Algalon host stack: storage, scraping, rule evaluation, routing, UI.
# All monitoring content (scrape config, rules, alerting policy) is
# bind-mounted read-only from monitoring/ — the single source of truth.
services:
  victoriametrics:
    image: victoriametrics/victoria-metrics:v1.149.0
    container_name: algalon-victoriametrics
    restart: unless-stopped
    ports:
      - "${VM_PORT:-8428}:8428"
    volumes:
      - vmdata:/storage
    command:
      - '--storageDataPath=/storage'
      - '--retentionPeriod=${VM_RETENTION_MONTHS:-3}'
    networks:
      - monitoring

  # Scrapes workers listed in ./targets/*.yml (copy from
  # monitoring/scrape/targets/*.yml.example) and writes to VictoriaMetrics.
  vmagent:
    image: victoriametrics/vmagent:v1.149.0
    container_name: algalon-vmagent
    restart: unless-stopped
    depends_on:
      - victoriametrics
    volumes:
      - ../../../monitoring/scrape/prometheus.yml:/etc/vmagent/prometheus.yml:ro
      - ./targets:/etc/vmagent/targets:ro
    command:
      - '--promscrape.config=/etc/vmagent/prometheus.yml'
      - '--remoteWrite.url=http://victoriametrics:8428/api/v1/write'
    networks:
      - monitoring

  # Evaluates monitoring/rules/*.yml every 30s; recording rules are written
  # back via remoteWrite; alert state is restored via remoteRead.
  vmalert:
    image: victoriametrics/vmalert:v1.149.0
    container_name: algalon-vmalert
    restart: unless-stopped
    depends_on:
      - victoriametrics
      - alertmanager
    ports:
      - "${VMALERT_PORT:-8880}:8880"
    volumes:
      - ../../../monitoring/rules:/rules:ro
    command:
      - '--rule=/rules/*.yml'
      - '--datasource.url=http://victoriametrics:8428'
      - '--remoteWrite.url=http://victoriametrics:8428'
      - '--remoteRead.url=http://victoriametrics:8428'
      - '--notifier.url=http://alertmanager:9093'
      - '--evaluationInterval=30s'
      - '--httpListenAddr=:8880'
    networks:
      - monitoring

  # Routing policy from monitoring/alerting/alertmanager.yml; Slack webhook
  # FILES go in ./secrets/ (gitignored) — see secrets/README.md.
  alertmanager:
    image: prom/alertmanager:v0.33.1
    container_name: algalon-alertmanager
    restart: unless-stopped
    ports:
      - "${ALERTMANAGER_PORT:-9093}:9093"
    volumes:
      - ../../../monitoring/alerting/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro
      - ./secrets:/etc/alertmanager/secrets:ro
      - amdata:/alertmanager
    command:
      - '--config.file=/etc/alertmanager/alertmanager.yml'
      - '--storage.path=/alertmanager'
    networks:
      - monitoring

  grafana:
    image: grafana/grafana:13.1.3
    container_name: algalon-grafana
    restart: unless-stopped
    ports:
      - "${GRAFANA_PORT:-3000}:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=${GRAFANA_ADMIN_USER:-admin}
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD:-admin}
    volumes:
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
      - grafanadata:/var/lib/grafana
    networks:
      - monitoring

volumes:
  vmdata:
  amdata:
  grafanadata:

networks:
  monitoring:
    driver: bridge
```

- [ ] **Step 3: Write `deploy/compose/host/.env.example`**

```bash
# Algalon host stack configuration. Copy to .env and adjust.

VM_PORT=8428
VM_RETENTION_MONTHS=3
VMALERT_PORT=8880
ALERTMANAGER_PORT=9093
GRAFANA_PORT=3000
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=admin
```

- [ ] **Step 4: Write `deploy/compose/host/grafana/provisioning/datasources/victoriametrics.yml`**

```yaml
apiVersion: 1

datasources:
  - name: VictoriaMetrics
    type: prometheus
    access: proxy
    url: http://victoriametrics:8428
    isDefault: true
    editable: false
```

- [ ] **Step 5: Write the two READMEs**

`deploy/compose/host/targets/README.md`:

```markdown
# Scrape targets

Copy the templates and fill in your worker hostnames (one file per job;
file names are fixed — vmagent watches exactly these):

    cp ../../../../monitoring/scrape/targets/dcgm-targets.yml.example dcgm-targets.yml
    cp ../../../../monitoring/scrape/targets/node-targets.yml.example node-targets.yml
    cp ../../../../monitoring/scrape/targets/all-smi-targets.yml.example all-smi-targets.yml

Every entry must carry a `node` label — Alertmanager groups and inhibits
on it. Real `*.yml` files here are gitignored (deployment-specific).
Leave `all-smi-targets.yml` as an empty list (`[]`) if no worker runs the
all-smi profile.
```

`deploy/compose/host/secrets/README.md`:

```markdown
# Alertmanager secrets

Put one Slack incoming-webhook URL per file (file content = the bare URL):

    slack_webhook_critical
    slack_webhook_warning

Both may contain the same URL if you use a single channel. Files here are
gitignored — never commit webhook URLs.
```

- [ ] **Step 6: Run to verify it passes**

Run: `make compose-validate` then the full gate `make rules-validate rules-test scrape-validate alertmanager-validate`.
Expected: all PASS. (`docker compose config` does not require `./targets/*.yml` or `./secrets/*` to exist.)

- [ ] **Step 7: Commit**

```bash
git add deploy/compose/host/ Makefile
git commit -m "feat: Add host compose stack (VictoriaMetrics, vmagent, vmalert, Alertmanager, Grafana)"
```

---

### Task 4: Quickstart docs, gitignore, CI, status

**Files:**
- Create: `deploy/compose/README.md`
- Modify: `.gitignore` (append ignores)
- Modify: `.github/workflows/monitoring-test.yml` (paths + steps)
- Modify: `IMPLEMENTATION_PLAN.md` (Phase 2 done; add Phase 5 CI-deferral note)

**Interfaces:**
- Consumes: `make compose-validate`, `make alertmanager-validate` (Tasks 1–3).

- [ ] **Step 1: Write `deploy/compose/README.md`**

```markdown
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

## Worker (each GPU node)

    cd deploy/compose/worker
    cp .env.example .env
    docker compose up -d                       # dcgm-exporter + node-exporter
    docker compose --profile all-smi up -d     # + optional all-smi

Non-NVIDIA nodes: `docker compose up -d node-exporter` only.

## Smoke test (host, no GPU needed)

    docker compose up -d
    curl -s localhost:8880/api/v1/rules | grep -c '"name"'   # 6 rule groups
    curl -s localhost:9093/api/v2/alerts | grep Watchdog     # dead man's switch firing

`Watchdog` firing at Alertmanager proves the vmalert → Alertmanager path.
It is routed to a null receiver, so Slack stays quiet — configure your
real webhooks in `host/secrets/` and trigger a test alert to verify
Slack delivery end to end.

## Validation (CI-equivalent)

    make compose-validate alertmanager-validate
```

- [ ] **Step 2: Append to `.gitignore`**

```gitignore
# Compose deployment-specific files (never commit)
deploy/compose/host/secrets/*
!deploy/compose/host/secrets/README.md
deploy/compose/host/targets/*.yml
deploy/compose/**/.env
```

- [ ] **Step 3: Extend `.github/workflows/monitoring-test.yml`**

Add to BOTH `paths:` lists:

```yaml
      - 'deploy/compose/**'
```

(`monitoring/**` already covers `monitoring/alerting/`.) Add two steps after "Validate vmagent scrape config":

```yaml
      - name: Validate Alertmanager config
        run: make alertmanager-validate

      - name: Validate compose stacks
        run: make compose-validate
```

- [ ] **Step 4: Update `IMPLEMENTATION_PLAN.md`**

Mark the Phase 2 row `✅ done` and set its Plan cell to
`docs/superpowers/plans/2026-08-07-alert-center-phase2-compose.md`.
Append to `## Notes carried to later phases`:

```markdown
- **Phase 5 (CI, deferred by decision)**: `terraform-test.yml` Cost Estimation
  job fails on any PR touching `tests/**` — it `cd`s into the nonexistent
  `terraform/examples/basic` (real examples: `host-only`, `training-cluster`).
  Pre-existing bug surfaced by PR #1; fix the path and narrow the `tests/**`
  trigger to `tests/{unit,integration,e2e}/**` during the terraform migration.
```

- [ ] **Step 5: Verify everything**

Run: `make rules-validate rules-test scrape-validate alertmanager-validate compose-validate`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add deploy/compose/README.md .gitignore .github/workflows/monitoring-test.yml IMPLEMENTATION_PLAN.md
git commit -m "docs: Add compose quickstart, CI validation, Phase 2 status"
```

---

## Self-Review Notes

- Spec coverage: §5 Alertmanager policy → Task 1 (severity routes, group_by, inhibition, Watchdog blackhole, secret injection); §6.1 worker → Task 2 (ports/profile/mountstats contract); §6.1 host → Task 3 (bind mounts of scrape/rules/alerting, remoteWrite for recording rules); §7 compose row → Tasks 2–4 (`docker compose config` in CI).
- Consistency: secret paths in Task 1 receivers = mount target of Task 3 (`./secrets` → `/etc/alertmanager/secrets`); ports in worker `.env.example` = target templates' ports (9400/9100/9090); `node` label contract stated in targets/README matches Alertmanager `equal: ['node']`.
- Judgment calls encoded: `runtime: nvidia` over `gpus:` (matches legacy repo, wider compose compatibility); two webhook files (may be identical) instead of env-substitution hacks (Alertmanager has no env expansion; `api_url_file` is native); validation-only CI (no `compose up` — smoke test documented as manual).
