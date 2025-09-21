package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

func TestAlgalonWorkerModule(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../terraform/modules/algalon-worker",
		NoColor:      true,
		Vars: map[string]interface{}{
			"network_name": "test-network",
			"subnet_name":  "test-subnet",
		},
	})

	// Test initialization and planning (includes validation)
	terraform.Init(t, terraformOptions)
	_, planErr := terraform.PlanE(t, terraformOptions)
	assert.NoError(t, planErr, "Algalon worker module should plan successfully")
}

func TestAlgalonWorkerConfiguration(t *testing.T) {
	t.Parallel()

	testCases := []struct {
		name            string
		instanceCount   int
		machineType     string
		gpuType         string
		gpuCount        int
		allSmiVersion   string
		allSmiPort      int
		allSmiInterval  int
		preemptible     bool
		enableExtIP     bool
	}{
		{
			name:           "Default Configuration",
			instanceCount:  1,
			machineType:    "n1-standard-1",
			gpuType:        "nvidia-tesla-t4",
			gpuCount:       1,
			allSmiVersion:  "v0.9.0",
			allSmiPort:     9090,
			allSmiInterval: 5,
			preemptible:    false,
			enableExtIP:    false,
		},
		{
			name:           "Multi-Worker Configuration",
			instanceCount:  3,
			machineType:    "n1-standard-2",
			gpuType:        "nvidia-tesla-v100",
			gpuCount:       2,
			allSmiVersion:  "v0.9.0",
			allSmiPort:     9091,
			allSmiInterval: 3,
			preemptible:    false,
			enableExtIP:    true,
		},
		{
			name:           "CPU-Only Configuration",
			instanceCount:  1,
			machineType:    "n1-standard-1",
			gpuType:        "",
			gpuCount:       0,
			allSmiVersion:  "v0.9.0",
			allSmiPort:     9090,
			allSmiInterval: 5,
			preemptible:    false,
			enableExtIP:    false,
		},
	}

	for _, tc := range testCases {
		tc := tc // capture range variable
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			vars := map[string]interface{}{
				"network_name":       "test-network",
				"subnet_name":        "test-subnet",
				"total_gpu_count":    tc.instanceCount * tc.gpuCount, // Calculate total GPUs
				"machine_type":       tc.machineType,
				"all_smi_version":    tc.allSmiVersion,
				"all_smi_port":       tc.allSmiPort,
				"all_smi_interval":   tc.allSmiInterval,
				"preemptible":        tc.preemptible,
				"enable_external_ip": tc.enableExtIP,
			}

			// Only add GPU config if GPU type is specified
			if tc.gpuType != "" {
				vars["gpu_type"] = tc.gpuType
				vars["gpus_per_instance"] = tc.gpuCount
			}

			terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
				TerraformDir: "../../terraform/modules/algalon-worker",
				NoColor:      true,
				Vars:         vars,
			})

			terraform.Init(t, terraformOptions)
			_, planErr := terraform.PlanE(t, terraformOptions)
			assert.NoError(t, planErr, "Algalon worker configuration '%s' should plan successfully", tc.name)
		})
	}
}

func TestAlgalonWorkerBasicPlan(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../terraform/modules/algalon-worker",
		NoColor:      true,
		Vars: map[string]interface{}{
			"network_name":     "test-network",
			"subnet_name":      "test-subnet",
			"all_smi_version":  "v0.9.0",
			"all_smi_port":     9091,
			"all_smi_interval": 3,
		},
	})

	terraform.Init(t, terraformOptions)

	// Test planning (includes validation)
	_, planErr := terraform.PlanE(t, terraformOptions)
	assert.NoError(t, planErr, "Algalon worker basic plan should succeed")
}

func TestAlgalonWorkerGPUAllocation(t *testing.T) {
	t.Parallel()

	testCases := []struct {
		name              string
		totalGPUs         int
		gpusPerInstance   int
		expectedInstances int
	}{
		{
			name:              "Single GPU",
			totalGPUs:         1,
			gpusPerInstance:   1,
			expectedInstances: 1,
		},
		{
			name:              "8 GPUs with 2 per instance",
			totalGPUs:         8,
			gpusPerInstance:   2,
			expectedInstances: 4,
		},
		{
			name:              "7 GPUs with 2 per instance (ceil)",
			totalGPUs:         7,
			gpusPerInstance:   2,
			expectedInstances: 4,
		},
	}

	for _, tc := range testCases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
				TerraformDir: "../../terraform/modules/algalon-worker",
				NoColor:      true,
				Vars: map[string]interface{}{
					"network_name":       "test-network",
					"subnet_name":        "test-subnet",
					"total_gpu_count":    tc.totalGPUs,
					"gpus_per_instance":  tc.gpusPerInstance,
					"gpu_type":           "nvidia-tesla-t4",
				},
			})

			terraform.Init(t, terraformOptions)

			// Test planning (includes validation)
			_, planErr := terraform.PlanE(t, terraformOptions)
			assert.NoError(t, planErr, "GPU allocation test case '%s' should plan successfully", tc.name)
		})
	}
}

func TestAlgalonWorkerLabels(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../terraform/modules/algalon-worker",
		NoColor:      true,
		Vars: map[string]interface{}{
			"network_name":     "test-network",
			"subnet_name":      "test-subnet",
			"cluster_name":     "test-cluster",
			"environment_name": "test-environment",
			"labels": map[string]interface{}{
				"team":        "ml-ops",
				"cost_center": "research",
			},
		},
	})

	terraform.Init(t, terraformOptions)

	// Test planning (includes validation)
	_, planErr := terraform.PlanE(t, terraformOptions)
	assert.NoError(t, planErr, "Algalon worker labels test should plan successfully")
}