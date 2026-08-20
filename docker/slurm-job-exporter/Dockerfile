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

RUN pip3 install --no-cache-dir --break-system-packages \
      prometheus_client psutil

ADD https://raw.githubusercontent.com/guilbaults/slurm-job-exporter/${SJE_VERSION}/slurm-job-exporter.py \
    /opt/slurm-job-exporter/slurm-job-exporter.py

ENTRYPOINT ["python3", "/opt/slurm-job-exporter/slurm-job-exporter.py"]
CMD ["--monitor", "dcgm"]
