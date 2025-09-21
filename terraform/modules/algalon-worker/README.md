# Algalon Worker Module

This module creates GPU worker instances optimized for ML/AI training workloads. The module automatically calculates the required number of instances based on the total GPU count needed.

## Key Features

- **GPU-focused design**: Specify total GPU count, module calculates instance count
- **Single zone deployment**: All instances in same zone for optimal training communication
- **Automatic scaling**: `instance_count = ceil(total_gpu_count / gpus_per_instance)`
- **Training optimized**: No autoscaling or managed instance groups to avoid disruption

## Example Usage

```hcl
module "training_workers" {
  source = "./modules/algalon-worker"

  # Need 8 GPUs total with 2 GPUs per instance = 4 instances
  total_gpu_count    = 8
  gpus_per_instance  = 2
  gpu_type          = "nvidia-tesla-v100"

  network_name = "my-network"
  subnet_name  = "my-subnet"
  zone         = "us-central1-a"
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 7.3 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 7.3.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [google_compute_instance.algalon_worker](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_instance) | resource |
| [google_compute_image.cos_image](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/compute_image) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_all_smi_interval"></a> [all\_smi\_interval](#input\_all\_smi\_interval) | Metrics collection interval in seconds | `number` | `5` | no |
| <a name="input_all_smi_port"></a> [all\_smi\_port](#input\_all\_smi\_port) | Port for all-smi metrics endpoint | `number` | `9090` | no |
| <a name="input_all_smi_version"></a> [all\_smi\_version](#input\_all\_smi\_version) | Version of all-smi to install | `string` | `"v0.9.0"` | no |
| <a name="input_boot_disk_size"></a> [boot\_disk\_size](#input\_boot\_disk\_size) | Size of the boot disk in GB | `number` | `30` | no |
| <a name="input_boot_disk_type"></a> [boot\_disk\_type](#input\_boot\_disk\_type) | Type of the boot disk | `string` | `"pd-standard"` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the cluster for labeling | `string` | `"production"` | no |
| <a name="input_enable_external_ip"></a> [enable\_external\_ip](#input\_enable\_external\_ip) | Whether to assign external IP to instances | `bool` | `false` | no |
| <a name="input_environment_name"></a> [environment\_name](#input\_environment\_name) | Environment name for labeling | `string` | `"gpu-cluster"` | no |
| <a name="input_gpu_type"></a> [gpu\_type](#input\_gpu\_type) | Type of GPU to attach (e.g., nvidia-tesla-t4, nvidia-tesla-v100) | `string` | `null` | no |
| <a name="input_gpus_per_instance"></a> [gpus\_per\_instance](#input\_gpus\_per\_instance) | Number of GPUs to attach per instance | `number` | `1` | no |
| <a name="input_instance_name_prefix"></a> [instance\_name\_prefix](#input\_instance\_name\_prefix) | Prefix for worker instance names | `string` | `"algalon-worker"` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels to apply to instances | `map(string)` | `{}` | no |
| <a name="input_machine_type"></a> [machine\_type](#input\_machine\_type) | Machine type for worker instances | `string` | `"n1-standard-1"` | no |
| <a name="input_network_name"></a> [network\_name](#input\_network\_name) | Name of the VPC network | `string` | n/a | yes |
| <a name="input_preemptible"></a> [preemptible](#input\_preemptible) | Whether to create preemptible instances | `bool` | `false` | no |
| <a name="input_service_account_email"></a> [service\_account\_email](#input\_service\_account\_email) | Service account email for instances | `string` | `null` | no |
| <a name="input_service_account_scopes"></a> [service\_account\_scopes](#input\_service\_account\_scopes) | Service account scopes for instances | `list(string)` | <pre>[<br/>  "https://www.googleapis.com/auth/cloud-platform"<br/>]</pre> | no |
| <a name="input_subnet_name"></a> [subnet\_name](#input\_subnet\_name) | Name of the subnet | `string` | n/a | yes |
| <a name="input_total_gpu_count"></a> [total\_gpu\_count](#input\_total\_gpu\_count) | Total number of GPUs needed for training | `number` | `1` | no |
| <a name="input_zone"></a> [zone](#input\_zone) | GCP zone for worker instances (single zone for optimal training performance) | `string` | `"us-central1-a"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_external_ips"></a> [external\_ips](#output\_external\_ips) | External IP addresses of the worker instances (if enabled) |
| <a name="output_gpus_per_instance"></a> [gpus\_per\_instance](#output\_gpus\_per\_instance) | Number of GPUs per instance |
| <a name="output_instance_count"></a> [instance\_count](#output\_instance\_count) | Number of instances created |
| <a name="output_instance_names"></a> [instance\_names](#output\_instance\_names) | Names of the created worker instances |
| <a name="output_instance_self_links"></a> [instance\_self\_links](#output\_instance\_self\_links) | Self links of the created worker instances |
| <a name="output_internal_ips"></a> [internal\_ips](#output\_internal\_ips) | Internal IP addresses of the worker instances |
| <a name="output_metrics_endpoints"></a> [metrics\_endpoints](#output\_metrics\_endpoints) | Metrics endpoints for the worker instances |
| <a name="output_total_gpu_count"></a> [total\_gpu\_count](#output\_total\_gpu\_count) | Total number of GPUs allocated across all instances |
| <a name="output_worker_targets"></a> [worker\_targets](#output\_worker\_targets) | Comma-separated list of worker targets for monitoring host |
| <a name="output_zone"></a> [zone](#output\_zone) | Zone where worker instances are deployed |
