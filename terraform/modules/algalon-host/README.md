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
| [google_compute_address.algalon_host_ip](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_address) | resource |
| [google_compute_instance.algalon_host](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_instance) | resource |
| [google_compute_image.cos_image](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/compute_image) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_boot_disk_size"></a> [boot\_disk\_size](#input\_boot\_disk\_size) | Size of the boot disk in GB | `number` | `50` | no |
| <a name="input_boot_disk_type"></a> [boot\_disk\_type](#input\_boot\_disk\_type) | Type of the boot disk | `string` | `"pd-standard"` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the cluster for labeling | `string` | `"production"` | no |
| <a name="input_enable_external_ip"></a> [enable\_external\_ip](#input\_enable\_external\_ip) | Whether to assign an external IP to the instance | `bool` | `true` | no |
| <a name="input_environment_name"></a> [environment\_name](#input\_environment\_name) | Environment name for labeling | `string` | `"gpu-cluster"` | no |
| <a name="input_instance_name"></a> [instance\_name](#input\_instance\_name) | Name of the monitoring host instance | `string` | `"algalon-monitoring-host"` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels to apply to the instance | `map(string)` | `{}` | no |
| <a name="input_machine_type"></a> [machine\_type](#input\_machine\_type) | Machine type for the monitoring host | `string` | `"n1-standard-2"` | no |
| <a name="input_network_name"></a> [network\_name](#input\_network\_name) | Name of the VPC network | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | GCP region for resources | `string` | `"us-central1"` | no |
| <a name="input_reserve_static_ip"></a> [reserve\_static\_ip](#input\_reserve\_static\_ip) | Reserve a static IP address (optional, for persistent IP) | `bool` | `false` | no |
| <a name="input_service_account_email"></a> [service\_account\_email](#input\_service\_account\_email) | Service account email for the instance | `string` | `null` | no |
| <a name="input_service_account_scopes"></a> [service\_account\_scopes](#input\_service\_account\_scopes) | Service account scopes for the instance | `list(string)` | <pre>[<br/>  "https://www.googleapis.com/auth/cloud-platform"<br/>]</pre> | no |
| <a name="input_subnet_name"></a> [subnet\_name](#input\_subnet\_name) | Name of the subnet | `string` | n/a | yes |
| <a name="input_worker_targets"></a> [worker\_targets](#input\_worker\_targets) | Comma-separated list of worker targets (host:port). Leave empty for host-only deployment | `string` | `""` | no |
| <a name="input_zone"></a> [zone](#input\_zone) | GCP zone for the instance | `string` | `"us-central1-a"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_external_ip"></a> [external\_ip](#output\_external\_ip) | External IP address of the monitoring host |
| <a name="output_grafana_url"></a> [grafana\_url](#output\_grafana\_url) | URL for the Grafana dashboard |
| <a name="output_instance_name"></a> [instance\_name](#output\_instance\_name) | Name of the created monitoring host instance |
| <a name="output_instance_self_link"></a> [instance\_self\_link](#output\_instance\_self\_link) | Self link of the created monitoring host instance |
| <a name="output_internal_ip"></a> [internal\_ip](#output\_internal\_ip) | Internal IP address of the monitoring host |
| <a name="output_static_ip_address"></a> [static\_ip\_address](#output\_static\_ip\_address) | Static IP address if created |
| <a name="output_victoria_metrics_url"></a> [victoria\_metrics\_url](#output\_victoria\_metrics\_url) | URL for VictoriaMetrics |
<!-- END_TF_DOCS -->