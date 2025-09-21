<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 7.3 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 5.45.2 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [google_compute_firewall.algalon_grafana](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_firewall) | resource |
| [google_compute_firewall.algalon_internal](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_firewall) | resource |
| [google_compute_firewall.algalon_metrics_internal](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_firewall) | resource |
| [google_compute_firewall.algalon_ssh](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_firewall) | resource |
| [google_compute_firewall.algalon_victoria_metrics](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_firewall) | resource |
| [google_compute_network.algalon_network](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_network) | resource |
| [google_compute_subnetwork.algalon_subnet](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_subnetwork) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_enable_external_victoria_metrics"></a> [enable\_external\_victoria\_metrics](#input\_enable\_external\_victoria\_metrics) | Whether to allow external access to VictoriaMetrics | `bool` | `false` | no |
| <a name="input_enable_ssh_access"></a> [enable\_ssh\_access](#input\_enable\_ssh\_access) | Whether to allow SSH access to instances | `bool` | `true` | no |
| <a name="input_grafana_allowed_ips"></a> [grafana\_allowed\_ips](#input\_grafana\_allowed\_ips) | List of IP ranges allowed to access Grafana | `list(string)` | <pre>[<br/>  "35.235.240.0/20"<br/>]</pre> | no |
| <a name="input_network_name"></a> [network\_name](#input\_network\_name) | Name of the VPC network | `string` | `"algalon-network"` | no |
| <a name="input_region"></a> [region](#input\_region) | GCP region for the subnet | `string` | `"us-central1"` | no |
| <a name="input_ssh_allowed_ips"></a> [ssh\_allowed\_ips](#input\_ssh\_allowed\_ips) | List of IP ranges allowed SSH access | `list(string)` | <pre>[<br/>  "35.235.240.0/20"<br/>]</pre> | no |
| <a name="input_subnet_cidr"></a> [subnet\_cidr](#input\_subnet\_cidr) | CIDR block for the subnet | `string` | `"10.1.0.0/16"` | no |
| <a name="input_victoria_metrics_allowed_ips"></a> [victoria\_metrics\_allowed\_ips](#input\_victoria\_metrics\_allowed\_ips) | List of IP ranges allowed to access VictoriaMetrics | `list(string)` | <pre>[<br/>  "35.235.240.0/20"<br/>]</pre> | no |
| <a name="input_worker_ports"></a> [worker\_ports](#input\_worker\_ports) | List of ports used by worker nodes for metrics | `list(string)` | <pre>[<br/>  "9090"<br/>]</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_network_name"></a> [network\_name](#output\_network\_name) | Name of the created VPC network |
| <a name="output_network_self_link"></a> [network\_self\_link](#output\_network\_self\_link) | Self link of the created VPC network |
| <a name="output_subnet_cidr"></a> [subnet\_cidr](#output\_subnet\_cidr) | CIDR block of the created subnet |
| <a name="output_subnet_name"></a> [subnet\_name](#output\_subnet\_name) | Name of the created subnet |
| <a name="output_subnet_self_link"></a> [subnet\_self\_link](#output\_subnet\_self\_link) | Self link of the created subnet |
<!-- END_TF_DOCS -->