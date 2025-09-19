# Algalon Worker Configuration Examples

This directory contains example configuration files for different Algalon worker deployment scenarios.

## 📁 Configuration Files

### `basic-worker.env`
Basic configuration for development and testing environments.
- Standard 5-second collection interval
- External access enabled
- Minimal configuration

### `high-frequency-worker.env`
High-frequency monitoring for real-time applications.
- 1-second collection interval
- Suitable for training workloads requiring real-time metrics
- Higher CPU overhead

### `production-worker.env`
Production-ready configuration with security considerations.
- Balanced performance and monitoring overhead
- Proper labeling for production environments
- Security-conscious defaults

## 🚀 Usage

1. **Copy the appropriate configuration:**
   ```bash
   cp examples/worker-configs/basic-worker.env algalon_worker/.env
   ```

2. **Customize for your environment:**
   ```bash
   vim algalon_worker/.env
   ```

3. **Deploy the worker:**
   ```bash
   cd algalon_worker
   ./setup.sh
   ```

## ⚙️ Configuration Options

### Core Settings

| Variable | Description | Default | Examples |
|----------|-------------|---------|----------|
| `ALL_SMI_VERSION` | all-smi container version | `v0.9.0` | `v0.8.0`, `latest` |
| `ALL_SMI_PORT` | Metrics endpoint port | `9090` | `9091`, `8080` |
| `ALL_SMI_INTERVAL` | Collection interval (seconds) | `5` | `1`, `10`, `30` |
| `HOST_IP` | Bind address | `0.0.0.0` | `127.0.0.1`, `192.168.1.100` |

### Advanced Settings

| Variable | Description | Default | Examples |
|----------|-------------|---------|----------|
| `HOSTNAME` | Custom hostname identifier | System hostname | `gpu-worker-01`, `ml-node-east` |
| `WORKER_LABELS` | Custom metric labels | None | `team=ml-ops,env=prod` |
| `MEMORY_LIMIT` | Container memory limit | None | `512m`, `1g` |
| `CPU_LIMIT` | Container CPU limit | None | `0.5`, `1.0` |

## 🎯 Deployment Scenarios

### Development Environment
```bash
# Use basic configuration
cp examples/worker-configs/basic-worker.env algalon_worker/.env

# Modify for local development
sed -i 's/ALL_SMI_INTERVAL=5/ALL_SMI_INTERVAL=10/' algalon_worker/.env
sed -i 's/HOST_IP=0.0.0.0/HOST_IP=127.0.0.1/' algalon_worker/.env
```

### Training Workloads
```bash
# Use high-frequency configuration for real-time monitoring
cp examples/worker-configs/high-frequency-worker.env algalon_worker/.env

# Add training-specific labels
echo "WORKER_LABELS=workload=training,model=transformer,dataset=imagenet" >> algalon_worker/.env
```

### Production Deployment
```bash
# Use production configuration
cp examples/worker-configs/production-worker.env algalon_worker/.env

# Customize for your production environment
vim algalon_worker/.env  # Update HOSTNAME and WORKER_LABELS
```

### Edge Computing
```bash
# Copy basic config and modify for edge
cp examples/worker-configs/basic-worker.env algalon_worker/.env

# Reduce frequency for limited bandwidth
sed -i 's/ALL_SMI_INTERVAL=5/ALL_SMI_INTERVAL=30/' algalon_worker/.env

# Add edge-specific labels
echo "WORKER_LABELS=deployment=edge,location=datacenter-west" >> algalon_worker/.env
```

## 🔧 Customization Guidelines

### Collection Interval Selection

| Interval | Use Case | CPU Impact | Network Impact |
|----------|----------|------------|----------------|
| 1s | Real-time training monitoring | High | High |
| 5s | Standard production monitoring | Medium | Medium |
| 10s | Development/testing | Low | Low |
| 30s+ | Edge/bandwidth-limited | Very Low | Very Low |

### Security Considerations

#### Network Binding
```bash
# Local access only (secure)
HOST_IP=127.0.0.1

# Specific interface (recommended for production)
HOST_IP=192.168.1.100

# All interfaces (development only)
HOST_IP=0.0.0.0
```

#### Firewall Configuration
```bash
# Ubuntu/Debian
sudo ufw allow from MONITORING_HOST_IP to any port 9090

# CentOS/RHEL
sudo firewall-cmd --permanent --add-rich-rule="rule family='ipv4' source address='MONITORING_HOST_IP' port protocol='tcp' port='9090' accept"
```

### Performance Tuning

#### Resource Limits
```bash
# Add to .env for resource-constrained environments
MEMORY_LIMIT=256m
CPU_LIMIT=0.25

# For high-performance requirements
MEMORY_LIMIT=1g
CPU_LIMIT=1.0
```

#### GPU Selection
```bash
# Monitor specific GPUs only
CUDA_VISIBLE_DEVICES=0,1  # Only GPUs 0 and 1

# Monitor all GPUs (default)
CUDA_VISIBLE_DEVICES=all
```

## 🚨 Troubleshooting

### Common Issues

1. **Port already in use:**
   ```bash
   # Change port in .env
   ALL_SMI_PORT=9091
   ```

2. **High CPU usage:**
   ```bash
   # Reduce collection frequency
   ALL_SMI_INTERVAL=10

   # Add CPU limit
   CPU_LIMIT=0.5
   ```

3. **Network connectivity:**
   ```bash
   # Check bind address
   HOST_IP=0.0.0.0

   # Verify firewall rules
   sudo ufw status
   ```

4. **GPU not detected:**
   ```bash
   # Check NVIDIA drivers
   nvidia-smi

   # Verify Docker GPU support
   docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi
   ```

### Debug Configuration

Create a debug configuration:
```bash
# Copy production config
cp examples/worker-configs/production-worker.env algalon_worker/.env

# Add debug settings
echo "LOG_LEVEL=debug" >> algalon_worker/.env
echo "ALL_SMI_INTERVAL=1" >> algalon_worker/.env

# Deploy and check logs
cd algalon_worker
./setup.sh
docker logs -f algalon-all-smi
```

## 📚 Related Documentation

- [Worker Deployment Guide](../../WORKER_DEPLOYMENT.md) - Detailed worker setup
- [Hybrid Deployment Guide](../../HYBRID_DEPLOYMENT.md) - Cloud + on-premise setup
- [Host-Only Deployment](../../terraform/examples/host-only/) - Monitoring host setup
- [Main Documentation](../../README.md) - Complete project documentation

## 🆘 Support

- [GitHub Issues](https://github.com/appleparan/Algalon/issues) - Bug reports
- [Discussions](https://github.com/appleparan/Algalon/discussions) - Community support
- [Examples Repository](https://github.com/appleparan/Algalon/tree/main/examples) - More examples