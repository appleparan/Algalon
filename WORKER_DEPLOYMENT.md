# Algalon Worker-Only Deployment Guide

This guide covers deploying Algalon workers independently, typically for on-premise GPU machines that report to a centralized monitoring host in the cloud.

## 📋 Overview

Worker-only deployment is ideal for:
- **On-premise GPU servers** connecting to cloud monitoring
- **Edge computing** scenarios with distributed GPUs
- **Hybrid cloud** setups where workers are in different locations
- **Development environments** where you want local workers

## 🎯 Architecture

```
┌─────────────────┐         ┌─────────────────┐
│   Cloud Host    │         │ On-premise      │
│   (Terraform)   │◄────────┤ Worker          │
│                 │ Metrics │ (Manual Deploy) │
│ ┌─────────────┐ │         │                 │
│ │   Grafana   │ │         │ ┌─────────────┐ │
│ │   :3000     │ │         │ │   all-smi   │ │
│ └─────────────┘ │         │ │   :9090     │ │
│ ┌─────────────┐ │         │ └─────────────┘ │
│ │ VictoriaM.  │ │         │ ┌─────────────┐ │
│ │   :8428     │ │         │ │    GPU      │ │
│ └─────────────┘ │         │ │  Hardware   │ │
│ ┌─────────────┐ │         │ └─────────────┘ │
│ │   VMAgent   │ │         └─────────────────┘
│ └─────────────┘ │
└─────────────────┘
```

## 🚀 Quick Start

### Prerequisites

1. **Docker** and **Docker Compose** installed
2. **GPU** (NVIDIA) with drivers installed
3. **Network access** to monitoring host
4. **Port 9090** available for metrics

### 1. Install Worker

```bash
# Clone repository
git clone https://github.com/appleparan/Algalon.git
cd Algalon/algalon_worker

# Quick setup with defaults
./setup.sh

# Or customize configuration
./setup.sh --version v0.9.0 --port 9090 --interval 5
```

### 2. Verify Worker

```bash
# Check containers
docker ps

# Test metrics endpoint
curl -f http://localhost:9090/metrics

# View logs
docker logs algalon-all-smi
```

### 3. Register with Monitoring Host

If you have a monitoring host running (see [Host-Only Deployment](terraform/examples/host-only/)):

```bash
# Get your worker IP
curl -s ifconfig.me

# Contact your monitoring host administrator to add:
# YOUR_WORKER_IP:9090 to the targets configuration
```

## ⚙️ Configuration Options

### Environment Variables

Edit `.env` file or set environment variables:

```bash
# all-smi configuration
ALL_SMI_VERSION=v0.9.0      # Version of all-smi to use
ALL_SMI_PORT=9090           # Port for metrics endpoint
ALL_SMI_INTERVAL=5          # Metrics collection interval (seconds)

# Network configuration
HOST_IP=0.0.0.0            # Bind address (0.0.0.0 for external access)
```

### Command Line Options

```bash
# Full configuration
./setup.sh \
  --version v0.9.0 \
  --port 9090 \
  --interval 5 \
  --host-ip 0.0.0.0
```

### Manual Configuration

Create `.env` file:

```bash
cat > .env << EOF
ALL_SMI_VERSION=v0.9.0
ALL_SMI_PORT=9090
ALL_SMI_INTERVAL=5
HOST_IP=0.0.0.0
EOF

# Deploy with custom config
./setup.sh
```

## 🔧 Advanced Configuration

### Custom Docker Compose

You can modify `docker-compose.yml` for advanced scenarios:

```yaml
version: '3.8'
services:
  algalon-all-smi:
    image: nvcr.io/nvidia/all-smi:${ALL_SMI_VERSION:-v0.9.0}
    container_name: algalon-all-smi
    ports:
      - "${HOST_IP:-0.0.0.0}:${ALL_SMI_PORT:-9090}:9090"
    environment:
      - NVIDIA_VISIBLE_DEVICES=all
      - INTERVAL=${ALL_SMI_INTERVAL:-5}
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    restart: unless-stopped
    networks:
      - algalon
    # Add custom labels
    labels:
      - "algalon.component=worker"
      - "algalon.hostname=${HOSTNAME}"

networks:
  algalon:
    driver: bridge
```

### Firewall Configuration

Ensure port 9090 is accessible from monitoring host:

```bash
# Ubuntu/Debian
sudo ufw allow 9090/tcp

# CentOS/RHEL
sudo firewall-cmd --permanent --add-port=9090/tcp
sudo firewall-cmd --reload

# Test connectivity
telnet MONITORING_HOST_IP 9090
```

### SSL/TLS Configuration

For secure environments, you can configure HTTPS:

```bash
# Generate certificates (example)
openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -nodes

# Update docker-compose.yml to mount certificates
# and configure all-smi for HTTPS
```

## 🔗 Integration with Monitoring Host

### Automatic Registration

If your monitoring host supports dynamic registration:

```bash
# Register worker via API (if implemented)
curl -X POST "http://MONITORING_HOST:8428/api/v1/targets" \
  -H "Content-Type: application/json" \
  -d '{"targets": ["'$(hostname -I | awk '{print $1}')':9090"]}'
```

### Manual Registration

Contact your monitoring host administrator to add your worker:

```bash
# Provide this information
echo "Worker IP: $(curl -s ifconfig.me || hostname -I | awk '{print $1}')"
echo "Worker Port: ${ALL_SMI_PORT:-9090}"
echo "Metrics URL: http://$(curl -s ifconfig.me || hostname -I | awk '{print $1}'):${ALL_SMI_PORT:-9090}/metrics"
```

### Configuration File Update

If you have access to the monitoring host, update targets:

```bash
# On monitoring host
cd /opt/Algalon/algalon_host

# Add worker to targets
echo "  - targets: ['WORKER_IP:9090']" >> node/targets/all-smi-targets.yml

# Restart VMAgent
docker-compose restart vmagent
```

## 🛠️ Troubleshooting

### Common Issues

1. **Port Already in Use**
   ```bash
   # Check what's using port 9090
   sudo netstat -tulpn | grep 9090

   # Use different port
   ./setup.sh --port 9091
   ```

2. **GPU Not Detected**
   ```bash
   # Check NVIDIA drivers
   nvidia-smi

   # Check Docker GPU support
   docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi
   ```

3. **Network Connectivity**
   ```bash
   # Test from monitoring host
   curl -f http://WORKER_IP:9090/metrics

   # Check firewall
   sudo ufw status
   ```

4. **Container Not Starting**
   ```bash
   # Check logs
   docker logs algalon-all-smi

   # Check docker-compose
   docker-compose logs
   ```

### Debug Commands

```bash
# Check service status
docker ps | grep algalon

# View real-time logs
docker logs -f algalon-all-smi

# Test metrics endpoint
curl -v http://localhost:9090/metrics

# Check GPU metrics
curl -s http://localhost:9090/metrics | grep gpu

# Restart service
docker-compose restart
```

### Performance Tuning

```bash
# Adjust collection interval for performance
export ALL_SMI_INTERVAL=10  # Slower collection (less CPU)
export ALL_SMI_INTERVAL=1   # Faster collection (more CPU)

# Limit container resources
docker update --memory="512m" --cpus="0.5" algalon-all-smi
```

## 📊 Monitoring Multiple Workers

### Deployment at Scale

For multiple workers, use configuration management:

#### Ansible Example

```yaml
# playbook.yml
- hosts: gpu_workers
  tasks:
    - name: Deploy Algalon Worker
      shell: |
        cd /tmp
        git clone https://github.com/appleparan/Algalon.git
        cd Algalon/algalon_worker
        ./setup.sh --port {{ all_smi_port | default(9090) }}
```

#### Docker Swarm Example

```yaml
# docker-stack.yml
version: '3.8'
services:
  algalon-worker:
    image: nvcr.io/nvidia/all-smi:v0.9.0
    ports:
      - "9090:9090"
    environment:
      - INTERVAL=5
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.labels.gpu == true
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
```

### Worker Discovery

For automatic worker discovery, implement service registry:

```bash
# Register with Consul (example)
curl -X PUT "http://consul:8500/v1/kv/algalon/workers/$(hostname)" \
  -d "$(hostname -I | awk '{print $1}'):9090"
```

## 🔄 Maintenance

### Updates

```bash
# Update to latest version
cd Algalon/algalon_worker
git pull
./setup.sh --version v0.10.0  # Use new version
```

### Backup Configuration

```bash
# Backup current config
cp .env .env.backup
cp docker-compose.yml docker-compose.yml.backup
```

### Health Checks

```bash
# Create health check script
cat > health-check.sh << 'EOF'
#!/bin/bash
HEALTH_URL="http://localhost:${ALL_SMI_PORT:-9090}/metrics"
if curl -f "$HEALTH_URL" > /dev/null 2>&1; then
    echo "Worker healthy"
    exit 0
else
    echo "Worker unhealthy"
    exit 1
fi
EOF

chmod +x health-check.sh

# Add to cron for monitoring
echo "*/5 * * * * /path/to/health-check.sh" | crontab -
```

## 🔗 Related Documentation

- [Host-Only Deployment](terraform/examples/host-only/) - Deploy monitoring host
- [Hybrid Deployment Guide](HYBRID_DEPLOYMENT.md) - Cloud + on-premise setup
- [Main README](README.md) - Complete documentation
- [Cloud Deployment](CLOUD_DEPLOYMENT.md) - Full cloud setup

## 🆘 Support

- [GitHub Issues](https://github.com/appleparan/Algalon/issues)
- [Discussions](https://github.com/appleparan/Algalon/discussions)
- [Worker Configuration Examples](examples/worker-configs/)