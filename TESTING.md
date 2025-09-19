# Algalon Terraform Testing Guide

Comprehensive testing framework for Algalon infrastructure using GitHub Actions, Terratest, and security scanning tools.

## Overview

Our testing strategy covers multiple layers:

- **🔍 Static Analysis**: Format checking, linting, security scanning
- **🧪 Unit Tests**: Module validation and configuration testing
- **🔗 Integration Tests**: Real infrastructure deployment and validation
- **🚀 End-to-End Tests**: Full system functionality testing
- **💰 Cost Analysis**: Infrastructure cost estimation

## Quick Start

### Prerequisites

1. **Required Tools**:
   ```bash
   # Install all tools at once
   make install

   # Or install individually:
   # - Terraform >= 1.6.0
   # - Go >= 1.21
   # - TFLint
   # - Checkov
   # - terraform-docs
   ```

2. **For Integration/E2E Tests**:
   ```bash
   # Set GCP project
   export TF_VAR_project_id="your-gcp-project-id"
   export TF_VAR_region="us-central1"  # optional

   # Authenticate with GCP
   gcloud auth application-default login
   ```

### Running Tests

```bash
# Run all static checks and unit tests
make ci-test

# Run unit tests only
make test-unit

# Run integration tests (requires GCP)
make test-integration

# Run end-to-end tests (requires GCP)
make test-e2e

# Run security scan
make security

# Run linting
make lint

# Format code
make format
```

## Test Types

### 1. Static Analysis

#### Terraform Validation
```bash
make validate
```
- Validates syntax and configuration
- Checks module references
- Verifies variable types

#### Code Formatting
```bash
make check-format  # Check only
make format         # Fix formatting
```
- Ensures consistent code style
- Follows Terraform conventions

#### Linting (TFLint)
```bash
make lint
```
- Detects deprecated syntax
- Validates Google Cloud resources
- Enforces naming conventions
- Checks for common mistakes

#### Security Scanning (Checkov)
```bash
make security        # CLI output
make security-sarif  # Generate SARIF for GitHub
```
- Scans for security vulnerabilities
- Checks compliance with best practices
- Validates firewall rules
- Reviews IAM permissions

### 2. Unit Tests

Located in `tests/unit/`, these tests validate:

```bash
make test-unit
```

**What's Tested**:
- Terraform module syntax and validation
- Variable validation and defaults
- Resource configuration
- Output definitions
- Template rendering

**Test Files**:
- `terraform_validation_test.go` - Basic validation
- `network_module_test.go` - Network module testing
- `algalon_host_module_test.go` - Host module testing
- `algalon_worker_module_test.go` - Worker module testing
- `basic_example_test.go` - Example configuration testing

**Example Test**:
```go
func TestNetworkModuleDefaults(t *testing.T) {
    terraformOptions := &terraform.Options{
        TerraformDir: "../../terraform/modules/network",
        NoColor:      true,
    }

    terraform.Init(t, terraformOptions)
    validationErr := terraform.ValidateE(t, terraformOptions)
    assert.NoError(t, validationErr)
}
```

### 3. Integration Tests

Located in `tests/integration/`, these tests:

```bash
make test-integration
```

**What's Tested**:
- Real infrastructure deployment
- Resource creation in GCP
- Network connectivity
- Instance configuration
- Firewall rules
- Labels and metadata

**Test Coverage**:
- Network module deployment
- Basic example deployment
- Resource verification in GCP
- Configuration validation

**Requirements**:
- Valid GCP project with APIs enabled
- Appropriate IAM permissions
- Available quotas for resources

### 4. End-to-End Tests

Located in `tests/e2e/`, these tests:

```bash
make test-e2e
```

**What's Tested**:
- Complete Algalon deployment
- Service availability and health
- Metrics collection pipeline
- Grafana dashboard access
- VictoriaMetrics functionality
- Worker metrics endpoints

**Test Flow**:
1. Deploy full infrastructure
2. Wait for services to start (5+ minutes)
3. Test Grafana accessibility
4. Test VictoriaMetrics health
5. Verify worker metrics endpoints
6. Test metrics collection pipeline
7. Cleanup resources

## GitHub Actions Workflow

### Automated Testing

The `.github/workflows/terraform-test.yml` workflow runs:

**On Push/PR**:
- Format checking
- Validation
- Linting
- Security scanning
- Unit tests

**Manual Triggers**:
- Integration tests
- End-to-end tests
- Cost estimation

### Workflow Jobs

| Job | Purpose | Triggers |
|-----|---------|----------|
| `terraform-validate` | Syntax validation | All |
| `terraform-lint` | Code quality | All |
| `terraform-security` | Security scan | All |
| `terraform-docs` | Documentation check | All |
| `unit-tests` | Module testing | All |
| `integration-tests` | Infrastructure testing | Manual/Scheduled |
| `e2e-tests` | Full system testing | Manual/Scheduled |
| `cost-estimation` | Cost analysis | PRs |

### Required Secrets

For GitHub Actions to run integration/E2E tests:

```yaml
# In GitHub repository settings -> Secrets and variables -> Actions
GCP_SA_KEY: |
  {
    "type": "service_account",
    "project_id": "your-project",
    "private_key_id": "...",
    "private_key": "...",
    ...
  }

GCP_PROJECT_ID: "your-gcp-project-id"
GCP_REGION: "us-central1"  # optional

# Optional
SLACK_WEBHOOK_URL: "https://hooks.slack.com/..."
INFRACOST_API_KEY: "ico-xxx..."
```

## Local Development

### Setup Development Environment

```bash
# Clone repository
git clone https://github.com/inureyes/Algalon.git
cd Algalon

# Install tools
make install

# Set up dependencies
make deps

# Check status
make status
```

### Development Workflow

```bash
# 1. Make changes to Terraform code
# 2. Format code
make format

# 3. Run quality checks
make quality

# 4. Run unit tests
make test-unit

# 5. Test against real infrastructure (optional)
export TF_VAR_project_id="your-test-project"
make test-integration

# 6. Clean up
make clean
```

### Development Deployment

```bash
# Quick development deployment
export TF_VAR_project_id="your-dev-project"
make dev-apply

# Check what will be deployed
make dev-plan

# Clean up when done
make dev-destroy
```

## Configuration

### Test Configuration Files

| File | Purpose |
|------|---------|
| `.tflint.hcl` | TFLint rules and configuration |
| `.checkov.yml` | Checkov security scan configuration |
| `Makefile` | Development commands and workflows |

### Customizing Tests

#### Adding New Unit Tests

1. Create test file in `tests/unit/`
2. Import Terratest modules
3. Write test functions
4. Add to CI workflow if needed

```go
package test

import (
    "testing"
    "github.com/gruntwork-io/terratest/modules/terraform"
    "github.com/stretchr/testify/assert"
)

func TestMyModule(t *testing.T) {
    // Test implementation
}
```

#### Modifying Security Rules

Edit `.checkov.yml`:

```yaml
skip-check:
  - CKV_GCP_XX  # Skip specific check with reason

check:
  - CKV_GCP_YY  # Enforce specific check
```

#### Adding Lint Rules

Edit `.tflint.hcl`:

```hcl
rule "my_custom_rule" {
  enabled = true
}
```

## CI/CD Integration

### Branch Protection

Recommended branch protection rules:

```yaml
main:
  required_status_checks:
    - terraform-validate
    - terraform-lint
    - terraform-security
    - unit-tests
  require_branches_to_be_up_to_date: true
  required_pull_request_reviews:
    required_approving_review_count: 1
```

### Release Workflow

```bash
# 1. Create feature branch
git checkout -b feature/new-functionality

# 2. Make changes and test
make quality test-unit

# 3. Create pull request
# - CI runs automatically
# - Cost estimation generated
# - Security scan results

# 4. After approval and merge
# - Integration tests run
# - Documentation updated
# - Release tagged
```

## Troubleshooting

### Common Issues

#### Unit Tests Failing

```bash
# Check formatting
make check-format

# Validate syntax
make validate

# Check specific module
cd terraform/modules/network
terraform init
terraform validate
```

#### Integration Tests Failing

```bash
# Check authentication
gcloud auth list

# Check project access
gcloud projects describe $TF_VAR_project_id

# Check quotas
gcloud compute project-info describe --project=$TF_VAR_project_id

# Enable required APIs
gcloud services enable compute.googleapis.com
```

#### E2E Tests Timing Out

```bash
# Check instance startup
gcloud compute instances list --filter="labels.component:algalon-*"

# Check setup logs
gcloud compute ssh INSTANCE_NAME --command="sudo tail -f /var/log/algalon-setup.log"

# Check service status
gcloud compute ssh INSTANCE_NAME --command="docker ps"
```

#### Security Scan False Positives

```bash
# Review specific check
checkov --check CKV_GCP_XX --framework terraform terraform/

# Add skip rule to .checkov.yml
skip-check:
  - CKV_GCP_XX  # Reason for skipping
```

### Debug Commands

```bash
# View detailed test output
cd tests/unit && go test -v -run TestSpecificTest

# Run single integration test
cd tests/integration && go test -v -run TestNetworkModule

# Check lint rules
tflint --format json terraform/modules/network/

# Dry run security scan
checkov --config-file .checkov.yml --dry-run
```

## Performance and Optimization

### Test Execution Times

| Test Type | Duration | Parallelization |
|-----------|----------|-----------------|
| Unit Tests | 2-5 minutes | Yes |
| Integration Tests | 10-15 minutes | Limited |
| E2E Tests | 30-45 minutes | No |
| Security Scan | 1-2 minutes | Yes |

### Optimization Tips

1. **Parallel Execution**: Unit tests run in parallel
2. **Resource Limits**: Integration tests use minimal resources
3. **Preemptible Instances**: E2E tests use cost-effective instances
4. **Cleanup**: Automatic resource cleanup prevents cost accumulation
5. **Caching**: Go modules and Terraform providers cached in CI

## Best Practices

### Test Design

1. **Idempotent**: Tests should be repeatable
2. **Isolated**: Each test should be independent
3. **Fast**: Optimize for quick feedback
4. **Realistic**: Use real-world scenarios
5. **Comprehensive**: Cover success and failure cases

### Security

1. **Least Privilege**: Test service accounts have minimal permissions
2. **Temporary Resources**: All test resources are temporary
3. **No Secrets**: No hardcoded secrets in test code
4. **Audit Trail**: All test activities are logged

### Cost Management

1. **Preemptible Instances**: Use for cost reduction
2. **Minimal Resources**: Test with smallest viable instances
3. **Auto Cleanup**: Automatic resource destruction
4. **Monitoring**: Track test costs with Infracost

## Contributing

### Adding New Tests

1. Follow existing test patterns
2. Add documentation
3. Update CI workflow if needed
4. Test locally before submitting PR

### Test Standards

- Use descriptive test names
- Include setup and teardown
- Assert meaningful conditions
- Handle errors appropriately
- Clean up resources

### Pull Request Checklist

- [ ] Tests pass locally
- [ ] Code is formatted
- [ ] Security scan passes
- [ ] Documentation updated
- [ ] No hardcoded values
- [ ] Resource cleanup verified

## Resources

- [Terratest Documentation](https://terratest.gruntwork.io/)
- [TFLint Rules](https://github.com/terraform-linters/tflint)
- [Checkov Policies](https://www.checkov.io/5.Policy%20Index/terraform.html)
- [GitHub Actions](https://docs.github.com/en/actions)
- [Terraform Testing](https://developer.hashicorp.com/terraform/tutorials/automation/automate-terraform)

## Support

- [GitHub Issues](https://github.com/inureyes/Algalon/issues)
- [Discussions](https://github.com/inureyes/Algalon/discussions)
- [Contributing Guide](CONTRIBUTING.md)