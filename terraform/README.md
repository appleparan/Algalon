# Algalon Terraform Infrastructure

Infrastructure as Code for deploying Algalon GPU monitoring on Google Cloud Platform.

## Overview

This Terraform configuration provides automated deployment of Algalon infrastructure with:

- **Modular Design**: Reusable modules for network, monitoring host, and workers
- **Multiple Examples**: Basic, production, and multi-zone configurations
- **GPU Support**: Automated GPU instance provisioning with appropriate drivers
- **Cloud-Init Integration**: Automated software installation and configuration
- **Scalability**: Support for auto-scaling worker groups

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Monitoring    │    │     Worker      │    │     Worker      │
│     Host        │◄───┤      Node       │    │      Node       │
│                 │    │                 │    │                 │
│  ┌─────────────┐│    │ ┌─────────────┐ │    │ ┌─────────────┐ │
│  │   Grafana   ││    │ │   all-smi   │ │    │ │   all-smi   │ │
│  │   :3000     ││    │ │   :9090     │ │    │ │   :9090     │ │
│  └─────────────┘│    │ └─────────────┘ │    │ └─────────────┘ │
│  ┌─────────────┐│    │ ┌─────────────┐ │    │ ┌─────────────┐ │
│  │ VictoriaM.  ││    │ │    GPU      │ │    │ │    GPU      │ │
│  │   :8428     ││    │ │  Hardware   │ │    │ │  Hardware   │ │
│  └─────────────┘│    │ └─────────────┘ │    │ └─────────────┘ │
│  ┌─────────────┐│    └─────────────────┘    └─────────────────┘
│  │   VMAgent   ││
│  └─────────────┘│
└─────────────────┘
```

## Modules

### Network Module (`modules/network/`)
- VPC network and subnet creation
- Firewall rules for Grafana, SSH, and metrics collection
- Internal communication setup

### Algalon Host Module (`modules/algalon-host/`)
- Monitoring host with Grafana, VictoriaMetrics, VMAgent
- Cloud-init configuration for automated setup
- Static IP support for production

### Algalon Worker Module (`modules/algalon-worker/`)
- GPU-enabled worker instances
- all-smi metrics collection setup
- Managed instance groups with auto-scaling
- Preemptible instance support

## Examples

### [Basic Example](examples/basic/)
Simple deployment with 1 monitoring host and 2 workers.
```bash
cd examples/basic
terraform init
terraform apply
```

### [Production Example](examples/production/)
Production-ready setup with static IPs, restricted access, and managed instance groups.

### [Multi-Zone Example](examples/multi-zone/)
High-availability deployment across multiple zones with load balancing.

## Quick Start

### 1. Prerequisites

```bash
# Install required tools
gcloud auth application-default login
terraform --version  # >= 1.0 required

# Enable required APIs
gcloud services enable compute.googleapis.com
```

### 2. Basic Deployment

```bash
# Clone and navigate
git clone https://github.com/appleparan/Algalon.git
cd Algalon/terraform/examples/basic

# Configure
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project ID

# Deploy
terraform init
terraform plan
terraform apply
```

### 3. Access Grafana

```bash
# Get dashboard URL
terraform output grafana_url

# Default credentials: admin/admin
```

## Configuration

### Common Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `project_id` | GCP Project ID | Required |
| `region` | GCP Region | `us-central1` |
| `zones` | List of zones | `["us-central1-a"]` |
| `worker_count` | Number of workers | `2` |
| `gpu_type` | GPU type | `nvidia-tesla-t4` |
| `all_smi_interval` | Metrics interval (sec) | `5` |

### GPU Types

| Type | Use Case | Cost |
|------|----------|------|
| `nvidia-tesla-t4` | Inference, development | Low |
| `nvidia-tesla-v100` | Training, research | Medium |
| `nvidia-tesla-a100` | Large models, production | High |

### Security Configuration

```hcl
# Restrict access (recommended for production)
grafana_allowed_ips = ["YOUR_IP/32"]
ssh_allowed_ips = ["YOUR_OFFICE_CIDR/24"]
enable_worker_external_ip = false
```

## Advanced Features

### Auto-Scaling Workers

```hcl
module "workers" {
  source = "../../modules/algalon-worker"

  create_instance_group = true
  enable_autoscaling = true
  autoscaling_min_replicas = 2
  autoscaling_max_replicas = 10
  autoscaling_cpu_target = 0.8
}
```

### Preemptible Instances

```hcl
# Cost savings for non-critical workloads
use_preemptible_workers = true
```

### Custom all-smi Configuration

```hcl
all_smi_version = "v0.9.0"
all_smi_port = 9090
all_smi_interval = 3  # Faster collection
```

## Outputs

### Common Outputs

- `grafana_url`: Grafana dashboard URL
- `worker_metrics_endpoints`: List of worker metrics URLs
- `ssh_commands`: Commands to SSH into instances
- `deployment_summary`: Summary of deployed resources

### Example Usage

```bash
# Access Grafana
open $(terraform output -raw grafana_url)

# SSH to monitoring host
eval $(terraform output -raw ssh_commands.monitoring_host)

# Test worker metrics
curl $(terraform output -json worker_metrics_endpoints | jq -r '.[0]')
```

## Cost Optimization

### Development Setup
```hcl
use_preemptible_workers = true
worker_machine_type = "n1-standard-1"
gpu_type = "nvidia-tesla-t4"
worker_count = 1
```

### Production Setup
```hcl
use_preemptible_workers = false
worker_machine_type = "n1-standard-2"
gpu_type = "nvidia-tesla-v100"
create_static_ip = true
```

## Monitoring and Debugging

### Check Deployment Status

```bash
# List all instances
gcloud compute instances list --filter="labels.component:algalon"

# Check setup logs
gcloud compute ssh INSTANCE_NAME --command="sudo tail -f /var/log/algalon-setup.log"
```

### Verify Services

```bash
# Test worker metrics
curl -f http://WORKER_IP:9090/metrics

# Check Grafana
curl -f http://MONITORING_IP:3000/api/health
```

### Troubleshooting

1. **Setup Fails**: Check `/var/log/algalon-setup.log`
2. **No GPU Detected**: Verify GPU quota and instance type
3. **Network Issues**: Check firewall rules and VPC configuration
4. **Workers Not in Grafana**: Verify VMAgent targets configuration

## Migration from gcloud Commands

### Before (gcloud)
```bash
gcloud compute instances create algalon-host \
  --metadata="ALGALON_TARGETS=worker1:9090,worker2:9090"
```

### After (Terraform)
```hcl
module "monitoring_host" {
  source = "./modules/algalon-host"
  worker_targets = "worker1:9090,worker2:9090"
}
```

## Best Practices

### Production Deployment
1. Use dedicated service accounts
2. Restrict firewall rules to specific IPs
3. Enable static IPs for monitoring hosts
4. Use managed instance groups for workers
5. Set up monitoring and alerting

### Development
1. Use preemptible instances
2. Smaller machine types
3. Single zone deployment
4. Allow broader access for testing

### Security
1. Never use `0.0.0.0/0` for production
2. Use VPN or bastion hosts for access
3. Enable audit logging
4. Regular security reviews

## Integration

### CI/CD Pipeline

```yaml
# .github/workflows/deploy.yml
steps:
  - name: Terraform Apply
    run: |
      cd terraform/examples/production
      terraform init
      terraform plan
      terraform apply -auto-approve
```

### Monitoring Integration

```hcl
# Add custom labels for monitoring
labels = {
  team = "ml-ops"
  project = "gpu-cluster"
  cost_center = "research"
}
```

## Support

- [GitHub Issues](https://github.com/appleparan/Algalon/issues)
- [Main Documentation](../README.md)
- [Cloud Deployment Guide](../CLOUD_DEPLOYMENT.md)