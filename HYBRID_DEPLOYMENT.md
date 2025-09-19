# Algalon Hybrid Deployment Guide

This guide covers hybrid deployment scenarios where the Algalon monitoring host runs in the cloud (using Terraform) while workers run on-premise manually. This is ideal for organizations with existing on-premise GPU infrastructure that want centralized cloud monitoring.

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                     Cloud (GCP)                         │
│  ┌─────────────────────────────────────────────────────┐│
│  │              Algalon Host                           ││
│  │           (Terraform Managed)                       ││
│  │                                                     ││
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐   ││
│  │  │   Grafana   │ │ VictoriaM.  │ │   VMAgent   │   ││
│  │  │   :3000     │ │   :8428     │ │             │   ││
│  │  └─────────────┘ └─────────────┘ └─────────────┘   ││
│  └─────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────┘
                              ▲
                              │ HTTPS/Metrics
                              │ (Firewall: Port 9090)
┌─────────────────────────────────────────────────────────┐
│                    On-Premise                           │
│  ┌─────────────────┐  ┌─────────────────┐              │
│  │   Worker 1      │  │   Worker 2      │  ...         │
│  │ (Manual Deploy) │  │ (Manual Deploy) │              │
│  │                 │  │                 │              │
│  │ ┌─────────────┐ │  │ ┌─────────────┐ │              │
│  │ │   all-smi   │ │  │ │   all-smi   │ │              │
│  │ │   :9090     │ │  │ │   :9090     │ │              │
│  │ └─────────────┘ │  │ └─────────────┘ │              │
│  │ ┌─────────────┐ │  │ ┌─────────────┐ │              │
│  │ │    GPU      │ │  │ │    GPU      │ │              │
│  │ │  Hardware   │ │  │ │  Hardware   │ │              │
│  │ └─────────────┘ │  │ └─────────────┘ │              │
│  └─────────────────┘  └─────────────────┘              │
└─────────────────────────────────────────────────────────┘
```

## 🎯 Use Cases

- **Enterprise environments** with existing on-premise GPU clusters
- **Security-sensitive** workloads that must remain on-premise
- **Hybrid cloud** strategies with centralized monitoring
- **Edge computing** with distributed GPU resources
- **Cost optimization** by keeping compute on-premise, monitoring in cloud
- **Compliance requirements** for data locality

## 🚀 Deployment Steps

### Phase 1: Deploy Cloud Monitoring Host

#### 1. Deploy Host with Terraform

```bash
# Clone repository
git clone https://github.com/appleparan/Algalon.git
cd Algalon/terraform/examples/host-only

# Configure for your environment
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
# Required
project_id = "your-gcp-project-id"

# Network and security
grafana_allowed_ips = ["YOUR_OFFICE_IP/32"]  # Restrict access
ssh_allowed_ips = ["YOUR_OFFICE_IP/32"]

# Host configuration
deployment_name = "algalon-hybrid"
create_static_ip = true  # Important for stable worker connections

# Initially empty - workers will be added later
worker_targets = ""
```

Deploy:

```bash
terraform init
terraform plan
terraform apply
```

#### 2. Get Host Information

```bash
# Get monitoring host IP (workers will connect to this)
MONITORING_HOST_IP=$(terraform output -raw monitoring_host_external_ip)

# Get Grafana URL
GRAFANA_URL=$(terraform output -raw grafana_url)

echo "Monitoring Host IP: $MONITORING_HOST_IP"
echo "Grafana URL: $GRAFANA_URL"
```

### Phase 2: Configure Network Connectivity

#### 1. Firewall Configuration

**Cloud Side (GCP):**

```bash
# Allow worker metrics from your on-premise network
gcloud compute firewall-rules create algalon-workers-access \
  --direction=INGRESS \
  --priority=1000 \
  --network=algalon-host-network \
  --action=ALLOW \
  --rules=tcp:9090 \
  --source-ranges=YOUR_ONPREMISE_CIDR \
  --target-tags=algalon-host

# Verify firewall rule
gcloud compute firewall-rules describe algalon-workers-access
```

**On-premise Side:**

```bash
# Allow outbound HTTPS to monitoring host
# (Configure your enterprise firewall to allow)
# Destination: $MONITORING_HOST_IP:443
# Protocol: HTTPS/TCP
```

#### 2. Network Connectivity Test

From on-premise network:

```bash
# Test connectivity to monitoring host
telnet $MONITORING_HOST_IP 3000  # Grafana
curl -I https://$MONITORING_HOST_IP:3000

# Test if monitoring host can reach your network
# (May require VPN or firewall rules)
```

### Phase 3: Deploy On-Premise Workers

#### 1. Prepare Worker Machines

On each GPU machine:

```bash
# Install Docker and Docker Compose
sudo apt-get update
sudo apt-get install docker.io docker-compose

# Add user to docker group
sudo usermod -aG docker $USER
newgrp docker

# Verify GPU access
nvidia-smi
docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi
```

#### 2. Deploy Workers

On each GPU machine:

```bash
# Clone and deploy worker
git clone https://github.com/appleparan/Algalon.git
cd Algalon/algalon_worker

# Configure worker
cp .env.example .env
vim .env  # Edit configuration

# Deploy worker
./setup.sh --version v0.9.0 --port 9090 --interval 5

# Verify worker
curl -f http://localhost:9090/metrics
```

#### 3. Register Workers with Monitoring Host

**Option A: Manual Registration (Recommended for initial setup)**

```bash
# SSH to monitoring host
gcloud compute ssh algalon-hybrid-monitoring --zone=us-central1-a

# Register each worker
cd /opt/Algalon/algalon_host/scripts
./register-worker.sh WORKER1_IP:9090 WORKER2_IP:9090

# Verify registration
docker-compose logs vmagent
```

**Option B: Terraform Update (For permanent registration)**

Update `terraform.tfvars`:

```hcl
worker_targets = "10.0.1.100:9090,10.0.1.101:9090,10.0.1.102:9090"
```

Apply changes:

```bash
terraform apply
```

**Option C: Automated Discovery (For dynamic environments)**

```bash
# SSH to monitoring host
gcloud compute ssh algalon-hybrid-monitoring --zone=us-central1-a

# Run worker discovery
cd /opt/Algalon/algalon_host/scripts
./worker-discovery.sh --network YOUR_ONPREMISE_CIDR

# For continuous discovery
./worker-discovery.sh --network 10.0.0.0/8 --daemon
```

## 🔧 Advanced Configuration

### VPN Setup for Secure Connectivity

#### 1. Cloud VPN Gateway

```bash
# Create VPN gateway
gcloud compute vpn-gateways create algalon-vpn-gateway \
  --network=algalon-host-network \
  --region=us-central1

# Create VPN tunnel
gcloud compute vpn-tunnels create algalon-tunnel \
  --peer-address=YOUR_ONPREMISE_VPN_IP \
  --shared-secret=YOUR_SHARED_SECRET \
  --ike-version=2 \
  --local-traffic-selector=10.0.0.0/24 \
  --remote-traffic-selector=192.168.0.0/16
```

#### 2. On-premise VPN Configuration

Configure your on-premise VPN to connect to GCP:

```bash
# Example for strongSwan (Ubuntu)
sudo apt-get install strongswan

# Configure /etc/ipsec.conf
conn algalon-gcp
    type=tunnel
    authby=secret
    left=YOUR_ONPREMISE_IP
    leftsubnet=192.168.0.0/16
    right=GCP_VPN_GATEWAY_IP
    rightsubnet=10.0.0.0/24
    ike=aes256-sha1-modp1024!
    esp=aes256-sha1!
    keyingtries=0
    ikelifetime=1h
    lifetime=8h
    dpddelay=30
    dpdtimeout=120
    dpdaction=restart
    auto=start
```

### Service Discovery Integration

#### 1. Consul Integration

```bash
# On monitoring host, register service
curl -X PUT "http://consul:8500/v1/agent/service/register" \
  -d '{
    "ID": "algalon-monitoring",
    "Name": "algalon-monitoring",
    "Tags": ["monitoring", "grafana"],
    "Address": "'$MONITORING_HOST_IP'",
    "Port": 3000
  }'

# On workers, register themselves
curl -X PUT "http://consul:8500/v1/agent/service/register" \
  -d '{
    "ID": "algalon-worker-'$(hostname)'",
    "Name": "algalon-worker",
    "Tags": ["worker", "gpu"],
    "Address": "'$(hostname -I | awk '{print $1}')'",
    "Port": 9090,
    "Check": {
      "HTTP": "http://localhost:9090/metrics",
      "Interval": "10s"
    }
  }'
```

#### 2. Kubernetes Integration

For workers running in on-premise Kubernetes:

```yaml
# algalon-worker-daemonset.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: algalon-worker
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: algalon-worker
  template:
    metadata:
      labels:
        app: algalon-worker
    spec:
      hostNetwork: true
      nodeSelector:
        nvidia.com/gpu: "true"
      containers:
      - name: all-smi
        image: nvcr.io/nvidia/all-smi:v0.9.0
        ports:
        - containerPort: 9090
          hostPort: 9090
        env:
        - name: INTERVAL
          value: "5"
        resources:
          limits:
            nvidia.com/gpu: 1
```

### Load Balancing for Multiple Monitoring Hosts

For high availability:

```bash
# Deploy multiple monitoring hosts
terraform apply -var="host_count=3"

# Configure load balancer
gcloud compute instance-groups managed create algalon-hosts-group \
  --base-instance-name=algalon-host \
  --size=3 \
  --zone=us-central1-a

gcloud compute backend-services create algalon-backend \
  --protocol=HTTP \
  --port-name=grafana \
  --health-checks=algalon-health-check
```

## 🔒 Security Best Practices

### 1. Network Security

```bash
# Restrict firewall rules to specific IPs
gcloud compute firewall-rules update algalon-grafana-access \
  --source-ranges=YOUR_OFFICE_IP/32

# Use private IP ranges
# Cloud: 10.0.0.0/24
# On-premise: 192.168.0.0/16

# Enable VPC Flow Logs
gcloud compute networks subnets update algalon-subnet \
  --region=us-central1 \
  --enable-flow-logs
```

### 2. Authentication and Authorization

```bash
# Configure Grafana LDAP authentication
# In monitoring host cloud-init or setup script
cat > /opt/Algalon/algalon_host/grafana/ldap.toml << EOF
[[servers]]
host = "your-ldap-server.com"
port = 389
use_ssl = false
start_tls = false
ssl_skip_verify = false
bind_dn = "cn=admin,dc=grafana,dc=org"
bind_password = 'grafana'
search_filter = "(cn=%s)"
search_base_dns = ["dc=grafana,dc=org"]
EOF
```

### 3. Certificate Management

```bash
# Use Let's Encrypt for HTTPS
# Add to monitoring host setup
certbot --nginx -d monitoring.yourdomain.com

# Configure SSL for worker metrics (optional)
openssl req -x509 -newkey rsa:4096 -keyout worker.key -out worker.crt -days 365
```

## 📊 Monitoring and Troubleshooting

### 1. Health Checks

Create monitoring script:

```bash
#!/bin/bash
# hybrid-health-check.sh

MONITORING_HOST="$1"
WORKERS_FILE="/etc/algalon/workers.txt"

echo "=== Algalon Hybrid Deployment Health Check ==="

# Check monitoring host
echo "Checking monitoring host: $MONITORING_HOST"
if curl -f -s "http://$MONITORING_HOST:3000/api/health" > /dev/null; then
    echo "✓ Grafana is healthy"
else
    echo "✗ Grafana is not responding"
fi

# Check workers
echo "Checking workers..."
while read -r worker; do
    if curl -f -s "http://$worker/metrics" > /dev/null; then
        echo "✓ Worker $worker is healthy"
    else
        echo "✗ Worker $worker is not responding"
    fi
done < "$WORKERS_FILE"
```

### 2. Log Aggregation

Configure centralized logging:

```bash
# On monitoring host
docker run -d --name logstash \
  -p 5044:5044 \
  -v /var/log/algalon:/var/log/input \
  docker.elastic.co/logstash/logstash:7.10.0

# On workers
filebeat.inputs:
- type: log
  paths:
    - /var/log/algalon-worker.log
output.logstash:
  hosts: ["$MONITORING_HOST_IP:5044"]
```

### 3. Network Troubleshooting

```bash
# Test connectivity from worker to monitoring host
traceroute $MONITORING_HOST_IP
mtr $MONITORING_HOST_IP

# Test metrics collection
curl -v "http://$MONITORING_HOST_IP:8428/api/v1/query?query=up"

# Check VMAgent targets
curl -s "http://$MONITORING_HOST_IP:8428/api/v1/targets" | jq .
```

## 💰 Cost Optimization

### 1. Monitoring Host Sizing

```hcl
# Development/Small deployments
host_machine_type = "n1-standard-1"  # $24/month

# Production/Medium deployments
host_machine_type = "n1-standard-2"  # $49/month

# Large deployments
host_machine_type = "n1-standard-4"  # $97/month
```

### 2. Network Costs

```bash
# Use regional resources to minimize egress
region = "us-central1"  # Same region as workers if possible

# Monitor egress costs
gcloud logging metrics create algalon_egress_bytes \
  --description="Algalon egress traffic" \
  --log-filter='resource.type="gce_instance" AND resource.labels.instance_name=~"algalon.*"'
```

### 3. Storage Optimization

```hcl
# Use SSD only for high-IOPS requirements
boot_disk_type = "pd-standard"  # Cheaper for monitoring host

# Implement data retention policies
# Configure in VictoriaMetrics
retentionPeriod = "30d"  # Adjust based on needs
```

## 📚 Examples and Templates

### Complete Terraform Configuration

```hcl
# terraform/examples/hybrid-production/main.tf
module "monitoring_host" {
  source = "../../modules/algalon-host"

  instance_name   = "algalon-hybrid-monitoring"
  machine_type    = "n1-standard-2"
  create_static_ip = true

  # Security for hybrid deployment
  grafana_allowed_ips = ["YOUR_OFFICE_CIDR/24"]
  ssh_allowed_ips     = ["YOUR_VPN_CIDR/24"]

  # Initially empty - workers registered manually
  worker_targets = ""

  labels = {
    deployment_type = "hybrid"
    environment     = "production"
    cost_center     = "infrastructure"
  }
}
```

### Worker Deployment Automation

```bash
#!/bin/bash
# deploy-workers-parallel.sh

WORKERS=(
  "gpu-node-01.internal:9090"
  "gpu-node-02.internal:9090"
  "gpu-node-03.internal:9090"
)

MONITORING_HOST="monitoring.algalon.cloud"

# Deploy workers in parallel
for worker in "${WORKERS[@]}"; do
  {
    host=$(echo $worker | cut -d: -f1)
    echo "Deploying worker on $host..."

    ssh "$host" '
      cd /tmp
      git clone https://github.com/appleparan/Algalon.git
      cd Algalon/algalon_worker
      ./setup.sh --version v0.9.0 --port 9090
    '

    echo "Worker $host deployed successfully"
  } &
done

wait

# Register all workers
ssh "$MONITORING_HOST" "
  cd /opt/Algalon/algalon_host/scripts
  ./register-worker.sh ${WORKERS[*]}
"

echo "Hybrid deployment completed!"
```

## 🆘 Support and Next Steps

### Documentation Links

- [Host-Only Deployment](terraform/examples/host-only/) - Cloud monitoring host setup
- [Worker-Only Deployment](WORKER_DEPLOYMENT.md) - On-premise worker setup
- [Terraform Examples](terraform/examples/) - Infrastructure templates
- [Security Guide](SECURITY.md) - Best practices for production

### Getting Help

- [GitHub Issues](https://github.com/appleparan/Algalon/issues) - Bug reports and feature requests
- [Discussions](https://github.com/appleparan/Algalon/discussions) - Community support
- [Wiki](https://github.com/appleparan/Algalon/wiki) - Additional examples and guides

### Migration Path

If you currently have a basic deployment and want to move to hybrid:

1. **Backup current configuration**
2. **Deploy new host-only monitoring** in cloud
3. **Migrate data** from old monitoring to new
4. **Update workers** to point to new monitoring host
5. **Decommission old monitoring** infrastructure

This hybrid approach gives you the best of both worlds: centralized cloud monitoring with on-premise compute resources.