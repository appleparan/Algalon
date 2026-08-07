# Scrape targets

Copy the templates and fill in your worker hostnames (one file per job;
file names are fixed — vmagent watches exactly these):

    cp ../../../../monitoring/scrape/targets/dcgm-targets.yml.example dcgm-targets.yml
    cp ../../../../monitoring/scrape/targets/node-targets.yml.example node-targets.yml
    cp ../../../../monitoring/scrape/targets/all-smi-targets.yml.example all-smi-targets.yml
    cp ../../../../monitoring/scrape/targets/slurm-targets.yml.example slurm-targets.yml
    cp ../../../../monitoring/scrape/targets/slurm-job-targets.yml.example slurm-job-targets.yml

Every entry must carry a `node` label — Alertmanager groups and inhibits
on it. Real `*.yml` files here are gitignored (deployment-specific).
Leave `all-smi-targets.yml` as an empty list (`[]`) if no worker runs the
all-smi profile.

The two Slurm files are only needed when Slurm integration is in use;
leave them as an empty list (`[]`) otherwise. `slurm-targets.yml` holds the
single cluster-wide prometheus-slurm-exporter (port 9092) and needs no
`node` label. `slurm-job-targets.yml` holds one slurm-job-exporter entry per
compute node (port 9798), and every entry **must** carry a `node` label
matching the one used in `dcgm-targets.yml` / `node-targets.yml` — that is
the join key between per-job and per-node series.
