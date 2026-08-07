# Scrape targets

Copy the templates and fill in your worker hostnames (one file per job;
file names are fixed — vmagent watches exactly these):

    cp ../../../../monitoring/scrape/targets/dcgm-targets.yml.example dcgm-targets.yml
    cp ../../../../monitoring/scrape/targets/node-targets.yml.example node-targets.yml
    cp ../../../../monitoring/scrape/targets/all-smi-targets.yml.example all-smi-targets.yml

Every entry must carry a `node` label — Alertmanager groups and inhibits
on it. Real `*.yml` files here are gitignored (deployment-specific).
Leave `all-smi-targets.yml` as an empty list (`[]`) if no worker runs the
all-smi profile.
