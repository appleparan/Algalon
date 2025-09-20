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
	_, validationErr := terraform.ValidateE(t, terraformOptions)
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
		reserveStaticIP bool
	}{
		{
			name:            "Default Configuration",
			instanceName:    "algalon-monitoring",
			machineType:     "n1-standard-2",
			workerTargets:   "localhost:9090",
			clusterName:     "production",
			environment:     "gpu-cluster",
			enableExtIP:     true,
			reserveStaticIP: false,
		},
		{
			name:            "Production Configuration",
			instanceName:    "algalon-prod-monitoring",
			machineType:     "n1-standard-4",
			workerTargets:   "worker1:9090,worker2:9090,worker3:9090",
			clusterName:     "production",
			environment:     "ml-training",
			enableExtIP:     true,
			reserveStaticIP: true,
		},
		{
			name:            "Development Configuration",
			instanceName:    "algalon-dev-monitoring",
			machineType:     "n1-standard-1",
			workerTargets:   "localhost:9090",
			clusterName:     "development",
			environment:     "testing",
			enableExtIP:     false,
			reserveStaticIP: false,
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
					"instance_name":      tc.instanceName,
					"machine_type":       tc.machineType,
					"network_name":       "test-network",
					"subnet_name":        "test-subnet",
					"worker_targets":     tc.workerTargets,
					"cluster_name":       tc.clusterName,
					"environment_name":   tc.environment,
					"enable_external_ip": tc.enableExtIP,
					"reserve_static_ip":  tc.reserveStaticIP,
				},
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

func TestAlgalonHostBasicPlan(t *testing.T) {
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
	_, validationErr := terraform.ValidateE(t, terraformOptions)
	assert.NoError(t, validationErr)

	// Test planning
	_, planErr := terraform.PlanE(t, terraformOptions)
	assert.NoError(t, planErr)
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
					"network_name":   "test-network",
					"subnet_name":    "test-subnet",
					"boot_disk_size": tc.bootDiskSize,
					"boot_disk_type": tc.bootDiskType,
				},
			})

			terraform.Init(t, terraformOptions)
			_, validationErr := terraform.ValidateE(t, terraformOptions)
			assert.NoError(t, validationErr)

			// Test planning
			_, planErr := terraform.PlanE(t, terraformOptions)
			assert.NoError(t, planErr)
		})
	}
}