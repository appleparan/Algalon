# Algalon Host-Only Deployment

This example demonstrates deploying only the Algalon monitoring host using Terraform, suitable for scenarios where:

- Workers will be deployed manually on on-premise machines
- Workers will be added dynamically over time
- You want to separate Host deployment from Worker deployment
- You need a centralized monitoring host in the cloud with distributed workers

## Architecture

```
┌─────────────────┐
│   Cloud Host    │
│   (Terraform)   │◄───┐
│                 │    │
│ ┌─────────────┐ │    │ Manual Registration
│ │   Grafana   │ │    │ or API calls
│ │   :3000     │ │    │
│ └─────────────┘ │    │
│ ┌─────────────┐ │    │
│ │ VictoriaM.  │ │    │
│ │   :8428     │ │    │
│ └─────────────┘ │    │
│ ┌─────────────┐ │    │
│ │   VMAgent   │ │    │
│ └─────────────┘ │    │
└─────────────────┘    │
                       │
┌─────────────────┐    │
│ On-premise      │    │
│ Worker          │────┘
│ (Manual Deploy) │
│                 │
│ ┌─────────────┐ │
│ │   all-smi   │ │
│ │   :9090     │ │
│ └─────────────┘ │
│ ┌─────────────┐ │
│ │    GPU      │ │
│ │  Hardware   │ │
│ └─────────────┘ │
└─────────────────┘
```

## Prerequisites

1. **Google Cloud SDK** installed and configured
2. **Terraform** >= 1.0 installed
3. **GCP Project** with required APIs enabled:
   ```bash
   gcloud services enable compute.googleapis.com
   ```

## Quick Start

### 1. Deploy Host

```bash
# Clone and navigate
git clone https://github.com/appleparan/Algalon.git
cd Algalon/terraform/examples/host-only

# Configure
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project ID and IP restrictions

# Deploy
terraform init
terraform plan
terraform apply
```

### 2. Get Host Information

```bash
# Get Grafana URL
terraform output grafana_url

# Get Host IP for worker registration
terraform output monitoring_host_external_ip

# Get worker registration instructions
terraform output worker_registration_info
```

### 3. Deploy Workers Manually

After the host is deployed, you can add workers using one of these methods:

#### Option A: On-premise Docker Deployment

On your on-premise machines with GPUs:

```bash
# Clone repository
git clone https://github.com/appleparan/Algalon.git
cd Algalon/algalon_worker

# Configure worker
cp .env.example .env
# Edit .env with your settings

# Deploy worker
./setup.sh --version v0.9.0 --port 9090 --interval 5
```

#### Option B: Manual Registration

If you already have workers running, register them with the monitoring host:

```bash
# SSH to monitoring host
gcloud compute ssh algalon-host-monitoring --zone=us-central1-a

# Register worker manually
cd /opt/Algalon/algalon_host
./scripts/register-worker.sh WORKER_IP:9090
```

## Configuration

### Basic Variables

Edit `terraform.tfvars`:

```hcl
project_id = "your-gcp-project-id"
deployment_name = "algalon-host"

# Security (IMPORTANT: Restrict for production!)
grafana_allowed_ips = ["YOUR_IP/32"]
ssh_allowed_ips = ["YOUR_IP/32"]

# Host configuration
host_machine_type = "n1-standard-2"
create_static_ip = true
```

### Security Configuration

For production, always restrict access:

```hcl
grafana_allowed_ips = ["YOUR_OFFICE_CIDR/24"]
ssh_allowed_ips = ["VPN_CIDR/24"]
enable_ssh_access = true
```

### Adding Workers Later

You can add worker targets by updating the deployment:

```hcl
# Update terraform.tfvars
worker_targets = "10.0.1.100:9090,10.0.1.101:9090"

# Apply changes
terraform apply
```

## Outputs

| Output | Description |
|--------|-------------|
| `grafana_url` | URL to access Grafana dashboard |
| `victoria_metrics_url` | URL to VictoriaMetrics |
| `monitoring_host_external_ip` | Host IP for worker registration |
| `worker_registration_info` | Instructions for manual worker registration |

## Worker Deployment

### On-premise Worker Setup

On each machine you want to monitor:

1. **Install Docker and Docker Compose**
2. **Deploy Algalon Worker**:
   ```bash
   git clone https://github.com/appleparan/Algalon.git
   cd Algalon/algalon_worker
   ./setup.sh --version v0.9.0 --port 9090 --interval 5
   ```
3. **Register with monitoring host** (if not using auto-discovery)

### Worker Registration

#### Automatic Registration (Recommended)

Update your Terraform configuration:

```hcl
# Add workers to terraform.tfvars
worker_targets = "worker1.example.com:9090,worker2.example.com:9090"

# Apply update
terraform apply
```

#### Manual Registration

```bash
# SSH to monitoring host
terraform output ssh_command | bash

# Register worker
cd /opt/Algalon/algalon_host
echo "  - targets: ['WORKER_IP:9090']" >> node/targets/all-smi-targets.yml

# Restart VMAgent
docker-compose restart vmagent
```

## Troubleshooting

### Common Issues

1. **Cannot Access Grafana**
   ```bash
   # Check firewall rules
   gcloud compute firewall-rules list --filter="name:algalon"

   # Verify your IP is in allowed list
   terraform output deployment_summary
   ```

2. **Workers Not Appearing**
   ```bash
   # Check VMAgent targets
   terraform output ssh_command | bash
   cat /opt/Algalon/algalon_host/node/targets/all-smi-targets.yml
   ```

3. **Static IP Issues**
   ```bash
   # Check static IP creation
   gcloud compute addresses list --filter="name:algalon"
   ```

### Debug Commands

```bash
# Check host status
gcloud compute instances list --filter="labels.component:algalon-host"

# View setup logs
gcloud compute ssh INSTANCE_NAME --command="sudo tail -f /var/log/algalon-setup.log"

# Test worker connectivity
curl -f http://WORKER_IP:9090/metrics
```

## Cost Optimization

### Development Setup
```hcl
host_machine_type = "n1-standard-1"
create_static_ip = false
enable_host_external_ip = true
```

### Production Setup
```hcl
host_machine_type = "n1-standard-2"
create_static_ip = true
grafana_allowed_ips = ["YOUR_OFFICE_CIDR/24"]
```

## Next Steps

- Deploy workers using the [Worker Deployment Guide](../../../WORKER_DEPLOYMENT.md)
- Check out [production example](../production/) for advanced host configurations
- Review [hybrid deployment guide](../../../HYBRID_DEPLOYMENT.md) for cloud + on-premise setups

## Support

- [GitHub Issues](https://github.com/appleparan/Algalon/issues)
- [Main Documentation](../../../README.md)
- [Worker Deployment Guide](../../../WORKER_DEPLOYMENT.md)