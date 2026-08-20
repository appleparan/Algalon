# Algalon Makefile — monitoring validation and deployment helpers

.PHONY: help rules-validate rules-test scrape-validate alertmanager-validate compose-validate dashboards-validate helm-sync helm-validate e2e-k3d release

# Default target
help: ## Show this help message
	@echo "Algalon Commands"
	@echo "================"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# Monitoring / alert rules
VM_VERSION := v1.149.0
KUBECONFORM_TAG := v0.8.0

rules-validate: ## Validate vmalert rule file syntax
	@docker run --rm -v $(CURDIR)/monitoring/rules:/rules:ro \
		victoriametrics/vmalert:$(VM_VERSION) \
		-rule='/rules/*.yml' -datasource.url=http://localhost:8428 -dryRun
	@echo "✅ vmalert rules valid"

rules-test: ## Run vmalert rule unit tests
	@docker run --rm -v $(CURDIR):/repo:ro -w /repo \
		victoriametrics/vmalert-tool:$(VM_VERSION) \
		unittest -files='tests/rules/*.test.yml'
	@echo "✅ rule unit tests passed"

scrape-validate: ## Validate vmagent scrape config
	@docker run --rm -v $(CURDIR)/monitoring/scrape:/scrape:ro \
		victoriametrics/vmagent:$(VM_VERSION) \
		-promscrape.config=/scrape/prometheus.yml -dryRun
	@echo "✅ vmagent scrape config valid"

alertmanager-validate: ## Validate Alertmanager routing config
	@docker run --rm -v $(CURDIR)/monitoring/alerting:/config:ro \
		--entrypoint /bin/amtool prom/alertmanager:v0.33.1 \
		check-config /config/alertmanager.yml
	@echo "✅ alertmanager config valid"

compose-validate: ## Validate compose stacks
	@docker compose -f deploy/compose/worker/docker-compose.yml config -q
	@docker compose -f deploy/compose/worker/docker-compose.yml --profile all-smi config -q
	@docker compose -f deploy/compose/host/docker-compose.yml config -q
	@echo "✅ compose stacks valid"

dashboards-validate: ## Validate Grafana dashboard JSON conventions
	@set -e; for f in monitoring/dashboards/*.json; do \
		jq -e '.uid | test("^algalon-")' "$$f" >/dev/null || { echo "$$f: bad uid"; exit 1; }; \
		jq -e '.tags | index("algalon")' "$$f" >/dev/null || { echo "$$f: missing algalon tag"; exit 1; }; \
		jq -e '.refresh == "30s"' "$$f" >/dev/null || { echo "$$f: refresh != 30s"; exit 1; }; \
		jq -e '.templating.list | map(select(.type == "datasource")) | length >= 1' "$$f" >/dev/null || { echo "$$f: no datasource variable"; exit 1; }; \
		jq -e '[.panels[] | select(.targets) | .targets[] | .datasource.uid] | all(. == "$${datasource}")' "$$f" >/dev/null || { echo "$$f: panel target not using \$${datasource}"; exit 1; }; \
		jq -e '[.uid] as $$u | true' "$$f" >/dev/null; \
	done; \
	uids=$$(jq -r '.uid' monitoring/dashboards/*.json | sort | uniq -d); \
	test -z "$$uids" || { echo "duplicate uids: $$uids"; exit 1; }
	@echo "✅ dashboards valid"

helm-sync: ## Sync monitoring/ content into the Helm chart files/ dir (generated)
	@mkdir -p deploy/helm/algalon/files
	@rsync -a --delete monitoring/rules monitoring/dashboards monitoring/alerting monitoring/exporters deploy/helm/algalon/files/
	@echo "✅ helm files synced"

# Alertmanager has no usable default for the Slack webhooks — the chart fails
# the render rather than shipping a broken notifier — so validation supplies
# throwaway URLs. Never point these at a real workspace.
HELM_VALIDATE_SET := --set allSmi.enabled=true \
	--set alertmanager.slack.criticalUrl=https://hooks.example/x \
	--set alertmanager.slack.warningUrl=https://hooks.example/y

helm-validate: helm-sync ## Lint and schema-validate the Helm chart
	@helm lint deploy/helm/algalon $(HELM_VALIDATE_SET)
	@helm template algalon deploy/helm/algalon $(HELM_VALIDATE_SET) \
		| docker run --rm -i ghcr.io/yannh/kubeconform:$(KUBECONFORM_TAG) -strict -summary
	@echo "✅ helm chart valid"

# Not part of the validation gate: needs docker + k3d and takes minutes.
# It answers the one question `helm-validate` cannot — does the deployed
# pipeline actually evaluate rules and route alerts.
e2e-k3d: ## Run k3d end-to-end smoke test
	@bash tests/e2e/k3d-smoke.sh

release: ## Cut a release (usage: make release VERSION=0.5.0)
	@if [ -z "$(VERSION)" ]; then \
		echo "usage: make release VERSION=X.Y.Z"; \
		exit 1; \
	fi
	@bash scripts/release.sh $(VERSION)
