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

	// Test initialization and validation
	terraform.Init(t, terraformOptions)
	_, validationErr := terraform.ValidateE(t, terraformOptions)
	assert.NoError(t, validationErr)
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
				"instance_count":     tc.instanceCount,
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
				vars["gpu_count"] = tc.gpuCount
			}

			terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
				TerraformDir: "../../terraform/modules/algalon-worker",
				NoColor:      true,
				Vars:         vars,
			})

			terraform.Init(t, terraformOptions)
			_, planErr := terraform.PlanE(t, terraformOptions)
			assert.NoError(t, planErr)

			// Test basic validation - plan should succeed
			// For detailed resource validation, consider using terraform show with JSON output
			// or implement infrastructure tests after apply
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
	_, validationErr := terraform.ValidateE(t, terraformOptions)
	assert.NoError(t, validationErr)

	// Test planning
	_, planErr := terraform.PlanE(t, terraformOptions)
	assert.NoError(t, planErr)
}

func TestAlgalonWorkerManagedInstanceGroup(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../terraform/modules/algalon-worker",
		NoColor:      true,
		Vars: map[string]interface{}{
			"network_name":             "test-network",
			"subnet_name":              "test-subnet",
			"create_instance_group":    true,
			"instance_group_size":      3,
			"enable_autoscaling":       true,
			"autoscaling_min_replicas": 2,
			"autoscaling_max_replicas": 10,
			"autoscaling_cpu_target":   0.8,
		},
	})

	terraform.Init(t, terraformOptions)
	_, validationErr := terraform.ValidateE(t, terraformOptions)
	assert.NoError(t, validationErr)

	// Test planning
	_, planErr := terraform.PlanE(t, terraformOptions)
	assert.NoError(t, planErr)
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
	_, validationErr := terraform.ValidateE(t, terraformOptions)
	assert.NoError(t, validationErr)

	// Test planning
	_, planErr := terraform.PlanE(t, terraformOptions)
	assert.NoError(t, planErr)
}