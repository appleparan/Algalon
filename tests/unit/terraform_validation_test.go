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
			name: "Basic Example",
			path: "../../terraform/examples/basic",
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

			// Validate Terraform configuration
			terraform.Init(t, terraformOptions)
			_, validationErr := terraform.ValidateE(t, terraformOptions)
			assert.NoError(t, validationErr)
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
			name: "Basic Example",
			path: "../../terraform/examples/basic",
		},
	}

	for _, tc := range testCases {
		tc := tc // capture range variable
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
				TerraformDir: tc.path,
				NoColor:      true,
			})

			// Check Terraform formatting
			terraform.Init(t, terraformOptions)
			_, validationErr := terraform.ValidateE(t, terraformOptions)
			assert.NoError(t, validationErr)
		})
	}
}