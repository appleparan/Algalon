# slurm-job-exporter as a remote DCGM client. The image ships the DCGM
# python bindings only — nv-hostengine runs on the host; the exporter
# finds it via hostPID and connects over hostNetwork localhost:5555.
# Keep the DCGM major here aligned with the host engines it talks to.
FROM ubuntu:24.04

ARG SJE_VERSION=v0.4.12
ARG DCGM_PKG=datacenter-gpu-manager-4-core

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl python3 python3-pip \
    && curl -fsSL https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb \
       -o /tmp/cuda-keyring.deb \
    && dpkg -i /tmp/cuda-keyring.deb && rm /tmp/cuda-keyring.deb \
    && apt-get update && apt-get install -y --no-install-recommends ${DCGM_PKG} \
    && rm -rf /var/lib/apt/lists/*

# The whole point of installing ${DCGM_PKG} is the python bindings the
# exporter adds to sys.path at runtime. NVIDIA has moved that directory
# between DCGM majors, so fail the BUILD rather than ship an image whose
# --monitor=dcgm silently degrades to no GPU metrics.
RUN python3 -c "import glob; assert glob.glob('/usr/share/datacenter-gpu-manager-*/bindings/python3/'), 'DCGM python bindings missing'"

RUN pip3 install --no-cache-dir --break-system-packages \
      prometheus_client psutil

ADD https://raw.githubusercontent.com/guilbaults/slurm-job-exporter/${SJE_VERSION}/slurm-job-exporter.py \
    /opt/slurm-job-exporter/slurm-job-exporter.py

# Per-job GPU attribution: cgroup_gpus() shells out to `get_gpus.sh` by bare
# name, so it must be on PATH and executable. It binds itself into the job's
# cgroup and runs `nvidia-smi -L`; nvidia-smi itself is NOT baked in — the
# nvidia container runtime injects it (see the DaemonSet's NVIDIA_* env and
# runtimeClassName). Same pinned tag as the exporter above.
ADD https://raw.githubusercontent.com/guilbaults/slurm-job-exporter/${SJE_VERSION}/get_gpus.sh \
    /usr/local/bin/get_gpus.sh
# ADD does not set the exec bit, and `chmod +x` alone would leave the file
# unreadable to non-root — a #! script must be READ by its interpreter, not
# merely executed. 0755 keeps it runnable under a runAsUser override too.
RUN chmod 0755 /usr/local/bin/get_gpus.sh

ENTRYPOINT ["python3", "/opt/slurm-job-exporter/slurm-job-exporter.py"]
CMD ["--monitor", "dcgm"]
