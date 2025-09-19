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

			// Validate Terraform configuration
			terraform.Init(t, terraformOptions)
			exitCode := terraform.ValidateE(t, terraformOptions)
			assert.Equal(t, 0, exitCode, "Terraform validation should pass")
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
			exitCode := terraform.FmtE(t, terraformOptions)
			assert.Equal(t, 0, exitCode, "Terraform files should be properly formatted")
		})
	}
}