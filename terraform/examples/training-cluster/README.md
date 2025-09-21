# Training Cluster Example

This example demonstrates how to deploy Algalon for ML/AI training workloads. It creates a monitoring host and optionally GPU worker instances for distributed training.

## Deployment Modes

### 1. Host-Only Deployment (Default)

By default, only the monitoring host is deployed. This is useful for:
- Setting up monitoring infrastructure first
- Hybrid scenarios where workers are managed separately
- Development and testing

```bash
terraform apply
# Creates only monitoring host (worker_count = 0)
```

### 2. Full Training Cluster

To deploy with GPU workers for training:

```bash
terraform apply -var="worker_count=4" -var="gpu_count=2"
# Creates monitoring host + 4 workers with 2 GPUs each = 8 total GPUs
```

## Key Features

- **GPU-optimized**: Automatic instance calculation based on total GPU needs
- **Single zone deployment**: All workers in same zone for optimal training performance
- **Flexible scaling**: Easily adjust total GPU count by changing worker_count
- **Monitoring included**: Grafana and VictoriaMetrics for comprehensive observability

## Usage Examples

### Small Training Setup (2 GPUs)
```hcl
worker_count = 1
gpu_count = 2
gpu_type = "nvidia-tesla-t4"
```

### Large Training Setup (16 GPUs)
```hcl
worker_count = 4
gpu_count = 4
gpu_type = "nvidia-tesla-v100"
```

### Cost-Optimized with Preemptible Instances
```hcl
worker_count = 2
gpu_count = 2
use_preemptible_workers = true
```

## Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `worker_count` | Number of worker instances | `0` (host-only) |
| `gpu_count` | GPUs per worker instance | `1` |
| `gpu_type` | GPU type (e.g., nvidia-tesla-t4) | `null` |
| `worker_machine_type` | Worker machine type | `n1-standard-1` |

## Outputs

After deployment, you'll get:
- Grafana URL for monitoring dashboard
- VictoriaMetrics URL for metrics access
- SSH commands for accessing instances
- Worker endpoints for training job submission

## Getting Started

1. **Copy example configuration:**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Set your project ID:**
   ```bash
   echo 'project_id = "your-gcp-project"' >> terraform.tfvars
   ```

3. **Deploy host-only first:**
   ```bash
   terraform init
   terraform apply
   ```

4. **Add workers when ready:**
   ```bash
   echo 'worker_count = 2' >> terraform.tfvars
   terraform apply
   ```

## Architecture

```
┌─────────────────┐    ┌─────────────────┐
│ Monitoring Host │    │   Worker 1      │
│  - Grafana      │◄───┤  - GPU x2       │
│  - VictoriaM.   │    │  - all-smi      │
└─────────────────┘    └─────────────────┘
         ▲               ┌─────────────────┐
         └───────────────┤   Worker 2      │
                         │  - GPU x2       │
                         │  - all-smi      │
                         └─────────────────┘
```

The monitoring host collects metrics from all workers and provides unified observability for your training infrastructure.
<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 7.3 |

## Providers

No providers.

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_monitoring_host"></a> [monitoring\_host](#module\_monitoring\_host) | ../../modules/algalon-host | n/a |
| <a name="module_network"></a> [network](#module\_network) | ../../modules/network | n/a |
| <a name="module_workers"></a> [workers](#module\_workers) | ../../modules/algalon-worker | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_all_smi_interval"></a> [all\_smi\_interval](#input\_all\_smi\_interval) | Metrics collection interval in seconds | `number` | `5` | no |
| <a name="input_all_smi_port"></a> [all\_smi\_port](#input\_all\_smi\_port) | all-smi metrics port | `number` | `9090` | no |
| <a name="input_all_smi_version"></a> [all\_smi\_version](#input\_all\_smi\_version) | all-smi version | `string` | `"v0.9.0"` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Cluster name for labeling | `string` | `"production"` | no |
| <a name="input_deployment_name"></a> [deployment\_name](#input\_deployment\_name) | Name prefix for all resources | `string` | `"algalon"` | no |
| <a name="input_enable_external_victoria_metrics"></a> [enable\_external\_victoria\_metrics](#input\_enable\_external\_victoria\_metrics) | Enable external access to VictoriaMetrics | `bool` | `false` | no |
| <a name="input_enable_host_external_ip"></a> [enable\_host\_external\_ip](#input\_enable\_host\_external\_ip) | Enable external IP for monitoring host | `bool` | `true` | no |
| <a name="input_enable_ssh_access"></a> [enable\_ssh\_access](#input\_enable\_ssh\_access) | Enable SSH access to instances | `bool` | `true` | no |
| <a name="input_enable_worker_external_ip"></a> [enable\_worker\_external\_ip](#input\_enable\_worker\_external\_ip) | Enable external IP for workers | `bool` | `false` | no |
| <a name="input_environment_name"></a> [environment\_name](#input\_environment\_name) | Environment name | `string` | `"gpu-cluster"` | no |
| <a name="input_gpu_count"></a> [gpu\_count](#input\_gpu\_count) | Number of GPUs per worker | `number` | `1` | no |
| <a name="input_gpu_type"></a> [gpu\_type](#input\_gpu\_type) | GPU type (e.g., nvidia-tesla-t4, nvidia-tesla-v100) | `string` | `"nvidia-tesla-t4"` | no |
| <a name="input_grafana_allowed_ips"></a> [grafana\_allowed\_ips](#input\_grafana\_allowed\_ips) | List of IP ranges allowed to access Grafana | `list(string)` | <pre>[<br/>  "35.235.240.0/20"<br/>]</pre> | no |
| <a name="input_host_boot_disk_size"></a> [host\_boot\_disk\_size](#input\_host\_boot\_disk\_size) | Host boot disk size in GB | `number` | `50` | no |
| <a name="input_host_machine_type"></a> [host\_machine\_type](#input\_host\_machine\_type) | Machine type for monitoring host | `string` | `"n1-standard-2"` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels to apply to all resources | `map(string)` | <pre>{<br/>  "managed_by": "terraform",<br/>  "project": "algalon"<br/>}</pre> | no |
| <a name="input_network_name"></a> [network\_name](#input\_network\_name) | Name of the VPC network | `string` | `"algalon-network"` | no |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | GCP project ID | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | GCP region | `string` | `"us-central1"` | no |
| <a name="input_reserve_static_ip"></a> [reserve\_static\_ip](#input\_reserve\_static\_ip) | Reserve static IP for monitoring host | `bool` | `false` | no |
| <a name="input_ssh_allowed_ips"></a> [ssh\_allowed\_ips](#input\_ssh\_allowed\_ips) | List of IP ranges allowed for SSH access | `list(string)` | <pre>[<br/>  "35.235.240.0/20"<br/>]</pre> | no |
| <a name="input_subnet_cidr"></a> [subnet\_cidr](#input\_subnet\_cidr) | CIDR block for the subnet | `string` | `"10.1.0.0/16"` | no |
| <a name="input_use_preemptible_workers"></a> [use\_preemptible\_workers](#input\_use\_preemptible\_workers) | Use preemptible instances for workers | `bool` | `false` | no |
| <a name="input_worker_boot_disk_size"></a> [worker\_boot\_disk\_size](#input\_worker\_boot\_disk\_size) | Worker boot disk size in GB | `number` | `30` | no |
| <a name="input_worker_count"></a> [worker\_count](#input\_worker\_count) | Number of worker instances (used to calculate total GPU count = worker\_count * gpu\_count). Set to 0 for host-only deployment. | `number` | `0` | no |
| <a name="input_worker_machine_type"></a> [worker\_machine\_type](#input\_worker\_machine\_type) | Machine type for worker instances | `string` | `"n1-standard-1"` | no |
| <a name="input_zones"></a> [zones](#input\_zones) | List of GCP zones | `list(string)` | <pre>[<br/>  "us-central1-a",<br/>  "us-central1-b"<br/>]</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_deployment_summary"></a> [deployment\_summary](#output\_deployment\_summary) | Summary of the deployed infrastructure |
| <a name="output_grafana_url"></a> [grafana\_url](#output\_grafana\_url) | URL to access Grafana dashboard |
| <a name="output_monitoring_host_external_ip"></a> [monitoring\_host\_external\_ip](#output\_monitoring\_host\_external\_ip) | External IP of monitoring host |
| <a name="output_monitoring_host_internal_ip"></a> [monitoring\_host\_internal\_ip](#output\_monitoring\_host\_internal\_ip) | Internal IP of monitoring host |
| <a name="output_network_name"></a> [network\_name](#output\_network\_name) | Name of the created VPC network |
| <a name="output_ssh_commands"></a> [ssh\_commands](#output\_ssh\_commands) | SSH commands to connect to instances |
| <a name="output_subnet_name"></a> [subnet\_name](#output\_subnet\_name) | Name of the created subnet |
| <a name="output_victoria_metrics_url"></a> [victoria\_metrics\_url](#output\_victoria\_metrics\_url) | URL to access VictoriaMetrics |
| <a name="output_worker_external_ips"></a> [worker\_external\_ips](#output\_worker\_external\_ips) | External IPs of worker instances |
| <a name="output_worker_internal_ips"></a> [worker\_internal\_ips](#output\_worker\_internal\_ips) | Internal IPs of worker instances |
| <a name="output_worker_metrics_endpoints"></a> [worker\_metrics\_endpoints](#output\_worker\_metrics\_endpoints) | Metrics endpoints for worker instances |
| <a name="output_worker_targets"></a> [worker\_targets](#output\_worker\_targets) | Worker targets configured for monitoring |
<!-- END_TF_DOCS -->