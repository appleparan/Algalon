package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

func TestTrainingClusterExampleValidation(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../terraform/examples/training-cluster",
		NoColor:      true,
		Vars: map[string]interface{}{
			"project_id": "test-project-id",
		},
	})

	// Test initialization and planning (includes validation)
	terraform.Init(t, terraformOptions)
	_, planErr := terraform.PlanE(t, terraformOptions)
	assert.NoError(t, planErr, "Training cluster example should plan successfully")
}

func TestTrainingClusterExamplePlan(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../terraform/examples/training-cluster",
		NoColor:      true,
		Vars: map[string]interface{}{
			"project_id": "test-project-123",
			"region":     "us-central1",
		},
	})

	terraform.Init(t, terraformOptions)
	_, planErr := terraform.PlanE(t, terraformOptions)
	assert.NoError(t, planErr, "Training cluster example plan should succeed")
}

func TestTrainingClusterExampleWithWorkers(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../terraform/examples/training-cluster",
		NoColor:      true,
		Vars: map[string]interface{}{
			"project_id":                "test-project-123",
			"region":                    "us-central1",
			"worker_count":              2,
			"worker_machine_type":       "n1-standard-2",
			"gpu_type":                  "nvidia-tesla-t4",
			"gpu_count":                 1,
			"enable_worker_external_ip": false,
		},
	})

	terraform.Init(t, terraformOptions)
	_, planErr := terraform.PlanE(t, terraformOptions)
	assert.NoError(t, planErr)
}

func TestTrainingClusterExampleMinimal(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../terraform/examples/training-cluster",
		NoColor:      true,
		Vars: map[string]interface{}{
			"project_id":    "test-project-minimal",
			"worker_count":  0, // Host-only deployment
		},
	})

	terraform.Init(t, terraformOptions)
	_, planErr := terraform.PlanE(t, terraformOptions)
	assert.NoError(t, planErr)
}