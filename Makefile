# Algalon Terraform Testing Makefile
# Provides convenient commands for development and CI/CD

.PHONY: help init validate plan apply destroy test test-unit test-integration test-e2e lint security docs clean format check-format

# Default target
help: ## Show this help message
	@echo "Algalon Terraform Testing Commands"
	@echo "=================================="
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# Installation and setup
install: ## Install required tools for development
	@echo "Installing development tools..."
	@command -v terraform >/dev/null 2>&1 || { echo "Please install Terraform"; exit 1; }
	@command -v go >/dev/null 2>&1 || { echo "Please install Go"; exit 1; }
	@go version | grep -q "go1.25" || echo "Warning: Go 1.25 is recommended"
	@echo "Installing TFLint..."
	@curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash
	@echo "Installing Checkov..."
	@uv venv --no-project --clear --python 3.13
	@uv pip install checkov
	@echo "Installing terraform-docs..."
	@go install github.com/terraform-docs/terraform-docs@latest
	@echo "✅ Development tools installed"

# Terraform operations
init: ## Initialize all Terraform configurations
	@echo "Initializing Terraform configurations..."
	@(cd terraform/examples/host-only && terraform init)
	@(cd terraform/examples/training-cluster && terraform init)
	@for module in terraform/modules/*/; do \
		echo "Initializing $$module"; \
		(cd "$$module" && terraform init -backend=false); \
	done
	@echo "✅ All Terraform configurations initialized"

validate: ## Validate all Terraform configurations
	@echo "Validating Terraform configurations..."
	@(cd terraform/examples/host-only && terraform validate)
	@(cd terraform/examples/training-cluster && terraform validate)
	@for module in terraform/modules/*/; do \
		echo "Validating $$module"; \
		(cd "$$module" && terraform validate); \
	done
	@echo "✅ All Terraform configurations are valid"

plan: ## Create Terraform plan for basic example
	@echo "Creating Terraform plan..."
	@(cd terraform/examples/host-only && terraform plan -var="project_id=test-project")
	@(cd terraform/examples/training-cluster && terraform plan -var="project_id=test-project")

format: ## Format all Terraform files
	@echo "Formatting Terraform files..."
	@terraform fmt -recursive terraform/
	@echo "✅ All Terraform files formatted"

check-format: ## Check Terraform file formatting
	@echo "Checking Terraform file formatting..."
	@terraform fmt -check -recursive terraform/
	@echo "✅ All Terraform files are properly formatted"

# Testing
test: test-unit ## Run all tests (default: unit tests)

test-unit: ## Run unit tests
	@echo "Running unit tests..."
	@(cd tests/unit && go test -v -timeout 30m ./...)
	@echo "✅ Unit tests completed"

test-integration: ## Run integration tests (requires GCP credentials)
	@echo "🧪 Running integration tests..."
	@echo "=============================="
	@if [ -z "$$TF_VAR_project_id" ]; then \
		echo "❌ TF_VAR_project_id environment variable is required"; \
		echo "💡 Example: export TF_VAR_project_id=algalon-dev-test"; \
		exit 1; \
	fi
	@echo "📋 Project ID: $$TF_VAR_project_id"
	@echo "📋 Region: $${TF_VAR_region:-us-central1}"
	@echo "📋 Test type: Integration (infrastructure creation/validation)"
	@echo ""
	@(cd tests/integration && go test -v -timeout 60m ./...)
	@echo "✅ Integration tests completed"

test-e2e: ## Run end-to-end tests (requires GCP credentials)
	@echo "🚀 Running end-to-end tests..."
	@echo "============================="
	@if [ -z "$$TF_VAR_project_id" ]; then \
		echo "❌ TF_VAR_project_id environment variable is required"; \
		echo "💡 Example: export TF_VAR_project_id=algalon-dev-test"; \
		exit 1; \
	fi
	@echo "📋 Project ID: $$TF_VAR_project_id"
	@echo "📋 Region: $${TF_VAR_region:-us-central1}"
	@echo "📋 Test type: End-to-end (full deployment with service validation)"
	@echo "⚠️  Note: E2E tests take 15-20 minutes and deploy real infrastructure"
	@echo ""
	@(cd tests/e2e && go test -v -timeout 120m ./...)
	@echo "✅ End-to-end tests completed"

test-integration-host: ## Run integration tests for host-only deployment
	@echo "🏠 Running host-only integration tests..."
	@echo "========================================"
	@export TEST_DEPLOYMENT_TYPE=host-only && \
	if [ -z "$$TF_VAR_project_id" ]; then \
		echo "❌ TF_VAR_project_id environment variable is required"; \
		echo "💡 Example: export TF_VAR_project_id=algalon-dev-test"; \
		exit 1; \
	fi && \
	echo "📋 Project ID: $$TF_VAR_project_id" && \
	echo "📋 Test type: Host-only integration" && \
	echo "" && \
	(cd tests/integration && go test -v -timeout 60m -run TestBasicDeploymentIntegration ./...)
	@echo "✅ Host-only integration tests completed"

test-integration-cluster: ## Run integration tests for training cluster deployment
	@echo "🎯 Running training cluster integration tests..."
	@echo "=============================================="
	@export TEST_DEPLOYMENT_TYPE=training-cluster && \
	if [ -z "$$TF_VAR_project_id" ]; then \
		echo "❌ TF_VAR_project_id environment variable is required"; \
		echo "💡 Example: export TF_VAR_project_id=algalon-dev-test"; \
		exit 1; \
	fi && \
	echo "📋 Project ID: $$TF_VAR_project_id" && \
	echo "📋 Test type: Training cluster integration" && \
	echo "" && \
	(cd tests/integration && go test -v -timeout 90m -run TestBasicDeploymentIntegration ./...)
	@echo "✅ Training cluster integration tests completed"

test-e2e-host: ## Run e2e tests for host-only deployment
	@echo "🏠 Running host-only end-to-end tests..."
	@echo "======================================="
	@export TEST_DEPLOYMENT_TYPE=host-only && \
	if [ -z "$$TF_VAR_project_id" ]; then \
		echo "❌ TF_VAR_project_id environment variable is required"; \
		echo "💡 Example: export TF_VAR_project_id=algalon-dev-test"; \
		exit 1; \
	fi && \
	echo "📋 Project ID: $$TF_VAR_project_id" && \
	echo "📋 Test type: Host-only end-to-end" && \
	echo "⚠️  Note: E2E tests take 10-15 minutes for host-only" && \
	echo "" && \
	(cd tests/e2e && go test -v -timeout 90m -run TestFullAlgalonDeploymentE2E ./...)
	@echo "✅ Host-only end-to-end tests completed"

test-e2e-cluster: ## Run e2e tests for training cluster deployment
	@echo "🎯 Running training cluster end-to-end tests..."
	@echo "=============================================="
	@export TEST_DEPLOYMENT_TYPE=training-cluster && \
	if [ -z "$$TF_VAR_project_id" ]; then \
		echo "❌ TF_VAR_project_id environment variable is required"; \
		echo "💡 Example: export TF_VAR_project_id=algalon-dev-test"; \
		exit 1; \
	fi && \
	echo "📋 Project ID: $$TF_VAR_project_id" && \
	echo "📋 Test type: Training cluster end-to-end" && \
	echo "⚠️  Note: E2E tests take 15-20 minutes for full cluster" && \
	echo "" && \
	(cd tests/e2e && go test -v -timeout 120m -run TestFullAlgalonDeploymentE2E ./...)
	@echo "✅ Training cluster end-to-end tests completed"

test-all: test-unit test-integration test-e2e ## Run all test suites

test-all-host: test-unit test-integration-host test-e2e-host ## Run all test suites for host-only deployment

test-all-cluster: test-unit test-integration-cluster test-e2e-cluster ## Run all test suites for training cluster deployment

test-quick: test-unit test-integration-host ## Run quick tests (unit + host-only integration)

# Linting and security
lint: ## Run TFLint on all Terraform files
	@echo "Running TFLint..."
	@tflint --init
	@find terraform/ -name "*.tf" -type f -exec dirname {} \; | sort -u | while read dir; do \
		echo "Linting $$dir"; \
		tflint --chdir="$$dir"; \
	done
	@echo "✅ TFLint completed"

security: ## Run Checkov security scan
	@echo "Running Checkov security scan..."
	@mkdir -p reports
	@uv run checkov --config-file .checkov.yml
	@echo "✅ Security scan completed"

security-sarif: ## Run Checkov and generate SARIF report
	@echo "Running Checkov security scan with SARIF output..."
	@mkdir -p reports
	@checkov --config-file .checkov.yml --output sarif --output-file-path reports/checkov-results.sarif
	@echo "✅ Security scan completed, SARIF report generated"

# Documentation
docs: ## Generate documentation for all modules
	@echo "📚 Generating documentation for all modules..."
	@echo "=============================================="
	@modules_failed=0; \
	for module in terraform/modules/*/; do \
		module_name=$$(basename "$$module"); \
		echo "📝 Processing module: $$module_name"; \
		if (cd "$$module" && terraform-docs markdown --lockfile=false table --output-file README.md --output-mode inject .); then \
			echo "✅ $$module_name: Documentation generated successfully"; \
		else \
			echo "❌ $$module_name: Documentation generation failed"; \
			modules_failed=$$((modules_failed + 1)); \
		fi; \
		echo ""; \
	done; \
	if [ $$modules_failed -eq 0 ]; then \
		echo "🎉 All module documentation generated successfully!"; \
	else \
		echo "⚠️  $$modules_failed module(s) failed to generate documentation"; \
		exit 1; \
	fi

docs-check: ## Check if documentation is up to date
	@echo "🔍 Checking documentation status..."
	@echo "==================================="
	@git_clean=true; \
	modules_checked=0; \
	modules_outdated=0; \
	for module in terraform/modules/*/; do \
		module_name=$$(basename "$$module"); \
		echo "📋 Checking module: $$module_name"; \
		modules_checked=$$((modules_checked + 1)); \
		(cd "$$module" && terraform-docs markdown --lockfile=false table --output-file README.md --output-mode inject . >/dev/null 2>&1); \
		if [ -n "$$(git diff --name-only "$$module/README.md" 2>/dev/null)" ]; then \
			echo "❌ $$module_name: Documentation is outdated"; \
			modules_outdated=$$((modules_outdated + 1)); \
			git_clean=false; \
		else \
			echo "✅ $$module_name: Documentation is up to date"; \
		fi; \
		echo ""; \
	done; \
	echo "📊 Summary: $$modules_checked modules checked, $$modules_outdated outdated"; \
	if [ "$$git_clean" = "true" ]; then \
		echo "🎉 All documentation is up to date!"; \
	else \
		echo "⚠️  Documentation is out of date. Run 'make docs' and commit changes."; \
		echo "📋 Changed files:"; \
		git diff --name-only | grep README.md || true; \
		exit 1; \
	fi

# Quality checks
quality: check-format validate lint security docs-check ## Run all quality checks

# CI/CD targets
ci-setup: ## Setup for CI environment
	@echo "Setting up CI environment..."
	@go mod download
	@(cd tests/unit && go mod download)
	@(cd tests/integration && go mod download)
	@(cd tests/e2e && go mod download)
	@echo "✅ CI environment setup completed"

ci-test: quality test-unit ## Run CI tests (quality + unit tests)

ci-integration: ci-setup test-integration ## Run CI integration tests

ci-e2e: ci-setup test-e2e ## Run CI end-to-end tests

# Cleanup
clean: ## Clean up temporary files and state
	@echo "Cleaning up..."
	@find . -name ".terraform" -type d -exec rm -rf {} +
	@find . -name "terraform.tfstate*" -delete
	@find . -name ".terraform.lock.hcl" -delete
	@rm -rf reports/
	@echo "✅ Cleanup completed"

# Development helpers
dev-host-plan: ## Plan host-only deployment for development
	@echo "🏗️  Planning host-only development deployment..."
	@(cd terraform/examples/host-only && \
		terraform init && \
		terraform plan \
		-var="project_id=algalon-dev-test" \
		-var="deployment_name=algalon-dev-$$USER" \
		-var="cluster_name=development" \
		-var="environment_name=dev-host" \
		-var="host_machine_type=n1-standard-2" \
		-var="enable_host_external_ip=true" \
		-var="reserve_static_ip=false")

dev-host-apply: ## Apply host-only deployment for development
	@echo "🚀 Applying host-only development deployment..."
	@(cd terraform/examples/host-only && \
		terraform init && \
		terraform apply -auto-approve \
		-var="project_id=algalon-dev-test" \
		-var="deployment_name=algalon-dev-$$USER" \
		-var="cluster_name=development" \
		-var="environment_name=dev-host" \
		-var="host_machine_type=n1-standard-2" \
		-var="enable_host_external_ip=true" \
		-var="reserve_static_ip=false")

dev-host-destroy: ## Destroy host-only development deployment
	@echo "💥 Destroying host-only development deployment..."
	@(cd terraform/examples/host-only && \
		terraform destroy -auto-approve \
		-var="project_id=algalon-dev-test" \
		-var="deployment_name=algalon-dev-$$USER")

dev-cluster-plan: ## Plan training cluster deployment for development
	@echo "🏗️  Planning training cluster development deployment..."
	@(cd terraform/examples/training-cluster && \
		terraform init && \
		terraform plan \
		-var="project_id=algalon-dev-test" \
		-var="deployment_name=algalon-dev-$$USER" \
		-var="cluster_name=development" \
		-var="environment_name=dev-cluster" \
		-var="worker_count=1" \
		-var="gpu_type=nvidia-tesla-t4" \
		-var="gpu_count=1" \
		-var="use_preemptible_workers=true" \
		-var="host_machine_type=n1-standard-2" \
		-var="worker_machine_type=n1-standard-1" \
		-var="reserve_static_ip=false")

dev-cluster-apply: ## Apply training cluster deployment for development
	@echo "🚀 Applying training cluster development deployment..."
	@(cd terraform/examples/training-cluster && \
		terraform init && \
		terraform apply -auto-approve \
		-var="project_id=algalon-dev-test" \
		-var="deployment_name=algalon-dev-$$USER" \
		-var="cluster_name=development" \
		-var="environment_name=dev-cluster" \
		-var="worker_count=1" \
		-var="gpu_type=nvidia-tesla-t4" \
		-var="gpu_count=1" \
		-var="use_preemptible_workers=true" \
		-var="host_machine_type=n1-standard-2" \
		-var="worker_machine_type=n1-standard-1" \
		-var="reserve_static_ip=false")

dev-cluster-destroy: ## Destroy training cluster development deployment
	@echo "💥 Destroying training cluster development deployment..."
	@(cd terraform/examples/training-cluster && \
		terraform destroy -auto-approve \
		-var="project_id=algalon-dev-test" \
		-var="deployment_name=algalon-dev-$$USER")

# Legacy dev commands for backward compatibility
dev-plan: dev-host-plan ## Alias for dev-host-plan (backward compatibility)
dev-apply: dev-host-apply ## Alias for dev-host-apply (backward compatibility)
dev-destroy: dev-host-destroy ## Alias for dev-host-destroy (backward compatibility)

# Examples
example-host: ## Show host-only deployment example
	@echo "📋 Host-only deployment example:"
	@echo "================================="
	@echo "# Quick development deployment:"
	@echo "make dev-host-apply"
	@echo ""
	@echo "# Manual deployment:"
	@echo "cd terraform/examples/host-only"
	@echo "terraform init"
	@echo "terraform apply -var=\"project_id=your-gcp-project\""
	@echo ""
	@echo "# With custom variables:"
	@echo "terraform apply \\"
	@echo "  -var=\"project_id=your-gcp-project\" \\"
	@echo "  -var=\"deployment_name=my-algalon\" \\"
	@echo "  -var=\"cluster_name=production\""

example-cluster: ## Show training cluster deployment example
	@echo "📋 Training cluster deployment example:"
	@echo "======================================="
	@echo "# Quick development deployment:"
	@echo "make dev-cluster-apply"
	@echo ""
	@echo "# Manual deployment:"
	@echo "cd terraform/examples/training-cluster"
	@echo "terraform init"
	@echo "terraform apply \\"
	@echo "  -var=\"project_id=your-gcp-project\" \\"
	@echo "  -var=\"worker_count=2\" \\"
	@echo "  -var=\"gpu_type=nvidia-tesla-t4\""
	@echo ""
	@echo "# Production deployment:"
	@echo "terraform apply \\"
	@echo "  -var=\"project_id=your-gcp-project\" \\"
	@echo "  -var=\"deployment_name=prod-algalon\" \\"
	@echo "  -var=\"worker_count=4\" \\"
	@echo "  -var=\"gpu_type=nvidia-tesla-v100\" \\"
	@echo "  -var=\"use_preemptible_workers=false\" \\"
	@echo "  -var=\"reserve_static_ip=true\""

example-vars-host: ## Show example terraform.tfvars for host-only
	@echo "📄 Example terraform.tfvars for host-only deployment:"
	@echo "====================================================="
	@cat terraform/examples/host-only/terraform.tfvars.example

example-vars-cluster: ## Show example terraform.tfvars for training cluster
	@echo "📄 Example terraform.tfvars for training cluster:"
	@echo "================================================="
	@cat terraform/examples/training-cluster/terraform.tfvars.example

# Legacy example commands for backward compatibility
example-basic: example-host ## Alias for example-host (backward compatibility)
example-vars: example-vars-host ## Alias for example-vars-host (backward compatibility)

# Status and info
status: ## Show current status
	@echo "Algalon Terraform Development Status"
	@echo "===================================="
	@echo "Project directory: $$(pwd)"
	@echo "Git branch: $$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'Not a git repo')"
	@echo "Git status: $$(git status --porcelain 2>/dev/null | wc -l) files changed"
	@echo ""
	@echo "Tool versions:"
	@terraform version | head -1 || echo "Terraform: Not installed"
	@go version 2>/dev/null || echo "Go: Not installed"
	@tflint --version 2>/dev/null || echo "TFLint: Not installed"
	@checkov --version 2>/dev/null || echo "Checkov: Not installed"
	@echo ""
	@echo "Environment variables:"
	@echo "TF_VAR_project_id: $${TF_VAR_project_id:-Not set}"
	@echo "TF_VAR_region: $${TF_VAR_region:-Not set (default: us-central1)}"

# Dependencies
deps: ## Install Go dependencies for tests
	@echo "Installing Go dependencies..."
	@(cd tests/unit && go mod tidy)
	@(cd tests/integration && go mod tidy)
	@(cd tests/e2e && go mod tidy)
	@echo "✅ Go dependencies installed"