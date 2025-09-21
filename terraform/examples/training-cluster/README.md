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