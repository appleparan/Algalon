package test

import (
	"fmt"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/retry"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestFullAlgalonDeploymentE2E(t *testing.T) {
	// Skip if running in CI without GCP credentials
	if os.Getenv("TF_VAR_project_id") == "" {
		t.Skip("Skipping E2E test: TF_VAR_project_id not set")
	}

	projectID := os.Getenv("TF_VAR_project_id")
	region := getEnvOrDefault("TF_VAR_region", "us-central1")

	// Determine deployment type based on environment variable
	deploymentType := getEnvOrDefault("TEST_DEPLOYMENT_TYPE", "training-cluster")

	// Generate unique deployment name
	uniqueID := random.UniqueId()
	deploymentName := getEnvOrDefault("TF_VAR_deployment_name", fmt.Sprintf("algalon-e2e-%s-%s", deploymentType, uniqueID))

	// Set terraform directory based on deployment type
	var terraformDir string
	var vars map[string]interface{}

	if deploymentType == "host-only" {
		terraformDir = "../../terraform/examples/host-only"
		vars = map[string]interface{}{
			"project_id":        projectID,
			"region":            region,
			"deployment_name":   deploymentName,
			"cluster_name":      "e2e-test",
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
			"worker_count":      2,
			"gpu_type":          "nvidia-tesla-t4",
			"cluster_name":      "e2e-test",
			"environment_name":  "testing",
			"use_preemptible_workers": true, // Cost optimization
			"enable_host_external_ip":  true,
			"enable_worker_external_ip": true, // Enable for direct testing
			"grafana_allowed_ips": []string{"0.0.0.0/0"}, // Allow all for testing
			"ssh_allowed_ips":     []string{"0.0.0.0/0"}, // Allow all for testing
			"all_smi_interval":    3, // Faster collection for testing
			"host_machine_type":     "n1-standard-2", // Smaller for testing
			"worker_machine_type":   "n1-standard-1", // Smaller for testing
		}
	}

	t.Logf("Running E2E test for deployment type: %s", deploymentType)

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

	// Wait for services to be ready
	t.Log("Waiting for services to initialize...")
	time.Sleep(5 * time.Minute) // Give cloud-init time to run

	// Test Grafana accessibility
	testGrafanaAccessibility(t, terraformOptions)

	// Test VictoriaMetrics accessibility
	testVictoriaMetricsAccessibility(t, terraformOptions)

	if deploymentType == "training-cluster" {
		// Test worker metrics endpoints (only for training cluster)
		testWorkerMetricsEndpoints(t, terraformOptions)

		// Test metrics collection pipeline (more comprehensive for training cluster)
		testMetricsCollectionPipeline(t, terraformOptions, deploymentType)
	} else {
		// Test basic monitoring setup for host-only
		testHostOnlyMonitoring(t, terraformOptions)
	}
}

func testGrafanaAccessibility(t *testing.T, terraformOptions *terraform.Options) {
	t.Log("Testing Grafana accessibility...")

	grafanaURL := terraform.Output(t, terraformOptions, "grafana_url")
	require.NotEmpty(t, grafanaURL)

	// Test Grafana health endpoint
	healthURL := fmt.Sprintf("%s/api/health", grafanaURL)

	maxRetries := 20
	timeBetweenRetries := 30 * time.Second

	retry.DoWithRetry(t, "Check Grafana health", maxRetries, timeBetweenRetries, func() (string, error) {
		resp, err := http.Get(healthURL)
		if err != nil {
			return "", fmt.Errorf("failed to connect to Grafana: %v", err)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			return "", fmt.Errorf("Grafana health check failed with status: %d", resp.StatusCode)
		}

		t.Logf("✅ Grafana is accessible at %s", grafanaURL)
		return "Grafana is healthy", nil
	})
}

func testVictoriaMetricsAccessibility(t *testing.T, terraformOptions *terraform.Options) {
	t.Log("Testing VictoriaMetrics accessibility...")

	victoriaMetricsURL := terraform.Output(t, terraformOptions, "victoria_metrics_url")
	require.NotEmpty(t, victoriaMetricsURL)

	// Test VictoriaMetrics health endpoint
	healthURL := fmt.Sprintf("%s/health", victoriaMetricsURL)

	maxRetries := 20
	timeBetweenRetries := 30 * time.Second

	retry.DoWithRetry(t, "Check VictoriaMetrics health", maxRetries, timeBetweenRetries, func() (string, error) {
		resp, err := http.Get(healthURL)
		if err != nil {
			return "", fmt.Errorf("failed to connect to VictoriaMetrics: %v", err)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			return "", fmt.Errorf("VictoriaMetrics health check failed with status: %d", resp.StatusCode)
		}

		t.Logf("✅ VictoriaMetrics is accessible at %s", victoriaMetricsURL)
		return "VictoriaMetrics is healthy", nil
	})
}

func testWorkerMetricsEndpoints(t *testing.T, terraformOptions *terraform.Options) {
	t.Log("Testing worker metrics endpoints...")

	workerEndpoints := terraform.OutputList(t, terraformOptions, "worker_metrics_endpoints")
	require.NotEmpty(t, workerEndpoints)

	maxRetries := 30 // Workers need more time to start
	timeBetweenRetries := 30 * time.Second

	for i, endpoint := range workerEndpoints {
		endpoint := endpoint // capture for closure
		retry.DoWithRetry(t, fmt.Sprintf("Check worker %d metrics", i+1), maxRetries, timeBetweenRetries, func() (string, error) {
			resp, err := http.Get(endpoint)
			if err != nil {
				return "", fmt.Errorf("failed to connect to worker endpoint %s: %v", endpoint, err)
			}
			defer resp.Body.Close()

			if resp.StatusCode != http.StatusOK {
				return "", fmt.Errorf("worker metrics endpoint %s returned status: %d", endpoint, resp.StatusCode)
			}

			t.Logf("✅ Worker %d metrics accessible at %s", i+1, endpoint)
			return fmt.Sprintf("Worker %d is healthy", i+1), nil
		})
	}
}

func testHostOnlyMonitoring(t *testing.T, terraformOptions *terraform.Options) {
	t.Log("Testing host-only monitoring setup...")

	victoriaMetricsURL := terraform.Output(t, terraformOptions, "victoria_metrics_url")
	require.NotEmpty(t, victoriaMetricsURL)

	// Query VictoriaMetrics for basic metrics (should have host metrics)
	queryURL := fmt.Sprintf("%s/api/v1/query", victoriaMetricsURL)

	maxRetries := 20 // Give time for basic metrics to be collected
	timeBetweenRetries := 30 * time.Second

	// Test for basic host metrics that should always be present
	expectedMetrics := []string{
		"up", // Should show VictoriaMetrics itself
	}

	for _, metricName := range expectedMetrics {
		metricName := metricName // capture for closure
		retry.DoWithRetry(t, fmt.Sprintf("Check basic metric %s", metricName), maxRetries, timeBetweenRetries, func() (string, error) {
			// Query for the specific metric
			fullQueryURL := fmt.Sprintf("%s?query=%s", queryURL, metricName)

			resp, err := http.Get(fullQueryURL)
			if err != nil {
				return "", fmt.Errorf("failed to query metric %s: %v", metricName, err)
			}
			defer resp.Body.Close()

			if resp.StatusCode != http.StatusOK {
				return "", fmt.Errorf("metric query for %s failed with status: %d", metricName, resp.StatusCode)
			}

			t.Logf("✅ Basic metric %s is available for host-only monitoring", metricName)
			return fmt.Sprintf("Metric %s found", metricName), nil
		})
	}

	t.Log("✅ Host-only monitoring setup is working")
}

func testMetricsCollectionPipeline(t *testing.T, terraformOptions *terraform.Options, deploymentType string) {
	t.Log("Testing metrics collection pipeline...")

	victoriaMetricsURL := terraform.Output(t, terraformOptions, "victoria_metrics_url")
	require.NotEmpty(t, victoriaMetricsURL)

	// Query VictoriaMetrics for all-smi metrics
	queryURL := fmt.Sprintf("%s/api/v1/query", victoriaMetricsURL)

	maxRetries := 30 // Give time for metrics to be collected
	timeBetweenRetries := 30 * time.Second

	// Test for specific all-smi metrics
	expectedMetrics := []string{
		"all_smi_info",
		"all_smi_gpu_utilization",
		"all_smi_memory_utilization",
		"all_smi_cpu_utilization",
	}

	for _, metricName := range expectedMetrics {
		metricName := metricName // capture for closure
		retry.DoWithRetry(t, fmt.Sprintf("Check metric %s", metricName), maxRetries, timeBetweenRetries, func() (string, error) {
			// Query for the specific metric
			fullQueryURL := fmt.Sprintf("%s?query=%s", queryURL, metricName)

			resp, err := http.Get(fullQueryURL)
			if err != nil {
				return "", fmt.Errorf("failed to query metric %s: %v", metricName, err)
			}
			defer resp.Body.Close()

			if resp.StatusCode != http.StatusOK {
				return "", fmt.Errorf("metric query for %s failed with status: %d", metricName, resp.StatusCode)
			}

			// Read response body to check if we got data
			body := make([]byte, 1024)
			n, _ := resp.Body.Read(body)
			responseBody := string(body[:n])

			// Check if response contains data (not just empty result)
			if strings.Contains(responseBody, `"result":[]`) {
				return "", fmt.Errorf("no data found for metric %s", metricName)
			}

			t.Logf("✅ Metric %s is being collected", metricName)
			return fmt.Sprintf("Metric %s found", metricName), nil
		})
	}

	// Test that we can query for worker-specific metrics
	retry.DoWithRetry(t, "Check worker target metrics", maxRetries, timeBetweenRetries, func() (string, error) {
		// Query for up metric which should show targets
		fullQueryURL := fmt.Sprintf("%s?query=up", queryURL)

		resp, err := http.Get(fullQueryURL)
		if err != nil {
			return "", fmt.Errorf("failed to query up metric: %v", err)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			return "", fmt.Errorf("up metric query failed with status: %d", resp.StatusCode)
		}

		body := make([]byte, 2048)
		n, _ := resp.Body.Read(body)
		responseBody := string(body[:n])

		// Check if we have targets reporting
		if strings.Contains(responseBody, `"result":[]`) {
			return "", fmt.Errorf("no targets found in up metric")
		}

		// Look for job="all-smi" in the response
		if !strings.Contains(responseBody, `job":"all-smi"`) {
			return "", fmt.Errorf("all-smi job not found in targets")
		}

		t.Log("✅ Metrics collection pipeline is working")
		return "Pipeline is functional", nil
	})
}

func getEnvOrDefault(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}