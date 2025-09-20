package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

func TestNetworkModuleDefaults(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../terraform/modules/network",
		NoColor:      true,
	})

	// Test that the module initializes and validates correctly
	terraform.Init(t, terraformOptions)
	_, validationErr := terraform.ValidateE(t, terraformOptions)
	assert.NoError(t, validationErr)
}

func TestNetworkModuleBasicPlan(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../terraform/modules/network",
		NoColor:      true,
		Vars: map[string]interface{}{
			"network_name": "test-network",
			"region":       "us-central1",
			"subnet_cidr":  "10.2.0.0/16",
		},
	})

	terraform.Init(t, terraformOptions)
	_, validationErr := terraform.ValidateE(t, terraformOptions)
	assert.NoError(t, validationErr)

	// Test planning
	_, planErr := terraform.PlanE(t, terraformOptions)
	assert.NoError(t, planErr)
}

func TestNetworkModuleCustomConfiguration(t *testing.T) {
	t.Parallel()

	testCases := []struct {
		name         string
		networkName  string
		region       string
		subnetCIDR   string
		enableSSH    bool
		enableExtVM  bool
	}{
		{
			name:        "Production Network",
			networkName: "algalon-prod-network",
			region:      "us-central1",
			subnetCIDR:  "10.10.0.0/16",
			enableSSH:   true,
			enableExtVM: false,
		},
		{
			name:        "Development Network",
			networkName: "algalon-dev-network",
			region:      "us-west1",
			subnetCIDR:  "10.20.0.0/16",
			enableSSH:   true,
			enableExtVM: true,
		},
		{
			name:        "Secure Network",
			networkName: "algalon-secure-network",
			region:      "us-east1",
			subnetCIDR:  "10.30.0.0/16",
			enableSSH:   false,
			enableExtVM: false,
		},
	}

	for _, tc := range testCases {
		tc := tc // capture range variable
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
				TerraformDir: "../../terraform/modules/network",
				NoColor:      true,
				Vars: map[string]interface{}{
					"network_name":                    tc.networkName,
					"region":                          tc.region,
					"subnet_cidr":                     tc.subnetCIDR,
					"enable_ssh_access":               tc.enableSSH,
					"enable_external_victoria_metrics": tc.enableExtVM,
				},
			})

			terraform.Init(t, terraformOptions)
			_, validationErr := terraform.ValidateE(t, terraformOptions)
			assert.NoError(t, validationErr)

			// Test planning
			_, planErr := terraform.PlanE(t, terraformOptions)
			assert.NoError(t, planErr)
		})
	}
}