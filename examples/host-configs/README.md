# Algalon Host Configuration Examples

This directory contains example configuration files for different Algalon monitoring host deployment scenarios.

## 📁 Configuration Files

### `basic-host.env`
Basic configuration for development and testing environments.
- Default Grafana credentials (admin/admin)
- 30-day data retention
- Single worker target
- Minimal resource requirements

### `production-host.env`
Production-ready configuration with security and performance optimizations.
- Security-hardened Grafana settings
- 90-day data retention
- Multiple worker targets
- SSL/TLS support
- Resource limits and monitoring
- Backup configuration

### `multi-cluster-host.env`
Configuration for monitoring multiple clusters or environments.
- Multi-tenancy support
- Cluster-specific labeling
- High availability options
- Scaled resource allocation
- Dashboard organization by environment

### `minimal-host.env`
Lightweight configuration for edge or resource-constrained environments.
- Minimal resource usage
- 7-day data retention
- Disabled optional features
- Optimized for single worker monitoring

## 🚀 Usage

1. **Choose the appropriate configuration:**
   ```bash
   cp examples/host-configs/basic-host.env algalon_host/.env
   ```

2. **Customize for your environment:**
   ```bash
   vim algalon_host/.env
   ```

3. **Deploy the monitoring host:**
   ```bash
   cd algalon_host
   ./setup.sh
   ```

## ⚙️ Configuration Options

### Core Components

| Component | Description | Default Port | Purpose |
|-----------|-------------|--------------|---------|
| **Grafana** | Visualization dashboard | 3000 | Data visualization and alerting |
| **VictoriaMetrics** | Time-series database | 8428 | Metrics storage and querying |
| **VMAgent** | Metrics collection | N/A | Scraping and forwarding metrics |

### Essential Settings

| Variable | Description | Default | Examples |
|----------|-------------|---------|----------|
| `GRAFANA_ADMIN_PASSWORD` | Grafana admin password | `admin` | `secure_password_123` |
| `WORKER_TARGETS` | Comma-separated worker endpoints | `localhost:9090` | `10.0.1.100:9090,10.0.1.101:9090` |
| `VICTORIA_METRICS_RETENTION` | Data retention period | `30d` | `7d`, `90d`, `1y` |
| `VMAGENT_SCRAPE_INTERVAL` | Metrics collection frequency | `5s` | `10s`, `30s`, `1m` |

### Security Settings

| Variable | Description | Purpose |
|----------|-------------|---------|
| `GRAFANA_DISABLE_SIGNUPS` | Disable user registration | Prevent unauthorized access |
| `GRAFANA_SECURITY_SECRET_KEY` | Session encryption key | Secure session management |
| `ENABLE_HTTPS` | Enable SSL/TLS | Encrypted communication |
| `SSL_CERT_PATH` | SSL certificate location | HTTPS configuration |

## 🎯 Deployment Scenarios

### Development Environment
```bash
# Use basic configuration
cp examples/host-configs/basic-host.env algalon_host/.env

# Customize for local development
sed -i 's/WORKER_TARGETS=localhost:9090/WORKER_TARGETS=127.0.0.1:9090/' algalon_host/.env
```

### Production Environment
```bash
# Use production configuration
cp examples/host-configs/production-host.env algalon_host/.env

# Update critical settings
sed -i 's/GRAFANA_ADMIN_PASSWORD=change_me_in_production/GRAFANA_ADMIN_PASSWORD=your_secure_password/' algalon_host/.env
sed -i 's/WORKER_TARGETS=10.0.1.100:9090,10.0.1.101:9090,10.0.1.102:9090/WORKER_TARGETS=your_actual_workers/' algalon_host/.env
```

### Multi-Cluster Setup
```bash
# Use multi-cluster configuration
cp examples/host-configs/multi-cluster-host.env algalon_host/.env

# Configure cluster-specific worker targets
vim algalon_host/.env  # Update WORKER_TARGETS_* variables
```

### Edge/Minimal Setup
```bash
# Use minimal configuration
cp examples/host-configs/minimal-host.env algalon_host/.env

# Further reduce resource usage if needed
echo "VMAGENT_SCRAPE_INTERVAL=60s" >> algalon_host/.env
echo "VICTORIA_METRICS_RETENTION=3d" >> algalon_host/.env
```

## 🔧 Customization Guidelines

### Worker Target Configuration

#### Single Worker
```bash
WORKER_TARGETS=192.168.1.100:9090
```

#### Multiple Workers
```bash
WORKER_TARGETS=192.168.1.100:9090,192.168.1.101:9090,192.168.1.102:9090
```

#### Dynamic Target Discovery
```bash
# Use environment variables for flexibility
WORKER_TARGETS_PROD=10.0.1.100:9090,10.0.1.101:9090
WORKER_TARGETS_DEV=10.0.2.100:9090
WORKER_TARGETS=${WORKER_TARGETS_PROD},${WORKER_TARGETS_DEV}
```

### Resource Allocation

#### Development (Low Resources)
```bash
GRAFANA_MEMORY_LIMIT=256m
GRAFANA_CPU_LIMIT=0.5
VICTORIA_METRICS_MEMORY_LIMIT=512m
VICTORIA_METRICS_CPU_LIMIT=0.5
```

#### Production (High Performance)
```bash
GRAFANA_MEMORY_LIMIT=2g
GRAFANA_CPU_LIMIT=2.0
VICTORIA_METRICS_MEMORY_LIMIT=8g
VICTORIA_METRICS_CPU_LIMIT=4.0
```

### Data Retention Strategy

| Retention | Use Case | Storage Impact | Performance Impact |
|-----------|----------|---------------|--------------------|
| 7d | Edge/Testing | Minimal | Best |
| 30d | Development | Low | Good |
| 90d | Production | Medium | Good |
| 1y | Compliance/Analytics | High | Fair |

### Security Hardening

#### Grafana Security
```bash
# Strong authentication
GRAFANA_ADMIN_PASSWORD=complex_password_with_numbers_123
GRAFANA_DISABLE_SIGNUPS=true
GRAFANA_DISABLE_GRAVATAR=true

# Session security
GRAFANA_SECURITY_SECRET_KEY=your_random_secret_key_here
GRAFANA_SECURITY_ADMIN_PASSWORD_HASH=bcrypt_hash_of_password
```

#### Network Security
```bash
# Restrict VictoriaMetrics access
VICTORIA_METRICS_EXTERNAL_ACCESS=false

# Enable HTTPS
ENABLE_HTTPS=true
SSL_CERT_PATH=/etc/ssl/certs/algalon.crt
SSL_KEY_PATH=/etc/ssl/private/algalon.key
```

#### Firewall Configuration
```bash
# Ubuntu/Debian
sudo ufw allow 3000/tcp  # Grafana
sudo ufw deny 8428/tcp   # VictoriaMetrics (internal only)

# CentOS/RHEL
sudo firewall-cmd --permanent --add-port=3000/tcp
sudo firewall-cmd --reload
```

## 🚨 Troubleshooting

### Common Issues

1. **Workers not appearing in Grafana:**
   ```bash
   # Check worker targets configuration
   echo $WORKER_TARGETS

   # Test worker connectivity
   curl -f http://worker-ip:9090/metrics

   # Check VMAgent logs
   docker logs algalon-vmagent
   ```

2. **High memory usage:**
   ```bash
   # Reduce retention period
   VICTORIA_METRICS_RETENTION=7d

   # Add memory limits
   VICTORIA_METRICS_MEMORY_LIMIT=2g

   # Increase scrape interval
   VMAGENT_SCRAPE_INTERVAL=30s
   ```

3. **Grafana login issues:**
   ```bash
   # Reset admin password
   docker exec -it algalon-grafana grafana-cli admin reset-admin-password newpassword

   # Check admin user
   echo $GRAFANA_ADMIN_USER
   echo $GRAFANA_ADMIN_PASSWORD
   ```

4. **SSL/TLS certificate issues:**
   ```bash
   # Verify certificate files
   ls -la $SSL_CERT_PATH $SSL_KEY_PATH

   # Test certificate validity
   openssl x509 -in $SSL_CERT_PATH -text -noout
   ```

### Debug Configuration

Create a debug configuration for troubleshooting:
```bash
# Copy basic config
cp examples/host-configs/basic-host.env algalon_host/.env

# Add debug settings
echo "LOG_LEVEL=debug" >> algalon_host/.env
echo "VMAGENT_SCRAPE_INTERVAL=5s" >> algalon_host/.env
echo "GRAFANA_LOG_LEVEL=debug" >> algalon_host/.env

# Deploy and monitor logs
cd algalon_host
./setup.sh
docker logs -f algalon-grafana
docker logs -f algalon-victoria-metrics
docker logs -f algalon-vmagent
```

### Performance Monitoring

Monitor host resource usage:
```bash
# Container resource usage
docker stats algalon-grafana algalon-victoria-metrics algalon-vmagent

# Host system resources
top -p $(docker inspect -f '{{.State.Pid}}' algalon-grafana algalon-victoria-metrics algalon-vmagent | tr '\n' ',' | sed 's/,$//')

# Disk usage
du -sh /var/lib/docker/volumes/algalon_*
```

## 🔗 Integration Examples

### Cloud Deployment
```bash
# For Google Cloud Platform
VMAGENT_EXTERNAL_LABELS=environment=production,cloud=gcp,region=us-central1

# For AWS
VMAGENT_EXTERNAL_LABELS=environment=production,cloud=aws,region=us-east-1

# For Azure
VMAGENT_EXTERNAL_LABELS=environment=production,cloud=azure,region=eastus
```

### Kubernetes Integration
```bash
# Kubernetes cluster monitoring
VMAGENT_EXTERNAL_LABELS=environment=production,platform=kubernetes,cluster=main

# Add namespace labeling
WORKER_TARGETS=worker-service.algalon-system.svc.cluster.local:9090
```

### Hybrid Deployment
```bash
# Mixed cloud and on-premise
WORKER_TARGETS_CLOUD=10.0.1.100:9090,10.0.1.101:9090
WORKER_TARGETS_ONPREM=192.168.1.100:9090,192.168.1.101:9090
WORKER_TARGETS=${WORKER_TARGETS_CLOUD},${WORKER_TARGETS_ONPREM}

VMAGENT_EXTERNAL_LABELS=environment=production,deployment=hybrid
```

## 📚 Related Documentation

- [Host Deployment Guide](../../HOST_DEPLOYMENT.md) - Detailed host setup
- [Terraform Host-Only Example](../../terraform/examples/host-only/) - Infrastructure as Code
- [Worker Configuration Examples](../worker-configs/) - Worker setup examples
- [Main Documentation](../../README.md) - Complete project documentation

## 🆘 Support

- [GitHub Issues](https://github.com/appleparan/Algalon/issues) - Bug reports and feature requests
- [Discussions](https://github.com/appleparan/Algalon/discussions) - Community support
- [Examples Repository](https://github.com/appleparan/Algalon/tree/main/examples) - More configuration examples