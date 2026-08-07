# Algalon on k3s (local / on-prem)

The recommended path for on-prem GPU clusters: a single k3s server on the
central node, a k3s agent on every GPU node, and the Phase 4 Helm chart
(`deploy/helm/algalon`) on top. Three scripts live here:

| Script | What it does |
|---|---|
| `preflight.sh <server\|agent>` | read-only host checks; prints PASS/WARN/FAIL |
| `install-server.sh` | preflight + k3s server with the addons disabled |
| `install-agent.sh` | preflight + k3s agent join (`K3S_URL`/`K3S_TOKEN`) |

Both installers **refuse to run when k3s is already installed** — there is
no `--force`. Removing a cluster is a deliberate manual step; see
[Rollback](#rollback).

## Why k3s can sit next to Docker training workloads

GPU nodes keep running their training jobs under Docker. The k3s agent
runs *alongside* Docker and only schedules the exporter DaemonSets. The
two container stacks do not share state:

- The agent ships its **own embedded containerd** with its own socket
  (`/run/k3s/containerd/containerd.sock`), its own state directory
  (`/var/lib/rancher/k3s/agent/containerd`) and its own image store.
  Docker's daemon, socket and images are untouched.
- The kubelet only sees pods from its own containerd. It cannot inspect,
  evict, restart or garbage-collect a Docker container — a training job is
  invisible to it, and `k3s-killall.sh` does not reach it either.
- **dcgm-exporter requests no `nvidia.com/gpu`.** It asks for CPU and
  memory only (`deploy/helm/algalon/values.yaml`) and reads the GPUs
  through DCGM, so it never competes with training jobs for a GPU
  allocation and needs no device plugin.
- **nvidia-container-toolkit is auto-detected.** k3s finds `nvidia-ctk` at
  startup and generates a `nvidia` RuntimeClass in its own containerd
  config. Nothing writes to `/etc/docker/daemon.json`, so Docker's runtime
  configuration is unaffected.

What *is* shared — and therefore the entire conflict surface — is host
networking:

| Surface | Detail | Preflight |
|---|---|---|
| Ports (server) | 6443/tcp kube-apiserver | FAIL if taken |
| Ports (agent) | 10250/tcp kubelet, 8472/udp flannel VXLAN | FAIL if taken |
| Ports (exporters) | 9100 node-exporter, 9400 dcgm-exporter hostPorts | WARN if taken |
| CIDRs | flannel pods `10.42.0.0/16`, services `10.43.0.0/16` | FAIL on route overlap |
| iptables | k3s writes its own chains; Docker keeps `DOCKER`/`DOCKER-USER` | — |
| Host firewall | firewalld/ufw can drop node-to-node traffic | WARN if active |

`preflight.sh` covers all of it and is safe to re-run at any time — it
only reads.

### Why the default addons are disabled

`install-server.sh` pins:

    --disable traefik --disable servicelb --disable metrics-server

ServiceLB (klipper-lb) claims host ports on **every** node for any
`LoadBalancer` Service, and Traefik asks it for 80/443 — exactly the ports
a shared training box is most likely to already be using. metrics-server
is dead weight here because Algalon collects its own metrics. Algalon
exposes nothing but ClusterIP Services, so none of the three is needed.

## Prerequisites

- One central node (control plane + Algalon host stack) and one or more
  GPU nodes.
- `kubectl` and `helm` on whatever machine you drive the cluster from.
- Slack webhook URLs — the chart refuses to render without them, because
  a missing Secret means a permanently silent notifier.
- On GPU nodes: NVIDIA driver + `nvidia-container-toolkit` (preflight
  WARNs when `nvidia-ctk` is absent).

## Install order

Server first, then the stack, then the agents. Exporters land on agents as
soon as they join, so the order is not load-bearing — it just gives you a
working Grafana before there is anything to look at.

### 1. Central node — k3s server

    ./deploy/k3s/preflight.sh server        # optional; the installer runs it
    ./deploy/k3s/install-server.sh

If the default CIDRs collide with your site network, preflight FAILs and
tells you to pick free ranges. Pass the same values to both:

    export ALGALON_CLUSTER_CIDR=10.52.0.0/16
    export ALGALON_SERVICE_CIDR=10.53.0.0/16
    ./deploy/k3s/install-server.sh          # -> --cluster-cidr/--service-cidr

`INSTALL_K3S_VERSION` and `INSTALL_K3S_CHANNEL` pass through to
`get.k3s.io` if you need to pin a version.

Then take the kubeconfig:

    sudo cat /etc/rancher/k3s/k3s.yaml       # rewrite 127.0.0.1 for remote use
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
    kubectl get nodes

### 2. Slack Secret + Helm install

The key names are a contract with the Alertmanager policy's
`api_url_file` paths:

    kubectl create namespace algalon
    kubectl -n algalon create secret generic algalon-slack \
      --from-literal=slack_webhook_critical='https://hooks.slack.com/services/T.../B.../xxx' \
      --from-literal=slack_webhook_warning='https://hooks.slack.com/services/T.../B.../yyy'

    make helm-sync                           # files/ is generated + git-ignored
    helm install algalon deploy/helm/algalon \
      --namespace algalon \
      --set alertmanager.slack.existingSecret=algalon-slack

See `deploy/helm/algalon/README.md` for the full values reference.

    kubectl -n algalon port-forward svc/algalon-grafana 3000:3000

### 3. GPU nodes — k3s agent

Read the token on the server, then on each GPU node:

    sudo cat /var/lib/rancher/k3s/server/node-token     # on the server

    K3S_URL=https://<server>:6443 K3S_TOKEN=<token> \
      ./deploy/k3s/install-agent.sh

Then label the node so the GPU DaemonSets schedule on it. gpu-operator
sets this label automatically; a bare k3s agent does not:

    kubectl label node <node> nvidia.com/gpu.present=true

### 4. GPU RuntimeClass

If k3s auto-detected nvidia-container-toolkit it created an `nvidia`
RuntimeClass, and dcgm-exporter must be told to use it — otherwise the pod
starts without GPU visibility and exports nothing:

    kubectl get runtimeclass                 # is 'nvidia' there?

    helm upgrade algalon deploy/helm/algalon --reuse-values \
      --set dcgmExporter.runtimeClassName=nvidia

Verify:

    kubectl -n algalon logs -l app.kubernetes.io/component=dcgm-exporter --tail=20
    kubectl -n algalon port-forward svc/algalon-victoriametrics 8428:8428
    curl -s 'localhost:8428/api/v1/query?query=up{job="dcgm"}'

## Adding a node

One command on the new node, plus the label — nothing changes on the
server or in the Helm release. The DaemonSets pick the node up on their
own:

    K3S_URL=https://<server>:6443 K3S_TOKEN=<token> \
      ./deploy/k3s/install-agent.sh
    kubectl label node <node> nvidia.com/gpu.present=true

## Removing a node

Documented, not scripted — none of the scripts here uninstall anything.
Run these by hand, in this order:

    kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
    kubectl delete node <node>

    # then, on the node itself:
    /usr/local/bin/k3s-agent-uninstall.sh

`k3s-agent-uninstall.sh` ships with k3s. It removes the agent, its
containerd state and its images — and nothing owned by Docker, so training
workloads on the node survive it.

## Upgrades

**The Algalon stack** — rules, dashboards, images, thresholds — is a chart
upgrade. Always re-sync `files/` first; `helm upgrade` does not:

    make helm-sync
    helm upgrade algalon deploy/helm/algalon --reuse-values

**k3s itself** re-runs the installer against a channel or a pinned
version. Upgrade the server first, then the agents, one at a time:

    curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=stable sh -

Note that this is the one operation `install-server.sh` will not do for
you: it refuses on an existing install by design, so an in-place k3s
upgrade is an explicit manual command. Drain each agent before upgrading
it (`kubectl drain ... --ignore-daemonsets`).

## Rollback

Uninstalling is entirely k3s's own tooling — Algalon ships no uninstall
script and never calls these:

    helm uninstall algalon -n algalon        # 1. remove the stack
    kubectl delete namespace algalon         # 2. Secrets, PVCs, ConfigMaps

    /usr/local/bin/k3s-agent-uninstall.sh    # 3. on each agent node
    /usr/local/bin/k3s-uninstall.sh          # 4. on the server node

Step 2 deletes the VictoriaMetrics PVC and with it all stored metrics.
Steps 3 and 4 are irreversible for the cluster, and `k3s-uninstall.sh`
also runs `k3s-killall.sh` — which stops k3s pods and unmounts k3s
mounts, but does not touch Docker containers.

Nothing here needs to run to make training work again: Docker was never
reconfigured in the first place.

## Firewalls

k3s manages its own iptables chains, but a host firewall in front of them
still drops node-to-node traffic. Open, between cluster nodes only:

| Port | Direction | For |
|---|---|---|
| 6443/tcp | agents -> server | kube-apiserver |
| 10250/tcp | server -> agents | kubelet (logs, exec, metrics) |
| 8472/udp | all -> all | flannel VXLAN |

firewalld also needs the pod and service CIDRs trusted, otherwise pod
egress is masqueraded into a drop:

    firewall-cmd --permanent --zone=trusted --add-source=10.42.0.0/16
    firewall-cmd --permanent --zone=trusted --add-source=10.43.0.0/16
    firewall-cmd --reload

`preflight.sh` WARNs (never fails) when firewalld or ufw is active — a
correctly configured firewall is fine, it just can't tell from the host.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Agent never appears in `kubectl get nodes` | 6443 blocked, or wrong token |
| Pods on one node cannot reach Services | 8472/udp blocked; CIDR overlap |
| dcgm-exporter pods `Pending` | node missing `nvidia.com/gpu.present=true` |
| dcgm-exporter runs but exports no GPUs | `dcgmExporter.runtimeClassName` unset |
| node-exporter `CrashLoopBackOff` | host port 9100 already taken (preflight WARN) |
| `up{job="dcgm"}` missing entirely | pod not labelled `algalon.io/scrape=true` |
