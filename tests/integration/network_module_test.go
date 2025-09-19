package test

import (
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/gcp"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNetworkModuleIntegration(t *testing.T) {
	t.Parallel()

	// Skip if running in CI without GCP credentials
	if os.Getenv("TF_VAR_project_id") == "" {
		t.Skip("Skipping integration test: TF_VAR_project_id not set")
	}

	projectID := os.Getenv("TF_VAR_project_id")
	region := getEnvOrDefault("TF_VAR_region", "us-central1")

	// Generate unique network name
	uniqueID := random.UniqueId()
	networkName := fmt.Sprintf("algalon-network-test-%s", uniqueID)

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../terraform/modules/network",
		NoColor:      true,
		Vars: map[string]interface{}{
			"network_name":           networkName,
			"region":                 region,
			"subnet_cidr":            "10.2.0.0/16",
			"grafana_allowed_ips":    []string{"10.0.0.0/8"},
			"ssh_allowed_ips":        []string{"10.0.0.0/8"},
			"enable_ssh_access":      true,
			"enable_external_victoria_metrics": true,
		},
		RetryableTerraformErrors: map[string]string{
			".*timeout.*":                    "Timeout occurred",
			".*Error waiting for operation.*": "GCP operation timeout",
		},
		MaxRetries:         3,
		TimeBetweenRetries: 30 * time.Second,
	})

	// Clean up resources with "terraform destroy" at the end of the test
	defer terraform.Destroy(t, terraformOptions)

	// Run "terraform init" and "terraform apply"
	terraform.InitAndApply(t, terraformOptions)

	// Test network creation
	testNetworkCreation(t, terraformOptions, projectID, networkName, region)

	// Test firewall rules
	testFirewallRules(t, terraformOptions, projectID, networkName)

	// Test outputs
	testNetworkOutputs(t, terraformOptions, networkName)
}

func testNetworkCreation(t *testing.T, terraformOptions *terraform.Options, projectID, expectedNetworkName, region string) {
	// Verify network was created
	actualNetworkName := terraform.Output(t, terraformOptions, "network_name")
	assert.Equal(t, expectedNetworkName, actualNetworkName)

	// Get network details from GCP
	network := gcp.GetNetwork(t, projectID, expectedNetworkName)
	require.NotNil(t, network)
	assert.Equal(t, expectedNetworkName, network.Name)
	assert.False(t, network.AutoCreateSubnetworks)

	// Verify subnet was created
	subnetName := terraform.Output(t, terraformOptions, "subnet_name")
	subnet := gcp.GetSubnetwork(t, projectID, region, subnetName)
	require.NotNil(t, subnet)
	assert.Equal(t, "10.2.0.0/16", subnet.IpCidrRange)
	assert.Equal(t, region, subnet.Region)
}

func testFirewallRules(t *testing.T, terraformOptions *terraform.Options, projectID, networkName string) {
	// Get all firewall rules for the project
	firewallRules := gcp.GetFirewallRulesForNetwork(t, projectID, networkName)

	// Create a map for easier lookup
	ruleMap := make(map[string]*gcp.FirewallRule)
	for _, rule := range firewallRules {
		ruleMap[rule.Name] = rule
	}

	// Test Grafana firewall rule
	grafanaRuleName := fmt.Sprintf("%s-grafana", networkName)
	grafanaRule, exists := ruleMap[grafanaRuleName]
	require.True(t, exists, "Grafana firewall rule should exist")
	assert.Equal(t, "INGRESS", grafanaRule.Direction)
	assert.Contains(t, grafanaRule.TargetTags, "algalon-monitoring")

	// Check if TCP port 3000 is allowed
	var grafanaPortAllowed bool
	for _, allowed := range grafanaRule.Allowed {
		if allowed.IPProtocol == "tcp" {
			for _, port := range allowed.Ports {
				if port == "3000" {
					grafanaPortAllowed = true
					break
				}
			}
		}
	}
	assert.True(t, grafanaPortAllowed, "Grafana port 3000 should be allowed")

	// Test internal metrics firewall rule
	internalRuleName := fmt.Sprintf("%s-metrics-internal", networkName)
	internalRule, exists := ruleMap[internalRuleName]
	require.True(t, exists, "Internal metrics firewall rule should exist")
	assert.Equal(t, "INGRESS", internalRule.Direction)
	assert.Contains(t, internalRule.SourceTags, "algalon-monitoring")
	assert.Contains(t, internalRule.TargetTags, "algalon-worker")

	// Test SSH firewall rule
	sshRuleName := fmt.Sprintf("%s-ssh", networkName)
	sshRule, exists := ruleMap[sshRuleName]
	require.True(t, exists, "SSH firewall rule should exist")
	assert.Equal(t, "INGRESS", sshRule.Direction)
	assert.Contains(t, sshRule.TargetTags, "algalon-monitoring")
	assert.Contains(t, sshRule.TargetTags, "algalon-worker")

	// Test VictoriaMetrics firewall rule
	vmRuleName := fmt.Sprintf("%s-victoria-metrics", networkName)
	vmRule, exists := ruleMap[vmRuleName]
	require.True(t, exists, "VictoriaMetrics firewall rule should exist")
	assert.Equal(t, "INGRESS", vmRule.Direction)
	assert.Contains(t, vmRule.TargetTags, "algalon-monitoring")
}

func testNetworkOutputs(t *testing.T, terraformOptions *terraform.Options, expectedNetworkName string) {
	// Test all outputs
	networkName := terraform.Output(t, terraformOptions, "network_name")
	networkSelfLink := terraform.Output(t, terraformOptions, "network_self_link")
	subnetName := terraform.Output(t, terraformOptions, "subnet_name")
	subnetSelfLink := terraform.Output(t, terraformOptions, "subnet_self_link")
	subnetCIDR := terraform.Output(t, terraformOptions, "subnet_cidr")

	// Verify outputs
	assert.Equal(t, expectedNetworkName, networkName)
	assert.Contains(t, networkSelfLink, expectedNetworkName)
	assert.Equal(t, fmt.Sprintf("%s-subnet", expectedNetworkName), subnetName)
	assert.Contains(t, subnetSelfLink, subnetName)
	assert.Equal(t, "10.2.0.0/16", subnetCIDR)
}