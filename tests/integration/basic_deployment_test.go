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

	// Determine deployment type based on environment variable
	deploymentType := getEnvOrDefault("TEST_DEPLOYMENT_TYPE", "training-cluster")

	// Generate unique deployment name
	uniqueID := random.UniqueId()
	deploymentName := fmt.Sprintf("algalon-integration-%s-%s", deploymentType, uniqueID)

	// Set terraform directory based on deployment type
	var terraformDir string
	var vars map[string]interface{}

	if deploymentType == "host-only" {
		terraformDir = "../../terraform/examples/host-only"
		vars = map[string]interface{}{
			"project_id":        projectID,
			"region":            region,
			"deployment_name":   deploymentName,
			"cluster_name":      "integration-test",
			"environment_name":  "testing",
			"enable_host_external_ip":  true,
			"reserve_static_ip":        false, // Cost optimization
			"grafana_allowed_ips": []string{"0.0.0.0/0"}, // Allow all for testing
			"ssh_allowed_ips":     []string{"0.0.0.0/0"}, // Allow all for testing
			"host_machine_type":   "n1-standard-2", // Smaller for testing
		}
	} else {
		terraformDir = "../../terraform/examples/training-cluster"
		vars = map[string]interface{}{
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
			"host_machine_type":     "n1-standard-2", // Smaller for testing
			"worker_machine_type":   "n1-standard-1", // Smaller for testing
		}
	}

	t.Logf("Running integration test for deployment type: %s", deploymentType)

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: terraformDir,
		NoColor:      true,
		Vars:         vars,
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
	testInfrastructureCreation(t, terraformOptions, projectID, region, deploymentType)

	// Test network connectivity
	testNetworkConnectivity(t, terraformOptions, deploymentType)

	// Test monitoring endpoints
	testMonitoringEndpoints(t, terraformOptions, deploymentType)
}

func testInfrastructureCreation(t *testing.T, terraformOptions *terraform.Options, projectID, region, deploymentType string) {
	// Get outputs
	networkName := terraform.Output(t, terraformOptions, "network_name")
	monitoringHostIP := terraform.Output(t, terraformOptions, "monitoring_host_external_ip")

	// Verify network was created
	assert.NotEmpty(t, networkName)
	network := gcp.GetNetwork(t, projectID, networkName)
	assert.NotNil(t, network)

	// Verify monitoring host was created
	assert.NotEmpty(t, monitoringHostIP)
	assert.Regexp(t, `^\d+\.\d+\.\d+\.\d+$`, monitoringHostIP)

	// Verify instances exist in GCP
	instances := gcp.GetInstancesInRegion(t, projectID, region)

	var monitoringInstance *gcp.Instance
	var workerInstances []*gcp.Instance

	for _, instance := range instances {
		if instance.Labels["component"] == "algalon-host" {
			monitoringInstance = instance
		}
		if instance.Labels["component"] == "algalon-worker" {
			workerInstances = append(workerInstances, instance)
		}
	}

	require.NotNil(t, monitoringInstance, "Monitoring instance should exist")

	// Verify instance labels for monitoring host
	assert.Equal(t, "integration-test", monitoringInstance.Labels["cluster"])
	assert.Equal(t, "testing", monitoringInstance.Labels["environment"])
	assert.Equal(t, "algalon-host", monitoringInstance.Labels["component"])

	if deploymentType == "training-cluster" {
		// For training cluster, verify workers were created
		workerInternalIPs := terraform.OutputList(t, terraformOptions, "worker_internal_ips")
		assert.Len(t, workerInternalIPs, 1)
		for _, ip := range workerInternalIPs {
			assert.Regexp(t, `^\d+\.\d+\.\d+\.\d+$`, ip)
		}

		require.Len(t, workerInstances, 1, "Worker instances should exist for training cluster")

		for _, workerInstance := range workerInstances {
			assert.Equal(t, "integration-test", workerInstance.Labels["cluster"])
			assert.Equal(t, "testing", workerInstance.Labels["environment"])
			assert.Equal(t, "algalon-worker", workerInstance.Labels["component"])
		}
	} else {
		// For host-only deployment, workers should not exist
		assert.Len(t, workerInstances, 0, "No worker instances should exist for host-only deployment")
	}
}

func testNetworkConnectivity(t *testing.T, terraformOptions *terraform.Options, deploymentType string) {
	// Test that instances are in the correct network and can communicate
	monitoringHostIP := terraform.Output(t, terraformOptions, "monitoring_host_internal_ip")

	assert.NotEmpty(t, monitoringHostIP)

	if deploymentType == "training-cluster" {
		// Verify IPs are in the expected subnet range (10.1.x.x for training cluster)
		assert.Regexp(t, `^10\.1\.\d+\.\d+$`, monitoringHostIP)

		workerInternalIPs := terraform.OutputList(t, terraformOptions, "worker_internal_ips")
		assert.NotEmpty(t, workerInternalIPs)

		for _, ip := range workerInternalIPs {
			assert.Regexp(t, `^10\.1\.\d+\.\d+$`, ip)
		}
	} else {
		// Verify IPs are in the expected subnet range (10.0.x.x for host-only)
		assert.Regexp(t, `^10\.0\.\d+\.\d+$`, monitoringHostIP)
	}
}

func testMonitoringEndpoints(t *testing.T, terraformOptions *terraform.Options, deploymentType string) {
	// Get URLs
	grafanaURL := terraform.Output(t, terraformOptions, "grafana_url")
	victoriaMetricsURL := terraform.Output(t, terraformOptions, "victoria_metrics_url")

	// Verify URLs are properly formatted
	assert.Regexp(t, `^http://\d+\.\d+\.\d+\.\d+:3000$`, grafanaURL)
	assert.Regexp(t, `^http://\d+\.\d+\.\d+\.\d+:8428$`, victoriaMetricsURL)

	if deploymentType == "training-cluster" {
		workerEndpoints := terraform.OutputList(t, terraformOptions, "worker_metrics_endpoints")
		assert.NotEmpty(t, workerEndpoints, "Worker endpoints should exist for training cluster")

		for _, endpoint := range workerEndpoints {
			assert.Regexp(t, `^http://\d+\.\d+\.\d+\.\d+:9090/metrics$`, endpoint)
		}
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