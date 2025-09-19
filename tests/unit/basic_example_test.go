package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

func TestBasicExampleValidation(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../terraform/examples/basic",
		NoColor:      true,
		Vars: map[string]interface{}{
			"project_id": "test-project-id",
		},
	})

	// Test initialization and validation
	terraform.Init(t, terraformOptions)
	validationErr := terraform.ValidateE(t, terraformOptions)
	assert.NoError(t, validationErr)
}

func TestBasicExamplePlan(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../terraform/examples/basic",
		NoColor:      true,
		Vars: map[string]interface{}{
			"project_id":        "test-project-id",
			"deployment_name":   "algalon-test",
			"worker_count":      2,
			"gpu_type":          "nvidia-tesla-t4",
			"cluster_name":      "test-cluster",
			"environment_name":  "test-env",
		},
	})

	terraform.Init(t, terraformOptions)
	plan := terraform.Plan(t, terraformOptions)

	// Verify that all modules are included in the plan
	terraform.RequirePlannedValuesMapKeyExists(t, plan, "module.network.google_compute_network.algalon_network")
	terraform.RequirePlannedValuesMapKeyExists(t, plan, "module.workers.google_compute_instance.algalon_worker[0]")
	terraform.RequirePlannedValuesMapKeyExists(t, plan, "module.workers.google_compute_instance.algalon_worker[1]")
	terraform.RequirePlannedValuesMapKeyExists(t, plan, "module.monitoring_host.google_compute_instance.algalon_host")
}

func TestBasicExampleWithCustomConfiguration(t *testing.T) {
	t.Parallel()

	testCases := []struct {
		name          string
		workerCount   int
		gpuType       string
		preemptible   bool
		staticIP      bool
		enableExtIP   bool
	}{
		{
			name:        "Minimal Configuration",
			workerCount: 1,
			gpuType:     "nvidia-tesla-t4",
			preemptible: true,
			staticIP:    false,
			enableExtIP: false,
		},
		{
			name:        "Production Configuration",
			workerCount: 3,
			gpuType:     "nvidia-tesla-v100",
			preemptible: false,
			staticIP:    true,
			enableExtIP: true,
		},
		{
			name:        "Development Configuration",
			workerCount: 2,
			gpuType:     "nvidia-tesla-t4",
			preemptible: true,
			staticIP:    false,
			enableExtIP: true,
		},
	}

	for _, tc := range testCases {
		tc := tc // capture range variable
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
				TerraformDir: "../../terraform/examples/basic",
				NoColor:      true,
				Vars: map[string]interface{}{
					"project_id":                  "test-project-id",
					"deployment_name":             "algalon-test",
					"worker_count":                tc.workerCount,
					"gpu_type":                    tc.gpuType,
					"use_preemptible_workers":     tc.preemptible,
					"create_static_ip":            tc.staticIP,
					"enable_host_external_ip":     tc.enableExtIP,
				},
			})

			terraform.Init(t, terraformOptions)
			plan := terraform.Plan(t, terraformOptions)

			// Verify correct number of workers
			for i := 0; i < tc.workerCount; i++ {
				workerKey := "module.workers.google_compute_instance.algalon_worker[" + string(rune(i+'0')) + "]"
				terraform.RequirePlannedValuesMapKeyExists(t, plan, workerKey)

				// Verify GPU type
				gpuAccelerator := terraform.GetPlannedValueForResource(t, plan, workerKey, "guest_accelerator")
				if gpuAccelerator != nil {
					acceleratorList := gpuAccelerator.([]interface{})
					if len(acceleratorList) > 0 {
						acceleratorMap := acceleratorList[0].(map[string]interface{})
						assert.Equal(t, tc.gpuType, acceleratorMap["type"])
					}
				}

				// Verify preemptible setting
				scheduling := terraform.GetPlannedValueForResource(t, plan, workerKey, "scheduling")
				schedulingList := scheduling.([]interface{})
				schedulingMap := schedulingList[0].(map[string]interface{})
				assert.Equal(t, tc.preemptible, schedulingMap["preemptible"])
			}

			// Verify static IP creation
			if tc.staticIP {
				terraform.RequirePlannedValuesMapKeyExists(t, plan, "module.monitoring_host.google_compute_address.algalon_host_ip[0]")
			}
		})
	}
}

func TestBasicExampleOutputs(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../terraform/examples/basic",
		NoColor:      true,
		Vars: map[string]interface{}{
			"project_id":      "test-project-id",
			"deployment_name": "algalon-test",
			"worker_count":    2,
		},
	})

	terraform.Init(t, terraformOptions)
	plan := terraform.Plan(t, terraformOptions)

	// Verify that outputs are defined
	outputs := terraform.GetTerraformOutput(t, terraformOptions, plan)

	// Check if output keys exist (values will be computed)
	expectedOutputs := []string{
		"grafana_url",
		"victoria_metrics_url",
		"monitoring_host_external_ip",
		"monitoring_host_internal_ip",
		"worker_internal_ips",
		"worker_external_ips",
		"worker_metrics_endpoints",
		"worker_targets",
		"network_name",
		"subnet_name",
		"ssh_commands",
		"deployment_summary",
	}

	for _, outputKey := range expectedOutputs {
		assert.Contains(t, outputs, outputKey, "Output %s should be defined", outputKey)
	}
}

func TestBasicExampleVariablesValidation(t *testing.T) {
	t.Parallel()

	testCases := []struct {
		name       string
		vars       map[string]interface{}
		shouldFail bool
	}{
		{
			name: "Valid minimal configuration",
			vars: map[string]interface{}{
				"project_id": "test-project-123",
			},
			shouldFail: false,
		},
		{
			name: "Valid full configuration",
			vars: map[string]interface{}{
				"project_id":        "test-project-123",
				"region":            "us-west1",
				"zones":             []string{"us-west1-a", "us-west1-b"},
				"deployment_name":   "algalon-prod",
				"worker_count":      3,
				"gpu_type":          "nvidia-tesla-v100",
				"all_smi_interval":  3,
			},
			shouldFail: false,
		},
		{
			name: "Invalid worker count",
			vars: map[string]interface{}{
				"project_id":   "test-project-123",
				"worker_count": -1,
			},
			shouldFail: true,
		},
	}

	for _, tc := range testCases {
		tc := tc // capture range variable
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
				TerraformDir: "../../terraform/examples/basic",
				NoColor:      true,
				Vars:         tc.vars,
			})

			terraform.Init(t, terraformOptions)

			if tc.shouldFail {
				_, err := terraform.PlanE(t, terraformOptions)
				assert.Error(t, err)
			} else {
				plan := terraform.Plan(t, terraformOptions)
				assert.NotNil(t, plan)
			}
		})
	}
}