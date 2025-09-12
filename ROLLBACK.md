# Rollback Plan: all-smi → DCGM Migration

## Quick Rollback Commands

If issues occur with all-smi, revert to DCGM-based monitoring:

### Step 1: Restore Worker Configuration
```bash
cd algalon_worker
git checkout HEAD~1 -- docker-compose.yml
docker compose down && docker compose up -d
```

### Step 2: Restore Host Configuration  
```bash
cd algalon_host
git checkout HEAD~1 -- prometheus.yml
git checkout HEAD~1 -- grafana/dashboards/gpu-monitoring.json
# Remove all-smi specific files
rm node/targets/all-smi-targets.yml
rm grafana/dashboards/system-monitoring.json
docker compose restart vmagent grafana
```

### Step 3: Verify DCGM Metrics
```bash
curl http://localhost:9400/metrics | grep DCGM_FI_DEV
```

## Detailed Rollback Information

### What Gets Reverted
- **Worker**: `all-smi` → `nvidia/dcgm-exporter:4.2.3-4.1.3-ubuntu22.04`
- **Host Scraping**: `all-smi` job → `dcgm-exporter` job  
- **Dashboards**: all-smi metrics → DCGM metrics
- **Target Files**: all-smi-targets.yml removed

### What Stays
- VictoriaMetrics database (retains historical data)
- Grafana datasource configuration
- Network and volume configurations
- Docker compose infrastructure

### Verification Steps
1. ✅ Worker containers running DCGM-exporter
2. ✅ VMAgent scraping DCGM metrics successfully
3. ✅ Grafana dashboards displaying GPU data
4. ✅ No error logs in any containers

## Emergency Contacts & Resources
- **Git Commits**: 
  - all-smi version: `082384e`
  - DCGM version: `7f2db20` (pre-migration)
- **Key Metric Names**: 
  - DCGM: `DCGM_FI_DEV_GPU_UTIL`, `DCGM_FI_DEV_FB_USED`
  - all-smi: `all_smi_gpu_utilization`, `all_smi_gpu_memory_used_bytes`

## Prevention for Future
- Test all-smi in staging environment first
- Verify metric compatibility before production deployment  
- Monitor system resource usage during transition
- Have Docker environment properly configured before deployment