package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

func TestTerraformValidation(t *testing.T) {
	t.Parallel()

	testCases := []struct {
		name string
		path string
		vars map[string]interface{}
	}{
		{
			name: "Network Module",
			path: "../../terraform/modules/network",
			vars: map[string]interface{}{},
		},
		{
			name: "Algalon Host Module",
			path: "../../terraform/modules/algalon-host",
			vars: map[string]interface{}{
				"network_name": "test-network",
				"subnet_name":  "test-subnet",
			},
		},
		{
			name: "Algalon Worker Module",
			path: "../../terraform/modules/algalon-worker",
			vars: map[string]interface{}{
				"network_name": "test-network",
				"subnet_name":  "test-subnet",
			},
		},
		{
			name: "Training Cluster Example",
			path: "../../terraform/examples/training-cluster",
			vars: map[string]interface{}{
				"project_id": "test-project-123",
			},
		},
	}

	for _, tc := range testCases {
		tc := tc // capture range variable
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
				TerraformDir: tc.path,
				NoColor:      true,
				Vars:         tc.vars,
			})

			// Initialize and validate using plan
			// Plan includes validation and works with variables
			terraform.Init(t, terraformOptions)
			_, planErr := terraform.PlanE(t, terraformOptions)
			assert.NoError(t, planErr, "Terraform plan should succeed (includes validation)")
		})
	}
}

func TestTerraformFormat(t *testing.T) {
	t.Parallel()

	testCases := []struct {
		name string
		path string
	}{
		{
			name: "Network Module",
			path: "../../terraform/modules/network",
		},
		{
			name: "Algalon Host Module",
			path: "../../terraform/modules/algalon-host",
		},
		{
			name: "Algalon Worker Module",
			path: "../../terraform/modules/algalon-worker",
		},
		{
			name: "Training Cluster Example",
			path: "../../terraform/examples/training-cluster",
		},
		{
			name: "Host-only Example",
			path: "../../terraform/examples/host-only",
		},
	}

	for _, tc := range testCases {
		tc := tc // capture range variable
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			// Check Terraform formatting (fmt -check)
			_, formatErr := terraform.RunTerraformCommandE(t, &terraform.Options{
				TerraformDir: tc.path,
				NoColor:      true,
			}, "fmt", "-check")

			assert.NoError(t, formatErr, "Terraform files should be properly formatted")
		})
	}
}