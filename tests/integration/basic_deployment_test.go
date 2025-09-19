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

func TestBasicDeploymentIntegration(t *testing.T) {
	t.Parallel()

	// Skip if running in CI without GCP credentials
	if os.Getenv("TF_VAR_project_id") == "" {
		t.Skip("Skipping integration test: TF_VAR_project_id not set")
	}

	projectID := os.Getenv("TF_VAR_project_id")
	region := getEnvOrDefault("TF_VAR_region", "us-central1")

	// Generate unique deployment name
	uniqueID := random.UniqueId()
	deploymentName := fmt.Sprintf("algalon-integration-%s", uniqueID)

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../terraform/examples/basic",
		NoColor:      true,
		Vars: map[string]interface{}{
			"project_id":        projectID,
			"region":            region,
			"deployment_name":   deploymentName,
			"worker_count":      1, // Keep minimal for integration test
			"gpu_type":          "nvidia-tesla-t4",
			"cluster_name":      "integration-test",
			"environment_name":  "testing",
			"use_preemptible_workers": true, // Cost optimization
			"enable_host_external_ip":  true,
			"enable_worker_external_ip": false,
			"grafana_allowed_ips": []string{"0.0.0.0/0"}, // Allow all for testing
			"ssh_allowed_ips":     []string{"0.0.0.0/0"}, // Allow all for testing
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

	// Test that infrastructure was created correctly
	testInfrastructureCreation(t, terraformOptions, projectID, region)

	// Test network connectivity
	testNetworkConnectivity(t, terraformOptions)

	// Test monitoring endpoints
	testMonitoringEndpoints(t, terraformOptions)
}

func testInfrastructureCreation(t *testing.T, terraformOptions *terraform.Options, projectID, region string) {
	// Get outputs
	networkName := terraform.Output(t, terraformOptions, "network_name")
	monitoringHostIP := terraform.Output(t, terraformOptions, "monitoring_host_external_ip")
	workerInternalIPs := terraform.OutputList(t, terraformOptions, "worker_internal_ips")

	// Verify network was created
	assert.NotEmpty(t, networkName)
	network := gcp.GetNetwork(t, projectID, networkName)
	assert.NotNil(t, network)

	// Verify monitoring host was created
	assert.NotEmpty(t, monitoringHostIP)
	assert.Regexp(t, `^\d+\.\d+\.\d+\.\d+$`, monitoringHostIP)

	// Verify workers were created
	assert.Len(t, workerInternalIPs, 1)
	for _, ip := range workerInternalIPs {
		assert.Regexp(t, `^\d+\.\d+\.\d+\.\d+$`, ip)
	}

	// Verify instances exist in GCP
	instances := gcp.GetInstancesInRegion(t, projectID, region)

	var monitoringInstance, workerInstance *gcp.Instance
	for _, instance := range instances {
		if instance.Labels["component"] == "algalon-host" {
			monitoringInstance = instance
		}
		if instance.Labels["component"] == "algalon-worker" {
			workerInstance = instance
		}
	}

	require.NotNil(t, monitoringInstance, "Monitoring instance should exist")
	require.NotNil(t, workerInstance, "Worker instance should exist")

	// Verify instance labels
	assert.Equal(t, "integration-test", monitoringInstance.Labels["cluster"])
	assert.Equal(t, "testing", monitoringInstance.Labels["environment"])
	assert.Equal(t, "algalon-host", monitoringInstance.Labels["component"])

	assert.Equal(t, "integration-test", workerInstance.Labels["cluster"])
	assert.Equal(t, "testing", workerInstance.Labels["environment"])
	assert.Equal(t, "algalon-worker", workerInstance.Labels["component"])
}

func testNetworkConnectivity(t *testing.T, terraformOptions *terraform.Options) {
	// Test that instances are in the correct network and can communicate
	monitoringHostIP := terraform.Output(t, terraformOptions, "monitoring_host_internal_ip")
	workerInternalIPs := terraform.OutputList(t, terraformOptions, "worker_internal_ips")

	assert.NotEmpty(t, monitoringHostIP)
	assert.NotEmpty(t, workerInternalIPs)

	// Verify IPs are in the expected subnet range (10.1.x.x)
	assert.Regexp(t, `^10\.1\.\d+\.\d+$`, monitoringHostIP)
	for _, ip := range workerInternalIPs {
		assert.Regexp(t, `^10\.1\.\d+\.\d+$`, ip)
	}
}

func testMonitoringEndpoints(t *testing.T, terraformOptions *terraform.Options) {
	// Get URLs
	grafanaURL := terraform.Output(t, terraformOptions, "grafana_url")
	victoriaMetricsURL := terraform.Output(t, terraformOptions, "victoria_metrics_url")
	workerEndpoints := terraform.OutputList(t, terraformOptions, "worker_metrics_endpoints")

	// Verify URLs are properly formatted
	assert.Regexp(t, `^http://\d+\.\d+\.\d+\.\d+:3000$`, grafanaURL)
	assert.Regexp(t, `^http://\d+\.\d+\.\d+\.\d+:8428$`, victoriaMetricsURL)

	for _, endpoint := range workerEndpoints {
		assert.Regexp(t, `^http://\d+\.\d+\.\d+\.\d+:9090/metrics$`, endpoint)
	}

	// Note: We don't test actual HTTP connectivity here because:
	// 1. Services need time to start up (cloud-init takes several minutes)
	// 2. This would require more complex networking setup in CI
	// 3. End-to-end tests will cover actual service availability
}

func getEnvOrDefault(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}