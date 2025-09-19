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
	validationErr := terraform.ValidateE(t, terraformOptions)
	assert.NoError(t, validationErr)
}

func TestAlgalonWorkerConfiguration(t *testing.T) {
	t.Parallel()

	testCases := []struct {
		name             string
		instanceCount    int
		machineType      string
		gpuType          string
		gpuCount         int
		allSmiVersion    string
		allSmiPort       int
		allSmiInterval   int
		preemptible      bool
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
			enableExtIP:   false,
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
			enableExtIP:   true,
		},
		{
			name:           "Preemptible Configuration",
			instanceCount:  2,
			machineType:    "n1-standard-1",
			gpuType:        "nvidia-tesla-t4",
			gpuCount:       1,
			allSmiVersion:  "v0.9.0",
			allSmiPort:     9090,
			allSmiInterval: 10,
			preemptible:    true,
			enableExtIP:   false,
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
			enableExtIP:   false,
		},
	}

	for _, tc := range testCases {
		tc := tc // capture range variable
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			vars := map[string]interface{}{
				"network_name":      "test-network",
				"subnet_name":       "test-subnet",
				"instance_count":    tc.instanceCount,
				"machine_type":      tc.machineType,
				"all_smi_version":   tc.allSmiVersion,
				"all_smi_port":      tc.allSmiPort,
				"all_smi_interval":  tc.allSmiInterval,
				"preemptible":       tc.preemptible,
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
			plan := terraform.Plan(t, terraformOptions)

			// Verify correct number of instances
			for i := 0; i < tc.instanceCount; i++ {
				resourceKey := "google_compute_instance.algalon_worker[" + string(rune(i+'0')) + "]"
				terraform.RequirePlannedValuesMapKeyExists(t, plan, resourceKey)

				// Verify machine type
				machineType := terraform.GetPlannedValueForResource(t, plan, resourceKey, "machine_type")
				assert.Equal(t, tc.machineType, machineType)

				// Verify preemptible setting
				scheduling := terraform.GetPlannedValueForResource(t, plan, resourceKey, "scheduling")
				schedulingList := scheduling.([]interface{})
				schedulingMap := schedulingList[0].(map[string]interface{})
				assert.Equal(t, tc.preemptible, schedulingMap["preemptible"])

				// Verify GPU configuration if specified
				if tc.gpuType != "" {
					guestAccelerator := terraform.GetPlannedValueForResource(t, plan, resourceKey, "guest_accelerator")
					acceleratorList := guestAccelerator.([]interface{})
					if len(acceleratorList) > 0 {
						acceleratorMap := acceleratorList[0].(map[string]interface{})
						assert.Equal(t, tc.gpuType, acceleratorMap["type"])
						assert.Equal(t, float64(tc.gpuCount), acceleratorMap["count"])
					}
				}
			}
		})
	}
}

func TestAlgalonWorkerCloudInit(t *testing.T) {
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
	plan := terraform.Plan(t, terraformOptions)

	// Verify that metadata contains user-data
	metadata := terraform.GetPlannedValueForResource(t, plan, "google_compute_instance.algalon_worker[0]", "metadata")
	metadataMap := metadata.(map[string]interface{})
	assert.Contains(t, metadataMap, "user-data")

	// Verify that cloud-init config contains expected values
	userData := metadataMap["user-data"].(string)
	assert.Contains(t, userData, "all_smi_version")
	assert.Contains(t, userData, "all_smi_port")
	assert.Contains(t, userData, "all_smi_interval")
	assert.Contains(t, userData, "v0.9.0")
	assert.Contains(t, userData, "9091")
	assert.Contains(t, userData, "3")
}

func TestAlgalonWorkerManagedInstanceGroup(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../terraform/modules/algalon-worker",
		NoColor:      true,
		Vars: map[string]interface{}{
			"network_name":           "test-network",
			"subnet_name":            "test-subnet",
			"create_instance_group":  true,
			"instance_group_size":    3,
			"enable_autoscaling":     true,
			"autoscaling_min_replicas": 2,
			"autoscaling_max_replicas": 10,
			"autoscaling_cpu_target":   0.8,
		},
	})

	terraform.Init(t, terraformOptions)
	plan := terraform.Plan(t, terraformOptions)

	// Verify managed instance group resources
	terraform.RequirePlannedValuesMapKeyExists(t, plan, "google_compute_instance_template.algalon_worker_template[0]")
	terraform.RequirePlannedValuesMapKeyExists(t, plan, "google_compute_instance_group_manager.algalon_worker_group[0]")
	terraform.RequirePlannedValuesMapKeyExists(t, plan, "google_compute_health_check.algalon_worker_health[0]")
	terraform.RequirePlannedValuesMapKeyExists(t, plan, "google_compute_autoscaler.algalon_worker_autoscaler[0]")

	// Verify instance group size
	targetSize := terraform.GetPlannedValueForResource(t, plan, "google_compute_instance_group_manager.algalon_worker_group[0]", "target_size")
	assert.Equal(t, float64(3), targetSize)

	// Verify autoscaler configuration
	autoscalingPolicy := terraform.GetPlannedValueForResource(t, plan, "google_compute_autoscaler.algalon_worker_autoscaler[0]", "autoscaling_policy")
	policyList := autoscalingPolicy.([]interface{})
	policyMap := policyList[0].(map[string]interface{})
	assert.Equal(t, float64(2), policyMap["min_replicas"])
	assert.Equal(t, float64(10), policyMap["max_replicas"])
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
	plan := terraform.Plan(t, terraformOptions)

	// Verify labels
	labels := terraform.GetPlannedValueForResource(t, plan, "google_compute_instance.algalon_worker[0]", "labels")
	labelsMap := labels.(map[string]interface{})

	assert.Equal(t, "algalon-worker", labelsMap["component"])
	assert.Equal(t, "test-environment", labelsMap["environment"])
	assert.Equal(t, "test-cluster", labelsMap["cluster"])
	assert.Equal(t, "1", labelsMap["worker_index"])
	assert.Equal(t, "ml-ops", labelsMap["team"])
	assert.Equal(t, "research", labelsMap["cost_center"])
}