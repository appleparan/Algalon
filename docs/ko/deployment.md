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

설계의 전제는 학습 워크로드가 이미 Docker에서 돌고 있고 앞으로도 그대로
두어야 한다는 것입니다. 각 GPU 노드에서 k3s agent가 Docker와 *나란히*
동작하면서 exporter DaemonSet만 스케줄링합니다. 두 컨테이너 스택은 상태를
공유하지 않고(k3s는 자체 containerd를 내장합니다), kubelet은 Docker
컨테이너를 보거나 evict할 수 없으며, dcgm-exporter는 `nvidia.com/gpu`를
요청하지 않기 때문에 학습 잡과 GPU 할당을 두고 경쟁하지 않습니다.

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

한 가지 기억할 것: 최초 설치 전에 반드시 `make helm-sync`를 실행해야
합니다. Helm은 차트 바깥의 파일을 읽을 수 없어서, 차트의 `files/`
디렉터리를 `monitoring/`에서 생성하며 이 디렉터리는 git에서 제외됩니다.

## Docker Compose

스택은 두 개입니다. `deploy/compose/host`(저장, 알림, UI — 한 대의 머신)와
`deploy/compose/worker`(exporter — 모든 GPU 노드)입니다. 워커 노드는 호스트
쪽에서 타깃 템플릿을 복사해 등록하고, all-smi는 `--profile all-smi`로
선택해서 켭니다. 단일 머신이나 규모가 작고 잘 바뀌지 않는 클러스터라면 이
방식이 가장 빠릅니다.

## 시크릿

Slack 웹훅 URL은 항상 배포 시점에 주입합니다. Compose에서는 마운트된 시크릿
파일로, Helm에서는 Kubernetes Secret(또는 `existingSecret` 참조)으로
전달합니다. git에 저장되는 값은 없으며, 값이 없으면 Alertmanager는 조용히
망가진 알림 채널을 배포하는 대신 렌더링 자체를 거부합니다.
