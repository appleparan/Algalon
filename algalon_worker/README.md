# Algalon Worker - GPU Metrics Exporter

## Overview
This is the GPU worker node component that exports NVIDIA GPU metrics via DCGM-exporter for remote monitoring.

## Architecture
- **DCGM-Exporter**: Exports NVIDIA GPU metrics on port 9090
- **Custom Metrics Config**: Optimized GPU metrics collection
- **Network Bridge**: Allows external access for metric scraping

## Deployment on Worker Nodes

### Prerequisites
- NVIDIA GPU with drivers installed
- Docker with nvidia-docker2 runtime
- GPU node accessible from monitoring host

### Setup Steps
1. Copy worker files to GPU node:
   ```bash
   scp -r algalon_worker/ gpu-node:/opt/algalon/
   ```

2. On the GPU worker node:
   ```bash
   cd /opt/algalon/algalon_worker
   docker-compose up -d
   ```

3. Verify metrics endpoint:
   ```bash
   curl http://localhost:9090/metrics
   ```

### Configuration
- **Port 9090**: DCGM metrics endpoint (must be accessible from host)
- **Metrics Config**: `dcgm-exporter-config.csv` defines collected metrics
- **Network**: Bridge mode allows external access

### Security Considerations
- Ensure port 9090 is only accessible from trusted monitoring hosts
- Consider using firewall rules to restrict access
- Monitor resource usage of dcgm-exporter

### Troubleshooting
- Check GPU visibility: `docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi`
- Verify DCGM service: `docker logs algalon-dcgm-exporter`
- Test metrics: `curl -v http://worker-ip:9090/metrics`