# Algalon Host - Monitoring & Visualization Layer

## Overview
This is the monitoring and visualization layer that collects metrics from remote GPU worker nodes and displays them in Grafana dashboards.

## Architecture
- **VictoriaMetrics**: Time-series database for storing GPU metrics
- **VMAgent**: Scrapes metrics from remote dcgm-exporter instances
- **Grafana**: Visualization dashboards with VictoriaMetrics plugin

## Configuration

### Adding Remote Worker Nodes
Edit `node/targets/dcgm-targets.yml` to add your GPU worker nodes:

```yaml
- targets:
    - '192.168.1.100:9090'  # Replace with actual worker IP
    - '192.168.1.101:9090'  # Add more workers as needed
  labels:
    job: 'dcgm-exporter'
    cluster: 'production'
```

### Deployment Steps
1. Configure worker node IPs in `dcgm-targets.yml`
2. Ensure worker nodes are running dcgm-exporter on port 9090
3. Start monitoring stack: `docker-compose up -d`
4. Access Grafana at http://localhost:3000 (admin/admin)

### Network Requirements
- Host must be able to reach worker nodes on port 9090
- No special Docker networking needed (uses standard bridge)
- Worker nodes should have dcgm-exporter exposed on 0.0.0.0:9090

### Scaling
- Add new worker IPs to `dcgm-targets.yml`
- VMAgent automatically picks up changes within 30 seconds
- Support for multiple clusters with different labels