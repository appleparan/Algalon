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
	validationErr := terraform.ValidateE(t, terraformOptions)
	assert.NoError(t, validationErr)
}

func TestNetworkModuleOutputs(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../terraform/modules/network",
		NoColor:      true,
		Vars: map[string]interface{}{
			"network_name": "test-network",
			"region":       "us-central1",
			"subnet_cidr":  "10.0.0.0/16",
		},
	})

	// Plan the infrastructure
	terraform.Init(t, terraformOptions)
	plan := terraform.Plan(t, terraformOptions)

	// Verify that the plan contains expected resources
	terraform.RequirePlannedValuesMapKeyExists(t, plan, "google_compute_network.algalon_network")
	terraform.RequirePlannedValuesMapKeyExists(t, plan, "google_compute_subnetwork.algalon_subnet")
	terraform.RequirePlannedValuesMapKeyExists(t, plan, "google_compute_firewall.algalon_grafana")
}

func TestNetworkModuleVariables(t *testing.T) {
	t.Parallel()

	testCases := []struct {
		name        string
		networkName string
		subnetCIDR  string
		shouldFail  bool
	}{
		{
			name:        "Valid Configuration",
			networkName: "algalon-test",
			subnetCIDR:  "10.1.0.0/16",
			shouldFail:  false,
		},
		{
			name:        "Custom Network Name",
			networkName: "custom-algalon-network",
			subnetCIDR:  "192.168.0.0/16",
			shouldFail:  false,
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
					"network_name": tc.networkName,
					"subnet_cidr":  tc.subnetCIDR,
				},
			})

			terraform.Init(t, terraformOptions)

			if tc.shouldFail {
				_, err := terraform.PlanE(t, terraformOptions)
				assert.Error(t, err)
			} else {
				plan := terraform.Plan(t, terraformOptions)
				assert.NotNil(t, plan)

				// Verify network name in plan
				networkName := terraform.GetPlannedValueForResource(t, plan, "google_compute_network.algalon_network", "name")
				assert.Equal(t, tc.networkName, networkName)

				// Verify subnet CIDR in plan
				subnetCIDR := terraform.GetPlannedValueForResource(t, plan, "google_compute_subnetwork.algalon_subnet", "ip_cidr_range")
				assert.Equal(t, tc.subnetCIDR, subnetCIDR)
			}
		})
	}
}

func TestFirewallRules(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../terraform/modules/network",
		NoColor:      true,
		Vars: map[string]interface{}{
			"network_name":                       "test-network",
			"enable_ssh_access":                  true,
			"enable_external_victoria_metrics":  true,
			"grafana_allowed_ips":                []string{"10.0.0.0/8"},
			"ssh_allowed_ips":                    []string{"10.0.0.0/8"},
		},
	})

	terraform.Init(t, terraformOptions)
	plan := terraform.Plan(t, terraformOptions)

	// Verify firewall rules are created
	terraform.RequirePlannedValuesMapKeyExists(t, plan, "google_compute_firewall.algalon_grafana")
	terraform.RequirePlannedValuesMapKeyExists(t, plan, "google_compute_firewall.algalon_metrics_internal")
	terraform.RequirePlannedValuesMapKeyExists(t, plan, "google_compute_firewall.algalon_ssh")
	terraform.RequirePlannedValuesMapKeyExists(t, plan, "google_compute_firewall.algalon_victoria_metrics")
}