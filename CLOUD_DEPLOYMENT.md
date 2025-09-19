# Algalon Cloud Deployment Guide

This guide covers deploying Algalon on Google Cloud Platform using Container-Optimized OS and Cloud Init.

## Quick Deploy with Cloud Init

### 1. Deploy Monitoring Host

```bash
# Create monitoring host instance
gcloud compute instances create algalon-monitoring-host \
  --image-family cos-stable \
  --image-project cos-cloud \
  --machine-type n1-standard-2 \
  --boot-disk-size 50GB \
  --metadata-from-file user-data=cloud-init-gce.yml \
  --metadata="ALGALON_MODE=host,ALGALON_TARGETS=worker1:9090,worker2:9090,10.128.0.100:9090,ALGALON_CLUSTER=production" \
  --tags algalon-monitoring \
  --zone us-central1-a
```

### 2. Deploy Worker Nodes

```bash
# Create GPU worker instances
for i in {1..3}; do
  gcloud compute instances create algalon-worker-$i \
    --image-family cos-stable \
    --image-project cos-cloud \
    --machine-type n1-standard-1 \
    --accelerator type=nvidia-tesla-t4,count=1 \
    --maintenance-policy TERMINATE \
    --boot-disk-size 30GB \
    --metadata-from-file user-data=cloud-init-gce.yml \
    --metadata="ALGALON_MODE=worker,ALL_SMI_PORT=9090,ALL_SMI_INTERVAL=5" \
    --tags algalon-worker \
    --zone us-central1-a
done
```

### 3. Create Firewall Rules

```bash
# Allow Grafana access
gcloud compute firewall-rules create algalon-grafana \
  --allow tcp:3000 \
  --source-ranges 0.0.0.0/0 \
  --target-tags algalon-monitoring \
  --description "Allow access to Grafana dashboard"

# Allow internal communication for metrics
gcloud compute firewall-rules create algalon-metrics \
  --allow tcp:9090 \
  --source-tags algalon-monitoring \
  --target-tags algalon-worker \
  --description "Allow metrics collection from workers"
```

## Configuration Options

### Cloud Init Metadata Variables

#### For Monitoring Host (`ALGALON_MODE=host`)

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `ALGALON_TARGETS` | Comma-separated worker targets | `localhost:9090` | `worker1:9090,worker2:9090,10.128.0.100:9090` |
| `ALGALON_CLUSTER` | Cluster name for labeling | `production` | `staging`, `dev` |
| `ALGALON_ENVIRONMENT` | Environment name | `gpu-cluster` | `ml-training`, `inference` |

#### For Worker Nodes (`ALGALON_MODE=worker`)

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `ALL_SMI_VERSION` | all-smi version to install | `v0.9.0` | `v0.8.0`, `main` |
| `ALL_SMI_PORT` | Port for metrics endpoint | `9090` | `8080`, `9091` |
| `ALL_SMI_INTERVAL` | Metrics collection interval (seconds) | `5` | `3`, `10` |

## Advanced Deployment Examples

### Multi-Zone Deployment

```bash
# Deploy monitoring host in zone a
gcloud compute instances create algalon-monitoring \
  --image-family cos-stable \
  --image-project cos-cloud \
  --machine-type n1-standard-2 \
  --metadata-from-file user-data=cloud-init-gce.yml \
  --metadata="ALGALON_MODE=host,ALGALON_TARGETS=10.128.0.10:9090,10.128.0.20:9090,10.128.0.30:9090" \
  --zone us-central1-a

# Deploy workers across multiple zones
gcloud compute instances create algalon-worker-zone-a \
  --image-family cos-stable \
  --image-project cos-cloud \
  --machine-type n1-standard-1 \
  --accelerator type=nvidia-tesla-t4,count=1 \
  --maintenance-policy TERMINATE \
  --metadata-from-file user-data=cloud-init-gce.yml \
  --metadata="ALGALON_MODE=worker,ALL_SMI_INTERVAL=3" \
  --zone us-central1-a

gcloud compute instances create algalon-worker-zone-b \
  --image-family cos-stable \
  --image-project cos-cloud \
  --machine-type n1-standard-1 \
  --accelerator type=nvidia-tesla-t4,count=1 \
  --maintenance-policy TERMINATE \
  --metadata-from-file user-data=cloud-init-gce.yml \
  --metadata="ALGALON_MODE=worker,ALL_SMI_INTERVAL=3" \
  --zone us-central1-b
```

### Using Internal Load Balancer

```bash
# Create internal load balancer for worker nodes
gcloud compute instance-groups unmanaged create algalon-workers \
  --zone us-central1-a

# Add instances to group
gcloud compute instance-groups unmanaged add-instances algalon-workers \
  --instances algalon-worker-1,algalon-worker-2,algalon-worker-3 \
  --zone us-central1-a

# Create health check
gcloud compute health-checks create http algalon-worker-health \
  --port 9090 \
  --request-path /metrics

# Create backend service
gcloud compute backend-services create algalon-worker-backend \
  --load-balancing-scheme internal \
  --health-checks algalon-worker-health \
  --region us-central1

# Add instance group to backend
gcloud compute backend-services add-backend algalon-worker-backend \
  --instance-group algalon-workers \
  --instance-group-zone us-central1-a \
  --region us-central1

# Create forwarding rule
gcloud compute forwarding-rules create algalon-worker-lb \
  --load-balancing-scheme internal \
  --backend-service algalon-worker-backend \
  --region us-central1 \
  --subnet default \
  --ports 9090
```

## Monitoring and Management

### Check Setup Progress

```bash
# SSH into instances to check setup progress
gcloud compute ssh algalon-monitoring-host --zone us-central1-a

# View setup logs
sudo tail -f /var/log/algalon-setup.log

# Check service status
sudo tail -f /var/log/algalon-status.log
```

### Access Grafana Dashboard

```bash
# Get external IP of monitoring host
MONITORING_IP=$(gcloud compute instances describe algalon-monitoring-host \
  --zone us-central1-a \
  --format="get(networkInterfaces[0].accessConfigs[0].natIP)")

echo "Grafana Dashboard: http://$MONITORING_IP:3000"
echo "Username: admin"
echo "Password: admin"
```

### Update Worker Targets Dynamically

```bash
# SSH into monitoring host
gcloud compute ssh algalon-monitoring-host --zone us-central1-a

# Update targets
cd /opt/Algalon/algalon_host
sudo ./generate-targets.sh --targets "worker1:9090,worker2:9090,new-worker:9090"

# Restart VMAgent to pick up new targets
sudo docker compose restart vmagent
```

## Managed Instance Groups

For auto-scaling worker deployments:

```bash
# Create instance template for workers
gcloud compute instance-templates create algalon-worker-template \
  --image-family cos-stable \
  --image-project cos-cloud \
  --machine-type n1-standard-1 \
  --accelerator type=nvidia-tesla-t4,count=1 \
  --maintenance-policy TERMINATE \
  --metadata-from-file user-data=cloud-init-gce.yml \
  --metadata="ALGALON_MODE=worker,ALL_SMI_INTERVAL=5" \
  --tags algalon-worker

# Create managed instance group
gcloud compute instance-groups managed create algalon-worker-group \
  --template algalon-worker-template \
  --size 3 \
  --zone us-central1-a

# Setup autoscaling
gcloud compute instance-groups managed set-autoscaling algalon-worker-group \
  --max-num-replicas 10 \
  --min-num-replicas 2 \
  --target-cpu-utilization 0.8 \
  --zone us-central1-a
```

## Cost Optimization

### Use Preemptible Instances

```bash
# Create cost-effective preemptible workers
gcloud compute instances create algalon-worker-preemptible \
  --image-family cos-stable \
  --image-project cos-cloud \
  --machine-type n1-standard-1 \
  --accelerator type=nvidia-tesla-t4,count=1 \
  --maintenance-policy TERMINATE \
  --preemptible \
  --metadata-from-file user-data=cloud-init-gce.yml \
  --metadata="ALGALON_MODE=worker,ALL_SMI_INTERVAL=10" \
  --zone us-central1-a
```

### Use Spot Instances

```bash
# Create spot instances for workers
gcloud compute instances create algalon-worker-spot \
  --image-family cos-stable \
  --image-project cos-cloud \
  --machine-type n1-standard-1 \
  --accelerator type=nvidia-tesla-t4,count=1 \
  --maintenance-policy TERMINATE \
  --provisioning-model SPOT \
  --metadata-from-file user-data=cloud-init-gce.yml \
  --metadata="ALGALON_MODE=worker" \
  --zone us-central1-a
```

## Troubleshooting

### Common Issues

1. **Setup fails**: Check `/var/log/algalon-setup.log` on the instance
2. **No metrics**: Verify firewall rules allow port 9090
3. **Grafana not accessible**: Check firewall rule for port 3000
4. **GPU not detected**: Ensure GPU-enabled instance with proper drivers

### Debug Commands

```bash
# Check Docker containers
sudo docker ps

# Check container logs
sudo docker logs algalon-all-smi
sudo docker logs grafana

# Test metrics endpoint
curl -f http://localhost:9090/metrics

# Check VMAgent targets
sudo docker exec vmagent cat /etc/vmagent/prometheus.yml
```

## Security Considerations

1. **Restrict Grafana access**: Use VPN or specific IP ranges instead of 0.0.0.0/0
2. **Use internal IPs**: Configure workers to use internal IPs only
3. **Enable audit logging**: Use Google Cloud audit logs for compliance
4. **Use service accounts**: Apply least-privilege service accounts to instances

## Example Production Setup

```bash
#!/bin/bash
# production-deploy.sh - Production deployment script

PROJECT_ID="your-project-id"
ZONE="us-central1-a"
CLUSTER_NAME="ml-training"

# Set project
gcloud config set project $PROJECT_ID

# Create VPC network
gcloud compute networks create algalon-network --subnet-mode regional

# Create subnet
gcloud compute networks subnets create algalon-subnet \
  --network algalon-network \
  --range 10.1.0.0/16 \
  --region us-central1

# Deploy monitoring host
gcloud compute instances create algalon-monitoring \
  --image-family cos-stable \
  --image-project cos-cloud \
  --machine-type n1-standard-4 \
  --subnet algalon-subnet \
  --metadata-from-file user-data=cloud-init-gce.yml \
  --metadata="ALGALON_MODE=host,ALGALON_CLUSTER=$CLUSTER_NAME,ALGALON_TARGETS=10.1.0.10:9090,10.1.0.11:9090,10.1.0.12:9090" \
  --tags algalon-monitoring \
  --zone $ZONE

# Deploy worker nodes
for i in {10..12}; do
  gcloud compute instances create algalon-worker-$i \
    --image-family cos-stable \
    --image-project cos-cloud \
    --machine-type n1-standard-2 \
    --accelerator type=nvidia-tesla-v100,count=1 \
    --maintenance-policy TERMINATE \
    --subnet algalon-subnet \
    --private-network-ip 10.1.0.$i \
    --metadata-from-file user-data=cloud-init-gce.yml \
    --metadata="ALGALON_MODE=worker,ALL_SMI_INTERVAL=3" \
    --tags algalon-worker \
    --zone $ZONE
done

# Create firewall rules
gcloud compute firewall-rules create algalon-internal \
  --network algalon-network \
  --allow tcp:9090,tcp:3000 \
  --source-ranges 10.1.0.0/16

echo "Deployment complete! Check status in Cloud Console."
```

This completes the cloud deployment setup with full automation and configuration options.