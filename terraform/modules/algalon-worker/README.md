<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 5.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | ~> 5.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [google_compute_autoscaler.algalon_worker_autoscaler](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_autoscaler) | resource |
| [google_compute_health_check.algalon_worker_health](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_health_check) | resource |
| [google_compute_instance.algalon_worker](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_instance) | resource |
| [google_compute_instance_group_manager.algalon_worker_group](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_instance_group_manager) | resource |
| [google_compute_instance_template.algalon_worker_template](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_instance_template) | resource |
| [google_compute_image.cos_image](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/compute_image) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_all_smi_interval"></a> [all\_smi\_interval](#input\_all\_smi\_interval) | Metrics collection interval in seconds | `number` | `5` | no |
| <a name="input_all_smi_port"></a> [all\_smi\_port](#input\_all\_smi\_port) | Port for all-smi metrics endpoint | `number` | `9090` | no |
| <a name="input_all_smi_version"></a> [all\_smi\_version](#input\_all\_smi\_version) | Version of all-smi to install | `string` | `"v0.9.0"` | no |
| <a name="input_autoscaling_cooldown"></a> [autoscaling\_cooldown](#input\_autoscaling\_cooldown) | Cooldown period for autoscaling in seconds | `number` | `300` | no |
| <a name="input_autoscaling_cpu_target"></a> [autoscaling\_cpu\_target](#input\_autoscaling\_cpu\_target) | Target CPU utilization for autoscaling | `number` | `0.8` | no |
| <a name="input_autoscaling_max_replicas"></a> [autoscaling\_max\_replicas](#input\_autoscaling\_max\_replicas) | Maximum number of replicas for autoscaling | `number` | `10` | no |
| <a name="input_autoscaling_min_replicas"></a> [autoscaling\_min\_replicas](#input\_autoscaling\_min\_replicas) | Minimum number of replicas for autoscaling | `number` | `1` | no |
| <a name="input_boot_disk_size"></a> [boot\_disk\_size](#input\_boot\_disk\_size) | Size of the boot disk in GB | `number` | `30` | no |
| <a name="input_boot_disk_type"></a> [boot\_disk\_type](#input\_boot\_disk\_type) | Type of the boot disk | `string` | `"pd-standard"` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the cluster for labeling | `string` | `"production"` | no |
| <a name="input_create_instance_group"></a> [create\_instance\_group](#input\_create\_instance\_group) | Whether to create a managed instance group | `bool` | `false` | no |
| <a name="input_enable_autoscaling"></a> [enable\_autoscaling](#input\_enable\_autoscaling) | Whether to enable autoscaling for the instance group | `bool` | `false` | no |
| <a name="input_enable_external_ip"></a> [enable\_external\_ip](#input\_enable\_external\_ip) | Whether to assign external IP to instances | `bool` | `false` | no |
| <a name="input_environment_name"></a> [environment\_name](#input\_environment\_name) | Environment name for labeling | `string` | `"gpu-cluster"` | no |
| <a name="input_gpu_count"></a> [gpu\_count](#input\_gpu\_count) | Number of GPUs to attach per instance | `number` | `1` | no |
| <a name="input_gpu_type"></a> [gpu\_type](#input\_gpu\_type) | Type of GPU to attach (e.g., nvidia-tesla-t4, nvidia-tesla-v100) | `string` | `null` | no |
| <a name="input_instance_count"></a> [instance\_count](#input\_instance\_count) | Number of worker instances to create | `number` | `1` | no |
| <a name="input_instance_group_size"></a> [instance\_group\_size](#input\_instance\_group\_size) | Target size for the managed instance group | `number` | `3` | no |
| <a name="input_instance_name_prefix"></a> [instance\_name\_prefix](#input\_instance\_name\_prefix) | Prefix for worker instance names | `string` | `"algalon-worker"` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels to apply to instances | `map(string)` | `{}` | no |
| <a name="input_machine_type"></a> [machine\_type](#input\_machine\_type) | Machine type for worker instances | `string` | `"n1-standard-1"` | no |
| <a name="input_network_name"></a> [network\_name](#input\_network\_name) | Name of the VPC network | `string` | n/a | yes |
| <a name="input_preemptible"></a> [preemptible](#input\_preemptible) | Whether to create preemptible instances | `bool` | `false` | no |
| <a name="input_service_account_email"></a> [service\_account\_email](#input\_service\_account\_email) | Service account email for instances | `string` | `null` | no |
| <a name="input_service_account_scopes"></a> [service\_account\_scopes](#input\_service\_account\_scopes) | Service account scopes for instances | `list(string)` | <pre>[<br/>  "https://www.googleapis.com/auth/cloud-platform"<br/>]</pre> | no |
| <a name="input_subnet_name"></a> [subnet\_name](#input\_subnet\_name) | Name of the subnet | `string` | n/a | yes |
| <a name="input_zones"></a> [zones](#input\_zones) | List of GCP zones for worker instances | `list(string)` | <pre>[<br/>  "us-central1-a"<br/>]</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_autoscaler_self_link"></a> [autoscaler\_self\_link](#output\_autoscaler\_self\_link) | Self link of the autoscaler (if created) |
| <a name="output_external_ips"></a> [external\_ips](#output\_external\_ips) | External IP addresses of the worker instances (if enabled) |
| <a name="output_health_check_self_link"></a> [health\_check\_self\_link](#output\_health\_check\_self\_link) | Self link of the health check (if created) |
| <a name="output_instance_group_manager"></a> [instance\_group\_manager](#output\_instance\_group\_manager) | Name of the managed instance group (if created) |
| <a name="output_instance_group_self_link"></a> [instance\_group\_self\_link](#output\_instance\_group\_self\_link) | Self link of the managed instance group (if created) |
| <a name="output_instance_names"></a> [instance\_names](#output\_instance\_names) | Names of the created worker instances |
| <a name="output_instance_self_links"></a> [instance\_self\_links](#output\_instance\_self\_links) | Self links of the created worker instances |
| <a name="output_internal_ips"></a> [internal\_ips](#output\_internal\_ips) | Internal IP addresses of the worker instances |
| <a name="output_metrics_endpoints"></a> [metrics\_endpoints](#output\_metrics\_endpoints) | Metrics endpoints for the worker instances |
| <a name="output_worker_targets"></a> [worker\_targets](#output\_worker\_targets) | Comma-separated list of worker targets for monitoring host |
| <a name="output_zones"></a> [zones](#output\_zones) | Zones where worker instances are deployed |
<!-- END_TF_DOCS -->