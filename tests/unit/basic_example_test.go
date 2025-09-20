package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

func TestBasicExampleValidation(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../terraform/examples/basic",
		NoColor:      true,
		Vars: map[string]interface{}{
			"project_id": "test-project-id",
		},
	})

	// Test initialization and validation
	terraform.Init(t, terraformOptions)
	_, validationErr := terraform.ValidateE(t, terraformOptions)
	assert.NoError(t, validationErr)
}

func TestBasicExamplePlan(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../terraform/examples/basic",
		NoColor:      true,
		Vars: map[string]interface{}{
			"project_id": "test-project-123",
			"region":     "us-central1",
		},
	})

	terraform.Init(t, terraformOptions)
	_, planErr := terraform.PlanE(t, terraformOptions)
	assert.NoError(t, planErr)

	// Test basic validation - plan should succeed
	// For detailed resource validation, consider using terraform show with JSON output
	// or implement infrastructure tests after apply
}

func TestBasicExampleWithWorkers(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../terraform/examples/basic",
		NoColor:      true,
		Vars: map[string]interface{}{
			"project_id":               "test-project-123",
			"region":                   "us-central1",
			"worker_count":             2,
			"worker_machine_type":      "n1-standard-2",
			"worker_gpu_type":          "nvidia-tesla-t4",
			"worker_gpu_count":         1,
			"enable_worker_external_ip": false,
		},
	})

	terraform.Init(t, terraformOptions)
	_, validationErr := terraform.ValidateE(t, terraformOptions)
	assert.NoError(t, validationErr)

	// Test planning
	_, planErr := terraform.PlanE(t, terraformOptions)
	assert.NoError(t, planErr)
}

func TestBasicExampleMinimal(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../terraform/examples/basic",
		NoColor:      true,
		Vars: map[string]interface{}{
			"project_id":    "test-project-minimal",
			"worker_count":  0, // Host-only deployment
		},
	})

	terraform.Init(t, terraformOptions)
	_, validationErr := terraform.ValidateE(t, terraformOptions)
	assert.NoError(t, validationErr)

	// Test planning
	_, planErr := terraform.PlanE(t, terraformOptions)
	assert.NoError(t, planErr)
}