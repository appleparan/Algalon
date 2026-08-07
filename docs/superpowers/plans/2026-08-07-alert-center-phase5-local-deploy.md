# Alert Center Phase 5: Legacy Removal + Local Deployment Strategy

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove all Terraform/GCP and legacy compose assets; establish the local (on-prem) deployment path — k3s + the Phase 4 Helm chart — with preflight/install/runbook assets; add a k3d-based E2E smoke test to CI; rewrite the README with explicit attribution to the Lablup report.

**Architecture (decided with user):** Workers stay Docker-based for training workloads; k3s agent (embedded containerd) runs ALONGSIDE Docker on each node, scheduling only the exporter DaemonSets. Central node runs k3s server with default addons disabled (traefik/servicelb/metrics-server) to avoid port grabs. Conflict surface is networking only — mitigated by a preflight script (ports, CIDR overlap, nvidia toolkit, firewall) and pinned install flags. dcgm-exporter does not request `nvidia.com/gpu`, so it never contends with training jobs for GPU allocation.

**Spec:** redesign spec §8 Phase 5, re-scoped by user decision (2026-08-07): Terraform is REMOVED, not migrated; the deferred terraform-test.yml Cost Estimation bug dissolves with the deletion.

## Global Constraints

- Removal inventory is EXACT (Task 1–2 lists). Never `rm -rf` outside the listed paths; use `git rm -r` so every deletion is reviewable in the diff. Do not touch `tests/rules/`, `monitoring/`, `deploy/{compose,helm}/`, `docs/`.
- README attribution is MANDATORY and must include, verbatim where quoted: citation form **"Lablup Inc. (2026)"**, contact link `https://www.lablup.com/contact`, dataset repo `https://huggingface.co/datasets/lablup/from-detection-to-recovery`, report PDF `https://huggingface.co/datasets/lablup/from-detection-to-recovery/blob/main/Lablup_Technical_Report_2026_ko.pdf`, arXiv `https://arxiv.org/abs/2605.09370`, and this BibTeX block byte-verbatim:

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

- k3s install flags are pinned: server `--disable traefik --disable servicelb --disable metrics-server`; agent joins via `K3S_URL`/`K3S_TOKEN`. Scripts must be non-destructive (preflight only reads; install scripts never uninstall/overwrite an existing k3s without an explicit `--force` the user types).
- Quality gate after every task: `make rules-validate rules-test scrape-validate alertmanager-validate compose-validate dashboards-validate helm-validate` all green (these must survive the Makefile trim).
- Work in worktree `.claude/worktrees/alert-center-phase5`, branch `feat/alert-center-phase5-local-deploy`. Commit per task; never --no-verify.

---

### Task 1: Remove Terraform toolchain

**Files (remove via `git rm -r`):** `terraform/`, `tests/unit/`, `tests/integration/`, `tests/e2e/` (Go terratest; KEEP `tests/rules/`), `.github/workflows/terraform-test.yml`, `cloud-init-gce.yml`.
**Files (modify):** `Makefile` — remove every terraform-era target (`install init validate plan apply destroy test test-unit test-integration test-e2e lint security docs clean format check-format deps` and their recipes, the header comment, and their `.PHONY` entries), KEEPING: `help`, `VM_VERSION`, `KUBECONFORM_TAG`, and all seven monitoring targets (`rules-validate rules-test scrape-validate alertmanager-validate compose-validate dashboards-validate helm-sync helm-validate`). Update the Makefile header comment to `# Algalon Makefile — monitoring validation and deployment helpers`.

- [ ] Step 1: `git rm -r` the listed paths; edit the Makefile.
- [ ] Step 2: Verify nothing else references the removed paths: `grep -rn "terraform\|terratest\|cloud-init" --include='*.yml' --include='*.md' --include='Makefile' . | grep -v docs/superpowers | grep -v README.md` — expect only hits in files being removed/rewritten later (README is Task 5; record remaining hits in the report).
- [ ] Step 3: Full gate — all seven targets green; `make help` renders only surviving targets.
- [ ] Step 4: Commit: `git commit -m "chore: Remove Terraform toolchain and GCP deployment assets"`

### Task 2: Remove legacy compose and docs

**Files (remove via `git rm -r`):** `algalon_host/`, `algalon_worker/`, `examples/`, `setup.sh`, `CLOUD_DEPLOYMENT.md`, `HYBRID_DEPLOYMENT.md`, `ROLLBACK.md`, `TESTING.md`, `WORKER_DEPLOYMENT.md`.
**Files (modify):** `.gitignore` (drop the `algalon_worker/.env` line if present), `AGENTS.md` (Repository Map: delete the "Legacy ... remain until the redesign phases complete" bullet and the `deploy/terraform/` bullet; adjust the map to actual layout: `monitoring/`, `deploy/compose/`, `deploy/helm/algalon`, `deploy/k3s/` (added in Task 3 — write the bullet now), `tests/rules/`).

- [ ] Step 1: Remove; edit `.gitignore` and `AGENTS.md`.
- [ ] Step 2: Reference sweep as in Task 1 Step 2 (now expect zero hits outside README/docs history).
- [ ] Step 3: Full gate green.
- [ ] Step 4: Commit: `git commit -m "chore: Remove legacy compose stacks and deployment docs"`

### Task 3: k3s deployment assets (`deploy/k3s/`)

**Files (create):** `deploy/k3s/preflight.sh`, `deploy/k3s/install-server.sh`, `deploy/k3s/install-agent.sh`, `deploy/k3s/README.md`.

Specs:
- **preflight.sh** — read-only checks, prints PASS/FAIL per item, exits nonzero on any FAIL: (1) required ports free — server mode: 6443; agent mode: 10250, 8472/udp, and warn-only 9100/9400 (exporter hostPorts); (2) CIDR overlap: `ip route` entries intersecting `10.42.0.0/16` or `10.43.0.0/16` → FAIL with remediation text (`--cluster-cidr/--service-cidr` overrides); (3) nvidia-container-toolkit presence (`nvidia-ctk --version`) → WARN if absent (GPU nodes only need it); (4) firewalld/ufw active → WARN with doc pointer; (5) existing k3s install detected → FAIL (point at uninstall runbook; scripts never remove it). Mode selected by `$1` ∈ {server, agent}.
- **install-server.sh** — runs preflight (server), then `curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --disable traefik --disable servicelb --disable metrics-server" sh -`; prints the node token path and next-step hint. Refuses to run if k3s already installed (no --force implementation — just refuse; reinstall is a manual runbook step).
- **install-agent.sh** — requires `K3S_URL` and `K3S_TOKEN` env; runs preflight (agent), then the standard agent install; refuses if already installed.
- **README.md** — runbook: architecture note (Docker for training + k3s agent for exporters side-by-side; why addons are disabled; dcgm-exporter needs `--set dcgmExporter.runtimeClassName=nvidia` when k3s auto-detects the toolkit), install order (server → helm install → agents), node add (one curl), node remove (`kubectl delete node` + `k3s-agent-uninstall.sh` — documented, not scripted), upgrade (`helm upgrade` for the stack; k3s channel upgrade note), full rollback (uninstall scripts shipped by k3s), and the Slack secret prerequisite.

- [ ] Step 1: Author all four files. `bash -n` each script; `shellcheck` if available (record availability).
- [ ] Step 2: Run `./deploy/k3s/preflight.sh agent` on this machine and record the real output (this host HAS k3s installed, so the expected result is the existing-install FAIL — proving the guard works).
- [ ] Step 3: Full gate green (untouched by this task, but run it).
- [ ] Step 4: Commit: `git commit -m "feat: Add k3s deployment scripts and runbook for local clusters"`

### Task 4: k3d E2E smoke test

**Files (create):** `tests/e2e/k3d-smoke.sh`. **Modify:** `Makefile` (target `e2e-k3d`), `.github/workflows/monitoring-test.yml` (new `e2e` job + `deploy/k3s/**` and `tests/e2e/**` paths).

Specs:
- **k3d-smoke.sh** (`set -euo pipefail`; requires k3d, helm, kubectl): create cluster `algalon-e2e` (`k3d cluster create algalon-e2e --no-lb --wait`), `trap` cluster delete on EXIT; `make helm-sync`; `helm install algalon deploy/helm/algalon --set alertmanager.slack.criticalUrl=https://hooks.invalid/c --set alertmanager.slack.warningUrl=https://hooks.invalid/w --wait --timeout 5m`. Assertions (in-cluster via `kubectl run --rm -i --image=curlimages/curl:8.10.1 --restart=Never`, each with a retry loop ≤90s):
  1. vmalert rule groups: `curl -s http://algalon-vmalert:8880/api/v1/rules` contains all six group names (`gpu-xid gpu-ecc gpu-health node-precursor storage-nfs meta`).
  2. Watchdog reached Alertmanager: `curl -s http://algalon-alertmanager:9093/api/v2/alerts` contains `Watchdog` (Slack delivery fails against hooks.invalid — expected and irrelevant; the alert being registered proves vmalert→AM).
  3. node scrape works: `curl -s 'http://algalon-victoriametrics:8428/api/v1/query?query=up{job=\"node\"}'` returns a sample with value `"1"` (node-exporter DaemonSet runs on the k3d node; dcgm/all-smi stay unscheduled by nodeSelector — assert the dcgm DaemonSet has `desiredNumberScheduled: 0` as a 4th check).
  Print a summary table; exit nonzero on any failed assertion.
- **Makefile**: `e2e-k3d: ## Run k3d end-to-end smoke test` → `@bash tests/e2e/k3d-smoke.sh`.
- **CI**: new job `e2e` (needs: monitoring) in monitoring-test.yml: install k3d via its official install script, then `make e2e-k3d`. helm/kubectl/docker are preinstalled on ubuntu-latest.

- [ ] Step 1: Author script + Makefile target; `bash -n`.
- [ ] Step 2: RUN IT locally (`make e2e-k3d`) — this machine has docker; install k3d locally if absent (`curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash` — record version). All assertions must actually pass; paste the summary into the report. If the local k3s occupies 6443, k3d picks its own API port — no conflict (k3d runs in docker).
- [ ] Step 3: Add the CI job; full gate green.
- [ ] Step 4: Commit: `git commit -m "test: Add k3d end-to-end smoke test for the Helm deployment"`

### Task 5: README rewrite + attribution + wrap-up

**Files:** rewrite `README.md`; modify `IMPLEMENTATION_PLAN.md`.

- [ ] Step 1: Rewrite `README.md` from scratch (English), structure:
  1. Title + one-paragraph description (comprehensive GPU cluster alert center).
  2. **`## Origin & Attribution` — near the top, before architecture.** Content: Algalon's alert rules, thresholds, and dashboards encode the operational findings of the Lablup technical report *From Detection to Recovery: Operational Analysis on LLM Pre-training with 504 GPUs*; explicit statement that this project started from and references the report and its dataset repo; all links from Global Constraints (dataset repo, PDF, arXiv, contact); "Please cite this work as **Lablup Inc. (2026)**"; the BibTeX block verbatim; note that `all-smi` is also a Lablup project (`https://github.com/lablup/all-smi`).
  3. Architecture diagram (ASCII: workers → vmagent → VM → vmalert → Alertmanager → Slack; Grafana).
  4. What's monitored (6 rule groups, one line each with report grounding).
  5. Deployment: three paths with links — Docker Compose (`deploy/compose/README.md`), Kubernetes/Helm (`deploy/helm/algalon/README.md`), local k3s cluster (`deploy/k3s/README.md`, recommended for on-prem).
  6. Dashboards (5, one line each).
  7. Development: validation targets table, rule unit tests, e2e smoke.
  8. License.
- [ ] Step 2: `IMPLEMENTATION_PLAN.md`: Phase 5 row `✅ done` with this plan's path; update the Phase 5 row text to "Legacy removal + local deploy strategy (k3s) + e2e"; strike the obsolete Cost-Estimation note (mark `(dissolved — terraform removed)`).
- [ ] Step 3: markdownlint hook clean; reference sweep: `grep -rn "algalon_host\|algalon_worker\|terraform" README.md AGENTS.md deploy/ Makefile .github/` → zero hits.
- [ ] Step 4: Full gate + `make e2e-k3d` once more (fast re-run guards the README-era edits touched nothing).
- [ ] Step 5: Commit: `git commit -m "docs: Rewrite README with Lablup attribution and local deployment guide"`

---

## Self-Review Notes

- User requirements covered: Terraform 제거 (T1), 레거시 제거 (T2), 배포 전략 재고민 결과 = k3s+Helm with Docker-coexistence safeguards (T3), 테스트 전략 = k3d E2E in CI (T4), 출처 명시 with exact citation/BibTeX (T5 §2, mandatory constraint).
- The deferred terraform-test.yml Cost Estimation bug is resolved by deletion (T1) — IMPLEMENTATION_PLAN note updated in T5.
- Deletions are `git rm` (reviewable, no shell rm -rf); install scripts refuse rather than overwrite; preflight is read-only.
- E2E is genuinely runnable both locally and in CI without GPUs; the GPU-only DaemonSets are asserted *unscheduled* rather than skipped silently.
