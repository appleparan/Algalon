# Algalon Basic Terraform Example

This example demonstrates a basic Algalon deployment with:
- 1 monitoring host (Grafana + VictoriaMetrics + VMAgent)
- 2 worker nodes with GPU support
- VPC network with appropriate firewall rules

## Prerequisites

1. **Google Cloud SDK** installed and configured
2. **Terraform** >= 1.0 installed
3. **GCP Project** with required APIs enabled:
   ```bash
   gcloud services enable compute.googleapis.com
   gcloud services enable container.googleapis.com
   ```
4. **GPU Quota** in your project (if using GPUs)

## Quick Start

### 1. Setup

```bash
# Clone the repository
git clone https://github.com/inureyes/Algalon.git
cd Algalon/terraform/examples/basic

# Copy and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project ID and preferences
```

### 2. Deploy

```bash
# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Deploy infrastructure
terraform apply
```

### 3. Access Grafana

After deployment completes (takes 5-10 minutes):

```bash
# Get Grafana URL
terraform output grafana_url

# Default credentials
# Username: admin
# Password: admin
```

### 4. Verify Workers

```bash
# Check worker metrics endpoints
terraform output worker_metrics_endpoints

# Test a worker endpoint
curl -f http://WORKER_IP:9090/metrics
```

## Configuration

### Basic Variables

Edit `terraform.tfvars`:

```hcl
project_id = "your-gcp-project-id"
deployment_name = "algalon-demo"
worker_count = 2
gpu_type = "nvidia-tesla-t4"
```

### Security Configuration

For production, restrict access:

```hcl
grafana_allowed_ips = ["YOUR_IP/32"]
ssh_allowed_ips = ["YOUR_IP/32"]
enable_worker_external_ip = false
```

### Cost Optimization

For development/testing:

```hcl
use_preemptible_workers = true
worker_machine_type = "n1-standard-1"
gpu_type = "nvidia-tesla-t4"  # Cheaper than V100
```

## Outputs

| Output | Description |
|--------|-------------|
| `grafana_url` | URL to access Grafana dashboard |
| `victoria_metrics_url` | URL to VictoriaMetrics |
| `worker_metrics_endpoints` | List of worker metrics endpoints |
| `ssh_commands` | Commands to SSH into instances |

## Customization

### Different GPU Types

```hcl
# Tesla T4 (cheaper, good for inference)
gpu_type = "nvidia-tesla-t4"

# Tesla V100 (more powerful, good for training)
gpu_type = "nvidia-tesla-v100"

# A100 (latest, most powerful)
gpu_type = "nvidia-tesla-a100"
```

### Multiple Zones

```hcl
zones = ["us-central1-a", "us-central1-b", "us-central1-c"]
worker_count = 6  # Will distribute across zones
```

### Custom all-smi Configuration

```hcl
all_smi_version = "v0.9.0"
all_smi_port = 9090
all_smi_interval = 3  # Faster collection for real-time monitoring
```

## Cleanup

```bash
# Destroy all resources
terraform destroy
```

## Troubleshooting

### Common Issues

1. **GPU Quota Exceeded**
   ```bash
   gcloud compute project-info describe --project=YOUR_PROJECT
   # Check GPU quotas in the output
   ```

2. **API Not Enabled**
   ```bash
   gcloud services enable compute.googleapis.com
   ```

3. **Instance Setup Failed**
   ```bash
   # SSH into instance and check logs
   gcloud compute ssh INSTANCE_NAME --zone=ZONE
   sudo tail -f /var/log/algalon-setup.log
   ```

4. **Workers Not Showing in Grafana**
   - Check firewall rules allow port 9090
   - Verify worker targets in monitoring host
   - Check VMAgent configuration

### Debug Commands

```bash
# Check instance status
gcloud compute instances list --filter="labels.component:algalon-*"

# View setup logs
gcloud compute ssh INSTANCE_NAME --zone=ZONE --command="sudo tail -f /var/log/algalon-setup.log"

# Test connectivity
gcloud compute ssh MONITORING_HOST --zone=ZONE --command="curl -f WORKER_IP:9090/metrics"
```

## Next Steps

- Check out [production example](../production/) for a more robust setup
- Review [multi-zone example](../multi-zone/) for high availability
- Read the [main documentation](../../../CLOUD_DEPLOYMENT.md) for advanced configurations

## Support

- [GitHub Issues](https://github.com/inureyes/Algalon/issues)
- [Documentation](../../../README.md)
- [Cloud Deployment Guide](../../../CLOUD_DEPLOYMENT.md)