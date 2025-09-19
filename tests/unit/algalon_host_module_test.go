package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

func TestAlgalonHostModule(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../terraform/modules/algalon-host",
		NoColor:      true,
		Vars: map[string]interface{}{
			"network_name":   "test-network",
			"subnet_name":    "test-subnet",
			"worker_targets": "worker1:9090,worker2:9090",
		},
	})

	// Test initialization and validation
	terraform.Init(t, terraformOptions)
	validationErr := terraform.ValidateE(t, terraformOptions)
	assert.NoError(t, validationErr)
}

func TestAlgalonHostConfiguration(t *testing.T) {
	t.Parallel()

	testCases := []struct {
		name           string
		instanceName   string
		machineType    string
		workerTargets  string
		clusterName    string
		environment    string
		enableExtIP    bool
		createStaticIP bool
	}{
		{
			name:           "Default Configuration",
			instanceName:   "algalon-monitoring",
			machineType:    "n1-standard-2",
			workerTargets:  "localhost:9090",
			clusterName:    "production",
			environment:    "gpu-cluster",
			enableExtIP:    true,
			createStaticIP: false,
		},
		{
			name:           "Production Configuration",
			instanceName:   "algalon-prod-monitoring",
			machineType:    "n1-standard-4",
			workerTargets:  "worker1:9090,worker2:9090,worker3:9090",
			clusterName:    "production",
			environment:    "ml-training",
			enableExtIP:    true,
			createStaticIP: true,
		},
		{
			name:           "Development Configuration",
			instanceName:   "algalon-dev-monitoring",
			machineType:    "n1-standard-1",
			workerTargets:  "localhost:9090",
			clusterName:    "development",
			environment:    "testing",
			enableExtIP:    false,
			createStaticIP: false,
		},
	}

	for _, tc := range testCases {
		tc := tc // capture range variable
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
				TerraformDir: "../../terraform/modules/algalon-host",
				NoColor:      true,
				Vars: map[string]interface{}{
					"instance_name":     tc.instanceName,
					"machine_type":      tc.machineType,
					"network_name":      "test-network",
					"subnet_name":       "test-subnet",
					"worker_targets":    tc.workerTargets,
					"cluster_name":      tc.clusterName,
					"environment_name":  tc.environment,
					"enable_external_ip": tc.enableExtIP,
					"create_static_ip":  tc.createStaticIP,
				},
			})

			terraform.Init(t, terraformOptions)
			plan := terraform.Plan(t, terraformOptions)

			// Verify main instance is planned
			terraform.RequirePlannedValuesMapKeyExists(t, plan, "google_compute_instance.algalon_host")

			// Verify instance configuration
			instanceName := terraform.GetPlannedValueForResource(t, plan, "google_compute_instance.algalon_host", "name")
			assert.Equal(t, tc.instanceName, instanceName)

			machineType := terraform.GetPlannedValueForResource(t, plan, "google_compute_instance.algalon_host", "machine_type")
			assert.Equal(t, tc.machineType, machineType)

			// Verify labels
			labels := terraform.GetPlannedValueForResource(t, plan, "google_compute_instance.algalon_host", "labels")
			labelsMap := labels.(map[string]interface{})
			assert.Equal(t, "algalon-host", labelsMap["component"])
			assert.Equal(t, tc.environment, labelsMap["environment"])
			assert.Equal(t, tc.clusterName, labelsMap["cluster"])

			// Verify static IP creation
			if tc.createStaticIP {
				terraform.RequirePlannedValuesMapKeyExists(t, plan, "google_compute_address.algalon_host_ip")
				terraform.RequirePlannedValuesMapKeyExists(t, plan, "google_compute_instance.algalon_host_with_static_ip")
			}
		})
	}
}

func TestAlgalonHostCloudInit(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../terraform/modules/algalon-host",
		NoColor:      true,
		Vars: map[string]interface{}{
			"network_name":     "test-network",
			"subnet_name":      "test-subnet",
			"worker_targets":   "worker1:9090,worker2:9090",
			"cluster_name":     "test-cluster",
			"environment_name": "test-env",
		},
	})

	terraform.Init(t, terraformOptions)
	plan := terraform.Plan(t, terraformOptions)

	// Verify that metadata contains user-data
	metadata := terraform.GetPlannedValueForResource(t, plan, "google_compute_instance.algalon_host", "metadata")
	metadataMap := metadata.(map[string]interface{})
	assert.Contains(t, metadataMap, "user-data")

	// Verify that cloud-init config contains expected values
	userData := metadataMap["user-data"].(string)
	assert.Contains(t, userData, "algalon_targets")
	assert.Contains(t, userData, "algalon_cluster")
	assert.Contains(t, userData, "algalon_environment")
	assert.Contains(t, userData, "worker1:9090,worker2:9090")
	assert.Contains(t, userData, "test-cluster")
	assert.Contains(t, userData, "test-env")
}

func TestAlgalonHostDiskConfiguration(t *testing.T) {
	t.Parallel()

	testCases := []struct {
		name         string
		bootDiskSize int
		bootDiskType string
	}{
		{
			name:         "Standard Disk",
			bootDiskSize: 50,
			bootDiskType: "pd-standard",
		},
		{
			name:         "SSD Disk",
			bootDiskSize: 100,
			bootDiskType: "pd-ssd",
		},
	}

	for _, tc := range testCases {
		tc := tc // capture range variable
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
				TerraformDir: "../../terraform/modules/algalon-host",
				NoColor:      true,
				Vars: map[string]interface{}{
					"network_name":     "test-network",
					"subnet_name":      "test-subnet",
					"boot_disk_size":   tc.bootDiskSize,
					"boot_disk_type":   tc.bootDiskType,
				},
			})

			terraform.Init(t, terraformOptions)
			plan := terraform.Plan(t, terraformOptions)

			// Verify boot disk configuration
			bootDisk := terraform.GetPlannedValueForResource(t, plan, "google_compute_instance.algalon_host", "boot_disk")
			bootDiskList := bootDisk.([]interface{})
			bootDiskMap := bootDiskList[0].(map[string]interface{})
			initParams := bootDiskMap["initialize_params"].([]interface{})
			initParamsMap := initParams[0].(map[string]interface{})

			assert.Equal(t, float64(tc.bootDiskSize), initParamsMap["size"])
			assert.Equal(t, tc.bootDiskType, initParamsMap["type"])
		})
	}
}