# 배포

[English](../deployment.md) | **한국어**

Algalon은 세 가지 배포 방식을 제공합니다. 세 방식 모두 동일한
`monitoring/` 내용을 사용하므로, 어떤 방식으로 띄우든 rule과 대시보드,
알림 정책은 완전히 같습니다.

| 방식 | 적합한 환경 | 가이드 |
| --- | --- | --- |
| 로컬 k3s 클러스터 | 온프레미스 GPU 클러스터 (**권장**) | [`deploy/k3s/`](../../deploy/k3s/README.md) |
| Kubernetes / Helm | 이미 운영 중인 클러스터 | [`deploy/helm/algalon/`](../../deploy/helm/algalon/README.md) |
| Docker Compose | 단일 노드, 개발 환경, 소규모 클러스터 | [`deploy/compose/`](../../deploy/compose/README.md) |

## 로컬 k3s 클러스터 (온프레미스 권장)

설계의 전제는 학습 워크로드가 지금 돌던 방식 그대로 — Docker든
Apptainer/Singularity든 베어 프로세스든 — 호스트에서 계속 돌고, Algalon이
이를 절대 건드리지 않는다는 것입니다. k3s agent는 각 노드가 어떤 런타임을
쓰든 그 *옆에서* 동작하며 exporter DaemonSet만 스케줄링합니다. k3s는 자체
containerd를 내장하므로 호스트 컨테이너 스택과 상태를 공유하지 않고,
kubelet은 호스트 워크로드를 보거나 evict할 수 없으며, dcgm-exporter는
`nvidia.com/gpu`를 요청하지 않기 때문에 학습 잡과 GPU 할당을 두고 경쟁하지
않습니다. 런북에서 Docker를 가장 비중 있게 다루는 이유는 전제라서가 아니라,
iptables를 함께 만지는 유일한 런타임이기 때문입니다 — preflight 스크립트가
검사하는 게 바로 그 지점입니다. Apptainer처럼 데몬 없는 런타임은 k3s와
공유하는 것이 더 적어 별도 고려가 필요 없습니다.

직접 관리하는 Compose 스택 대비 얻는 것: 노드 추가가 `curl` 한 줄이면
끝나고(DaemonSet과 scrape 디스커버리가 알아서 잡아냅니다), 업그레이드는
`helm upgrade` 한 번이며, 관리해야 할 타깃 파일이 없습니다.

남는 충돌 지점은 호스트 네트워킹 — 포트, flannel CIDR, iptables 상호작용 —
인데, 함께 제공되는 preflight 스크립트가 설치 전에 정확히 이 부분을
점검합니다. k3s의 기본 애드온(Traefik, ServiceLB, metrics-server)은 설치
시점에 비활성화되므로 호스트의 80/443 포트를 가져가는 것도 없습니다.

```bash
./deploy/k3s/preflight.sh server      # read-only checks, PASS/WARN/FAIL
./deploy/k3s/install-server.sh        # k3s server, default addons disabled
make helm-sync
helm install algalon deploy/helm/algalon --namespace algalon \
  --create-namespace --set alertmanager.slack.existingSecret=algalon-slack
K3S_URL=https://<server>:6443 K3S_TOKEN=<token> \
  ./deploy/k3s/install-agent.sh       # on every GPU node
```

두 인스톨러 모두 k3s가 이미 설치되어 있으면 실행을 거부합니다. 제거는
의도적으로 수동 절차로 남겨두었고,
[런북](../../deploy/k3s/README.md)에 정리되어 있습니다.

## Kubernetes / Helm

이미 운영 중인 클러스터를 위한 방식입니다. exporter는
`nvidia.com/gpu.present` 라벨이 붙은 GPU 노드에 DaemonSet으로 뜨고, 호스트
스택 — VictoriaMetrics, vmagent, vmalert, Alertmanager, Grafana — 은
Deployment로 뜹니다. vmagent가 Kubernetes API를 통해 exporter 파드를
디스커버리하므로 scrape 타깃을 손으로 관리할 일이 없습니다.

클러스터 멤버가 아닌 머신 — 자체 exporter를 돌리는 베어메탈 GPU 노드,
Slurm 컨트롤러 — 은 `dcgmExporter.staticTargets` /
`nodeExporter.staticTargets`(그리고 Slurm exporter용 `slurm.*Targets`)에
정적으로 등록합니다. 정적 항목도 DaemonSet 파드와 동일한 `job`·`node` 라벨
계약을 따릅니다. 자세한 내용은
[차트 README](../../deploy/helm/algalon/README.md#scraping-and-labels)를
참고하세요.

한 가지 기억할 것: 최초 설치 전에 반드시 `make helm-sync`를 실행해야
합니다. Helm은 차트 바깥의 파일을 읽을 수 없어서, 차트의 `files/`
디렉터리를 `monitoring/`에서 생성하며 이 디렉터리는 git에서 제외됩니다.

`monitoring/`이 제공하는 것 이상으로 alert rule, 대시보드, scrape 설정이
필요한 사이트는 `vmalert.extraRules`, `grafana.extraDashboards`,
`vmagent.extraScrapeConfigs` 값으로 주입할 수 있습니다. 자세한 내용은 차트
README의 [Site extensions](../../deploy/helm/algalon/README.md#site-extensions)를
참고하세요.

## Docker Compose

스택은 두 개입니다. `deploy/compose/host`(저장, 알림, UI — 한 대의 머신)와
`deploy/compose/worker`(exporter — 모든 GPU 노드)입니다. 워커 노드는 호스트
쪽에서 타깃 템플릿을 복사해 등록하고, all-smi는 `--profile all-smi`로
선택해서 켭니다. 단일 머신이나 규모가 작고 잘 바뀌지 않는 클러스터라면 이
방식이 가장 빠릅니다.

## CPU 메모리 대역폭 (선택)

호스트 메모리 버스가 포화된 GPU 노드는(데이터 로더, pinned-memory 복사)
모든 DCGM 메트릭에서 한가해 보이고 모든 node_exporter 메트릭에서 정상으로
보입니다. PSI는 정체를, NUMA 카운터는 배치를 잴 뿐 대역폭을 재지 않기
때문입니다. 대역폭을 볼 수 있는 커널 인터페이스는 resctrl MBM(Memory
Bandwidth Monitoring)뿐이어서, Algalon은
`monitoring/exporters/resctrl-mbm-textfile.sh`를 제공합니다. 이 스크립트는
카운터를 node_exporter textfile로 써서 Host Saturation 대시보드에
공급합니다. Slurm 스크립트와 마찬가지로 사이트 쪽 산출물이며, Algalon이
배포하거나 스케줄링하지 않습니다.

**워크로드에 비용을 주지 않도록 만들었습니다.** MBM 파일을 읽으면 커널이
L3 도메인마다 하드웨어 카운터를 한 번 읽으므로, 비용은 그룹 수 × 도메인 수
× 빈도입니다. 스크립트는 기본 모니터 그룹만, 실행당 한 번, 데몬 없이
읽습니다. 30초마다 읽기 몇 번입니다. 모니터 그룹을 만들지 않고,
`schemata`에 쓰지 않으며, resctrl을 직접 마운트하지도 않습니다. 그 대가는
해상도입니다. 노드와 L3 도메인 단위의 대역폭만 얻고 잡 단위는 얻지
못합니다. 잡별 그룹은 잡마다 RMID를 쓰고 워크로드의 컨텍스트 스위치에 MSR
쓰기를 더하는데, 이 설계가 피하려는 부담이 바로 그것입니다.

측정할 노드마다 root로 설치합니다.

```bash
grep -c cqm_mbm_total /proc/cpuinfo            # 0이면 이 CPU는 MBM 미지원
mount -t resctrl resctrl /sys/fs/resctrl       # -o mba_MBps는 붙이지 않습니다
install -m 0755 monitoring/exporters/resctrl-mbm-textfile.sh \
  /usr/local/bin/algalon-resctrl-mbm-textfile
```

```ini
# /etc/systemd/system/algalon-resctrl-mbm.service
[Unit]
Description=Algalon resctrl MBM textfile export
ConditionPathIsDirectory=/sys/fs/resctrl

[Service]
Type=oneshot
ExecStart=/usr/local/bin/algalon-resctrl-mbm-textfile
Nice=19
IOSchedulingClass=idle
```

```ini
# /etc/systemd/system/algalon-resctrl-mbm.timer
[Unit]
Description=Run the Algalon resctrl MBM export every 30 s

[Timer]
OnBootSec=30s
OnUnitActiveSec=30s
AccuracySec=1s

[Install]
WantedBy=timers.target
```

이어서 `systemctl daemon-reload && systemctl enable --now
algalon-resctrl-mbm.timer`를 실행합니다. resctrl 마운트는 `/etc/fstab`에
추가하지 않으면 재부팅 후 사라집니다.

node-exporter는 스크립트가 쓰는 디렉터리(기본값
`/var/lib/node_exporter/textfile`)를 읽어야 합니다. compose 워커 스택은
기본으로 읽고(`NODE_EXPORTER_TEXTFILE_DIR`), 차트에서는
`nodeExporter.textfileDirectory`를 설정합니다.

한계는 다음과 같고, 이 프로젝트가 하드웨어에서 검증한 것은 없습니다. AMD
CPU는 하드웨어 카운터가 모자라면 `Unavailable`을 돌려주며, 이는 0이 아니라
빈 구간으로 나타납니다. Sub-NUMA Clustering은 최신 커널에서만 값이
정확합니다. 플랫폼의 최대 대역폭은 내보내지 않으므로 대시보드에 "100%"
선이 없습니다. 노드 자신의 과거 값이나 STREAM 실행 결과와 비교하세요.
MBM을 쓸 수 없는 곳에서는 Intel PCM이나 AMD uProf가 이 파이프라인 밖에서
같은 것을 측정합니다.

## 시크릿

Slack 웹훅 URL은 항상 배포 시점에 주입합니다. Compose에서는 마운트된 시크릿
파일로, Helm에서는 Kubernetes Secret(또는 `existingSecret` 참조)으로
전달합니다. git에 저장되는 값은 없으며, 값이 없으면 Alertmanager는 조용히
망가진 알림 채널을 배포하는 대신 렌더링 자체를 거부합니다.
