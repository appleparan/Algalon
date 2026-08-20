# Slurm 연동

[English](../slurm.md) | **한국어**

Algalon은 하드웨어 관점의 지표와 함께 Slurm 스케줄러가 보는 클러스터를 같이
읽을 수 있습니다. 어떤 잡이 큐에 쌓여 있는지, 스케줄러가 어떤 노드를
포기했는지, 그리고 잡 단위로 누가 그 잡의 주인이며 잡이 붙잡고 있는 GPU가
실제로 일을 하고 있는지까지요. 이 연동은 완전히 opt-in입니다. scrape 잡
두 개가 추가될 뿐이고, 타깃을 등록하지 않으면 시계열도, 알림도 생기지
않으며 대시보드 두 개가 비어 있을 뿐입니다.

여기 나오는 것 중 Algalon이 배포해 주는 것은 선택 사항인 클러스터 내부
[jobExporter DaemonSet](#클러스터-내부-jobexporter-daemonset) 하나뿐입니다.
두 exporter 모두 호스트에서 Slurm CLI나 cgroup에 접근해야 하므로, 기본적으로는
Slurm 머신 위에서 일반적인 호스트 서비스로 실행하고 Algalon은 그것을
scrape하기만 합니다.

## exporter 두 개, scrape 잡 두 개

Slurm에는 성격이 다른 두 가지 질문이 있고, 둘 다 잘 대답해 주는 exporter는
없습니다.

| Exporter | 실행 위치 | 포트 | scrape 잡 | 대답하는 질문 |
| --- | --- | --- | --- | --- |
| [prometheus-slurm-exporter](https://github.com/rivosinc/prometheus-slurm-exporter) | slurmctld 또는 로그인 노드, 클러스터당 하나 | 9092 | `slurm` | *스케줄러*는 건강한가? 큐 깊이, 잡 상태, 노드 상태, 파티션 |
| [slurm-job-exporter](https://github.com/guilbaults/slurm-job-exporter) | 모든 계산 노드 | 9798 | `slurm-job` | *할당된 하드웨어*는 쓰이고 있는가? 잡별 cgroup CPU/메모리, GPU별 사용률·메모리·전력 |

큐 exporter는 클러스터 전역이라 시계열에 `node` 레이블이 붙지 않습니다.
잡 exporter는 노드 단위이므로 타깃에 `node` 레이블이 **반드시** 있어야
합니다. 두 exporter를 함께 쓰는 이유가 바로 그 레이블입니다
([`on(node)` 조인 계약](#onnode-조인-계약) 참고).

## exporter 설치하기

### 큐 exporter

[prometheus-slurm-exporter](https://github.com/rivosinc/prometheus-slurm-exporter)를
slurmctld 호스트나 로그인 노드 — `sinfo`와 `squeue`가 동작하는 곳이면
어디든 — 에서 실행합니다. 권장 모드(`-slurm.cli-fallback`)에서는 slurmrestd가
아니라 Slurm CLI를 직접 호출하기 때문입니다. 클러스터당 하나면 충분합니다. 두 번째 인스턴스는 동일한 클러스터 전역 시계열을 중복
생성할 뿐입니다. `:9092`로 listen하게 하고, vmagent가 도는 호스트에서 그
포트에 접근할 수 있게 열어 둡니다.

### 잡 exporter

[slurm-job-exporter](https://github.com/guilbaults/slurm-job-exporter)는
**모든** 계산 노드에서 `:9798`로 실행합니다. Slurm의 cgroup 계층을 직접
읽기 때문에 전제 조건이 두 가지 있습니다.

- `slurm.conf`의 `JobAcctGatherType=jobacct_gather/cgroup`. cgroup 어카운팅이
  꺼져 있으면 읽을 잡별 cgroup 자체가 없고, exporter는 아무것도 보고하지
  않습니다.
- GPU 단위 메트릭을 위한 데이터 소스. 기본값이자 업스트림 권장인
  DCGM(`--monitor dcgm`), 또는 선택 모듈 `nvidia-ml-py`를 통한
  NVML(`--monitor nvml`) 중 하나가 필요합니다. 어느 쪽이든 exporter는 각
  cgroup 안에서 `nvidia-smi -L`을 실행해 잡에 어떤 GPU가 할당되었는지
  알아냅니다. 둘 다 없으면 CPU·메모리 메트릭은 그대로 동작하지만
  `slurm_job_utilization_gpu`, `slurm_job_memory_usage_gpu`,
  `slurm_job_power_gpu`가 사라지고, 이 exporter를 도입한 이유인
  `SlurmJobGpuIdle` 알림도 절대 발생하지 않습니다.

여기서 말하는 DCGM은 exporter 자신의 데이터 소스이며, Algalon의
`dcgm-exporter`와는 별개입니다. 한 노드에서 둘은 함께 돌아갑니다.

## 타깃 등록하기

### Docker Compose

템플릿 두 개를 호스트 스택의 타깃 디렉터리로 복사합니다(파일 이름은
고정입니다. vmagent가 정확히 이 이름들을 감시합니다).

```bash
cd deploy/compose/host/targets
cp ../../../../monitoring/scrape/targets/slurm-targets.yml.example \
   slurm-targets.yml
cp ../../../../monitoring/scrape/targets/slurm-job-targets.yml.example \
   slurm-job-targets.yml
```

`slurm-targets.yml`에는 큐 exporter 하나만 들어가며 레이블이 필요 없습니다.
`slurm-job-targets.yml`에는 계산 노드마다 한 항목씩 들어가고, 모든 항목에
`node` 레이블이 **반드시** 있어야 합니다. 값은 같은 머신에 대해
`dcgm-targets.yml`, `node-targets.yml`에서 쓴 값과 동일해야 합니다.

```yaml
- targets:
    - 'gpu01.example.internal:9798'
  labels:
    node: gpu01
```

Slurm을 쓰지 않는다면 두 파일을 빈 리스트(`[]`)로 두거나 아예 만들지
않으면 됩니다. 타깃 파일 전체 설명은
[`deploy/compose/host/targets/README.md`](../../deploy/compose/host/targets/README.md)에
있습니다.

### Helm과 k3s

exporter가 클러스터 바깥에 있으면 `kubernetes_sd`로는 찾을 수 없으므로,
대신 values에 정적으로 나열합니다. (계산 노드가 클러스터 *멤버*라면
[다음 절](#클러스터-내부-jobexporter-daemonset)의 DaemonSet 경로를 쓰며
정적 목록이 필요 없습니다.) 아래 내용은 모두 기본값이 `false`인
`slurm.enabled`로 게이팅됩니다.

```yaml
slurm:
  enabled: true
  queueTargets:
    - "slurmctld.example.internal:9092"
  jobTargets:
    - {address: "gpu01.example.internal:9798", node: "gpu01"}
    - {address: "gpu02.example.internal:9798", node: "gpu02"}
```

`jobTargets`의 각 항목은 자신의 `node` 레이블을 달고 `static_configs`
블록으로 렌더링됩니다. Helm 경로에서 exporter 파드의 `node` 레이블은
`__meta_kubernetes_pod_node_name`에서 오므로, 여기에 적는 값은 임의의
호스트명이 아니라 **쿠버네티스 노드 이름**이어야 합니다. 그렇지 않으면
조인이 조용히 아무것도 매칭하지 못합니다. 차트 문서는
[`deploy/helm/algalon/`](../../deploy/helm/algalon/README.md)에 있습니다.

### 클러스터 내부 jobExporter (DaemonSet)

위의 `jobTargets`는 계산 노드가 클러스터 바깥에 있다고 가정합니다. 계산
노드가 클러스터 멤버라면, 정적으로 나열하는 대신
`slurm.jobExporter.enabled: true`로 slurm-job-exporter를 DaemonSet으로
실행하세요. 같은 노드 집합에 대해서는 `jobTargets`와 `jobExporter` 중
하나만 켭니다 — 둘 다 켜면 같은 잡을 이중으로 scrape하게 됩니다.

DaemonSet도 GPU별 메트릭을 읽으려면 DCGM 엔진이 필요하지만, 이번에는
자기 파드에 내장된 엔진이 아니라 호스트 쪽 엔진을 씁니다. 각 노드에는
이미 `:5555`에서 대기하는 호스트 쪽 `nv-hostengine`이 떠 있어야 하고,
exporter는 `hostNetwork`를 통해 그 엔진에 remote client로 붙습니다. 같은
노드에서 `dcgm-exporter` DaemonSet도 돌고 있다면, `dcgmExporter.extraArgs:
["-r", "localhost:5555"]`와 `dcgmExporter.hostNetwork: true`로 동일한
엔진을 가리키게 하세요 — 한 노드에서 두 개의 DCGM 엔진이 동시에
`DCGM_FI_PROF_*` 필드를 볼 수는 없으므로, `dcgm-exporter`와
slurm-job-exporter는 호스트 쪽 엔진 하나를 공유해야 합니다.

#### 대상 노드마다 필요한 선행 조건

위의 호스트 쪽 `nv-hostengine` 외에, DaemonSet 경로에는 정적 호스트 서비스
경로에는 없는 선행 조건이 두 가지 더 있습니다.

- **nvidia-container-toolkit, 그리고 클러스터가 런타임을 RuntimeClass로
  게이팅한다면 `nvidia` RuntimeClass.** 잡 단위 GPU 귀속은 DCGM만으로는
  할 수 없습니다. DCGM은 *이 GPU가 바쁘다*까지만 알려주고, GPU를 잡에
  대응시키는 일은 잡 자신의 cgroup 안에서 `nvidia-smi -L`을 실행해서
  이루어집니다. `nvidia-smi`는 nvidia 컨테이너 런타임이 컨테이너에
  주입해 주는 것이라 이미지에 일부러 넣지 않았습니다. 그 바이너리는
  호스트 드라이버와 버전이 맞아야 하기 때문입니다. 그래서 파드는
  `NVIDIA_VISIBLE_DEVICES=all`과 `NVIDIA_DRIVER_CAPABILITIES=utility`를
  선언하며, 해당 런타임이 노드 기본값이 아니라면
  `slurm.jobExporter.runtimeClassName: nvidia`도 함께 설정해야 합니다.
  toolkit이 없으면 파드는 뜨고 cgroup CPU·메모리도 그대로 보고하지만
  `slurm_job_*_gpu` 시계열은 전부 사라지고, 이 exporter의 존재 이유인
  `SlurmJobGpuIdle` 알림도 영영 발생하지 않습니다.
- **Slurm 사용자가 `/etc/passwd`로 해석 가능할 것.** exporter는
  `id --name --user <uid>`를 실행해 uid를 `user` 레이블로 바꾸는데,
  파드에는 호스트의 `/etc/passwd`가 읽기 전용으로 바인드 마운트될
  뿐입니다. 로컬 계정이 아니라 LDAP이나 SSSD로 Slurm 사용자를 해석하는
  사이트에서는 이 조회가 예외를 던지고 `user` 레이블만이 아니라 *수집
  전체*가 실패합니다. 컨테이너 안에서도 사용자가 보이게 하거나(예:
  호스트의 `/var/lib/sss`를 추가로 마운트해 파드 안에서 NSS 경로가 살아
  있게 함), 아니면 `jobTargets`로 exporter를 호스트의 systemd 서비스로
  두어 노드 자신의 NSS 스택을 쓰게 하세요. Algalon은 이를 완화하려고
  upstream 코드를 수정하지 않습니다.

cgroup v2 참고: 수집기는 그 probe를 돌리려고 잡마다 수명이 짧은
`gpu_probe` 자식 cgroup을 만듭니다. 그래서 `/sys/fs/cgroup` 마운트는
의도적으로 **쓰기 가능**합니다. 읽기 전용으로 마운트하면 GPU 잡이 도는
동안의 모든 수집이 실패합니다.

```yaml
slurm:
  jobExporter:
    enabled: true
    image: ghcr.io/appleparan/slurm-job-exporter:0.4.12
    port: 9798
    dcgmUpdateInterval: 10
    # 런타임이 RuntimeClass 뒤에 있으면 "nvidia". nvidia 런타임이 이미
    # 노드 기본값일 때만 비워 둡니다.
    runtimeClassName: nvidia
    nodeSelector: {}
    tolerations: []
    resources:
      requests: {cpu: 100m, memory: 128Mi}
```

이 포트는 **호스트** 포트입니다(`hostNetwork`에 더해 명시적인 `hostPort`).
따라서 노드에서 이미 `:9798`을 잡고 있는 것이 있다면 — 십중팔구 같은
exporter의 호스트 서비스 잔재입니다 — 파드가 스케줄되지 못하는 형태로
드러납니다.

`jobExporter`는 `slurm.jobExporter.enabled: true`만으로 렌더링됩니다.
위에서 설명한 정적 `queueTargets`/`jobTargets` scrape 잡만 게이팅하는
`slurm.enabled: true`는 필요하지 않습니다. 파드는 `algalon.io/scrape:
"true"`와 `algalon.io/job: slurm-job` 레이블을 달고 있으므로,
`algalon-pods` kubernetes_sd 잡이 `dcgm-exporter`나 `node-exporter`
파드를 가져오는 것과 같은 방식으로 이 파드도 가져갑니다 — scrape 설정을
바꿀 필요가 없습니다. `job`은 `algalon.io/job` 파드 레이블에서,
`node`는 `__meta_kubernetes_pod_node_name`에서 오는데, 이는 `jobTargets`가
정적 항목에 대해 손으로 붙이는 relabelling과 정확히 같습니다. 그래서
어느 경로든 결과 시계열은 동일한 `job="slurm-job"`과 `node` 레이블을
갖습니다.

레이블이 같다는 점 덕분에 rule과 대시보드가 두 경로 사이에서 그대로
통하지만, 이는 *레이블*에 대한 이야기일 뿐 커버리지에 대한 이야기가
아닙니다. 위의 모든 rule·대시보드·조인은 **파드가 실제로 만들어 내는
메트릭에 한해서** 변경 없이 적용됩니다. 위의 선행 조건 두 가지를 모두
갖추면 그것이 전부이지만, nvidia 런타임을 빠뜨리면 GPU에서 파생되는
절반 — Job Explorer의 GPU별 패널과 `SlurmJobGpuIdle` — 은 비어 있는 채로
남고 CPU·메모리 쪽 절반만 멀쩡해 보입니다.

## 무엇을 얻게 되나

### 알림

rule 그룹 하나, [`monitoring/rules/slurm.yml`](../../monitoring/rules/slurm.yml)이
추가되며 다른 그룹과 마찬가지로 30초마다 평가됩니다. 1~4번은 큐 exporter,
5번은 잡 exporter에서 나옵니다.

<!-- markdownlint-disable MD013 -->
| 알림 | 심각도 | 발생 조건 | 이유 |
| --- | --- | --- | --- |
| `SlurmNodeDown` | critical | 노드가 5분간 `down` | 쓸 수 없는 자원이고, drain과 달리 아무도 의도하지 않았습니다 |
| `SlurmNodeDrained` | warning | 노드가 10분간 `drain` | drain 자체는 정상입니다. 문제는 *지속되는* drain이 조용히 클러스터를 줄인다는 것 |
| `SlurmJobFailureSpike` | warning | 30분간 3개 초과의 잡이 `failed` 진입 | 불량 노드, 깨진 공유 파일시스템, 소진된 쿼터가 스케줄러 쪽에 남긴 메아리 |
| `SlurmQueueStalledWithIdleNodes` | warning | 노드가 idle인데 잡이 30분간 pending | 파티션/QOS/GRES 설정 오류. 용량 부족은 모양이 다릅니다(idle 노드가 *없는* 채로 pending) |
| `SlurmJobGpuIdle` | warning | 잡의 평균 GPU 사용률이 30분간 10% 미만 | 할당 낭비: 멀쩡한 GPU를 잡이 붙잡고 놀리는 상태 |
<!-- markdownlint-enable MD013 -->

노드 단위 잡 exporter를 도입한 근거가 바로 `SlurmJobGpuIdle`입니다. DCGM은
GPU가 놀고 있다는 것은 볼 수 있지만 누가 붙잡고 있는지는 전혀 모릅니다.
그 귀속 정보를 cgroup 레이블이 제공하므로, 알림은 `node`, `user`,
`slurmjobid`를 달고 Slack에 도착합니다. 운영자는 대시보드를 열지 않고도
소유자와 잡 ID를 바로 알 수 있습니다.

억제(inhibition)에 대한 주의: **노드 범위**의 critical만 같은 노드의
warning을 억제합니다. 이번 단계에서 Alertmanager inhibit rule의 소스 쪽에
`node!=""` 가드를 추가해 범위를 좁혔습니다. `equal` 아래에서 Alertmanager는
레이블이 없는 것끼리도 일치로 취급하기 때문에, 가드가 없으면 `node`
레이블이 없는 클러스터 전역 critical(예: `SlurmNodeDown`)이 `node` 없는
warning 전체 — 나머지 세 개의 Slurm warning과 `DcgmMetricsMissing`을 포함해
— 를 통째로 억제합니다. 이들은 서로 독립적인 신호이므로, 이제 `node`가 없는
critical은 의도적으로 아무것도 억제하지 않습니다.

### 대시보드

다른 대시보드와 마찬가지로 **Algalon** 폴더에 자동 프로비저닝되는 두 개가
추가됩니다.

- **Algalon / Slurm Queue** (`algalon-slurm-queue`) — 스케줄러 관점.
  pending·running 잡 수, down·drain 노드 수, 시간에 따른 상태별 잡 추이,
  노드 상태 타임라인(alloc / idle / drain / down), 파티션별 표.
- **Algalon / Slurm Job Explorer** (`algalon-slurm-jobs`) — `job_id`
  변수로 한 번에 한 잡씩. 소유자와 account, cgroup 메모리, 프로세스 수,
  GPU 수, GPU별 사용률·메모리·전력, 그리고 아래에서 설명하는 노드 조인
  패널들.

### 메트릭과 레이블

직접 쿼리를 작성하기 전에 알아 두면 좋은 몇 가지입니다.

- Slurm 잡 ID 레이블은 **`slurmjobid`**입니다(`jobid`도 `job_id`도
  아닙니다). `job`은 이미 scrape 잡 이름이 쓰고 있습니다. Algalon의 모든
  rule, 대시보드 변수, 조인이 정확히 이 이름을 씁니다.
- `slurm_job_power_gpu`의 단위는 **밀리와트(mW)** 입니다. 대시보드 패널은
  와트로 표시하려고 1000으로 나눕니다. 직접 쿼리를 짤 때도 똑같이 하세요.
- `slurm_job_memory_usage`는 바이트 단위이며, 모든 조인에서 "이 잡이 이
  노드에 있다"는 존재 확인용 메트릭으로 씁니다. CPU 전용 잡에도 존재하기
  때문입니다.
- `user`와 `account`는 cgroup에서 오므로, Slurm에 별도로 질의하지 않아도
  모든 잡 시계열에서 사용할 수 있습니다.

## `on(node)` 조인 계약

잡 시계열과 하드웨어 시계열은 공유 레이블 하나, `node`로 만납니다. 모든
`slurm-job` 타깃이 그 머신의 dcgm·node-exporter 타깃과 동일한 `node` 값을
달고 있기 때문에, 노드 단위 시계열을 특정 잡의 노드로 좁힐 수 있습니다.

```promql
avg by (node) (DCGM_FI_DEV_GPU_UTIL)
  and on(node)
  (count by (node) (slurm_job_memory_usage{slurmjobid="$job_id"}) > 0)
```

오른쪽은 존재 확인용입니다. 잡의 cgroup이 있는 노드마다 샘플 하나를
내놓고, `and on(node)`가 왼쪽에서 매칭되는 시계열만 남깁니다. Job
Explorer는 DCGM 사용률, NFS GETATTR 지연, 그리고 잡의 노드에서 발생 중인
알림 표에 이 방식을 씁니다.

**한계를 분명히 하자면**, 이들은 *노드* 단위 신호입니다. 잡이 노드를
독점할 때에만 잡의 신호로 읽을 수 있습니다. 노드를 공유하는 경우 DCGM
사용률에는 모든 사용자가 섞이고, 알림 표의 항목이 남의 잡 것일 수도
있습니다. 노드를 공유한다면 설계상 잡 단위인 cgroup 메트릭
(`slurm_job_utilization_gpu`, `slurm_job_memory_usage`,
`slurm_job_core_usage_total`)만 믿으세요.

조인 결과가 비어 있다면 `node` 레이블이 서로 다른 것입니다.
`up{job="slurm-job"}`과 `up{job="dcgm"}`을 비교해 보세요. 같은 머신인 것으로
충분하지 않고, 문자열이 완전히 같아야 합니다.

## 잡 로그 (선택)

메트릭은 잡이 뜨겁게 돌다가 멈췄다는 것까지만 알려 줍니다. 세 번째 epoch에서
CUDA OOM으로 죽었다는 사실은 알려 주지 않습니다. Algalon은 각 잡의 stdout
끝부분을 메트릭 옆에 함께 보관할 수 있고, 그러면 Job Explorer 한 화면에서 두
질문에 모두 답할 수 있습니다.

위의 exporter들과는 별개의 opt-in이며, 움직이는 부품은 세 개입니다.

```text
slurmctld  --EpilogSlurmctld-->  epilog-logpush.sh
                                        |
                                        | HTTP POST /insert/jsonline
                                        v
                                  VictoriaLogs  <---- Grafana 로그 패널
```

### 왜 tailer가 아니라 잡 종료 시점의 push인가

흔한 설계는 출력 디렉터리를 감시하다가 파일이 자라는 대로 따라 읽는 로그
에이전트입니다. GPU 클러스터에서 그 설계는 오히려 해롭습니다. 잡 출력은 공유
NFS 위에 있고, follower는 폴링할 때마다 그 트리를 glob하고 후보 파일마다 다시
stat해야 합니다. 학습 잡이 체크포인트를 읽고 있는 바로 그 파일러를 향해 NFS
`GETATTR` 연산을 끊임없이 흘려보내는 셈입니다.

Algalon의 `storage-nfs`와 `node-precursor` rule은 바로 그 NFS `GETATTR` 지연
상승에 알림을 겁니다. Lablup 리포트가 이를 체크포인트 I/O 문제의 조기 지표로
지목하기 때문입니다. tailer를 두면 자기 알림이 감시하는 그 메트릭을 자기가
끌어올리게 됩니다. 지키려고 배포한 신호를 수집기가 오염시키는 것이고, 결국
운영자는 그 알림을 무시하는 법을 배우게 됩니다.

그래서 파일시스템을 감시하는 것은 아무것도 없습니다. 로그는 잡이 이미 끝난
뒤에 한 번만 읽고, 마지막 10 MiB만 전송합니다.

### 저장소 켜기

VictoriaLogs는 두 배포 경로 모두에서 기본 비활성입니다.

Docker Compose — `logs` 프로파일:

```bash
cd deploy/compose/host
docker compose --profile logs up -d
```

`VLOGS_PORT`(기본 `9428`)와 `VLOGS_RETENTION_MONTHS`(기본 `3`,
`VM_RETENTION_MONTHS`와 동일)는 `.env.example`에 있습니다.

Helm:

```bash
helm upgrade --install algalon deploy/helm/algalon \
  --set victorialogs.enabled=true
```

Grafana에 관해 두 가지. VictoriaLogs 데이터소스 플러그인은 저장소를 켰든
껐든 **항상** 설치됩니다(`GF_INSTALL_PLUGINS`). 저장소를 켜는 즉시 아래 패널이
그려지게 하기 위해서입니다. Grafana는 첫 기동 때 이 플러그인을 내려받으므로 그
컨테이너에 한 번은 외부 인터넷이 필요합니다. 폐쇄망 호스트라면
`grafana.installPlugins`를 `[]`로 두고 플러그인을 구운 파생 이미지를 쓰세요.
그리고 compose 스택에서는 데이터소스 자체가 조건 없이 프로비저닝되므로,
프로파일을 내려 둔 상태에서는 헬스 체크에 실패하는 `VictoriaLogs`
데이터소스가 보입니다. 정상입니다. 값으로 분기할 수 있는 Helm 차트는
`victorialogs.enabled`일 때만 프로비저닝합니다.

### epilog 훅 설치하기

`monitoring/slurm/epilog-logpush.sh`를 slurmctld 호스트가 실행할 수 있는
위치에 두고, `slurm.conf`에 **`EpilogSlurmctld`**로 등록합니다.

```conf
EpilogSlurmctld=/etc/slurm/epilog-logpush.sh
```

`Epilog`가 아니라 `EpilogSlurmctld`라는 점이 핵심입니다. `Epilog`는 할당된
모든 노드에서 실행되므로 64노드 잡이라면 같은 공유 출력 파일을 64번 밀어
올리게 됩니다. `EpilogSlurmctld`는 **잡당 한 번, 컨트롤러에서** `SlurmUser`
권한으로 실행됩니다. 스크립트에 중복 제거 로직이 없는 이유는 훅 선택만으로
중복 제거가 불필요해지기 때문입니다.

대신 컨트롤러가 잡의 `StdOut` 경로를 읽을 수 있어야 합니다. 보통은 사용자가
쓰는 것과 같은 공유 파일시스템을 컨트롤러도 마운트해야 한다는 뜻입니다. 읽을
수 없으면 스크립트는 조용히 종료하고 로그도 남지 않습니다. 에러가 아닙니다.

저장소 주소는 `/etc/default/slurmctld`나 유닛의 `Environment=`로 넘깁니다.

```bash
VLOGS_URL=http://algalon-host.example.internal:9428
ALGALON_LOG_MAX_BYTES=10485760   # 잡당 출력 끝부분 10 MiB
CURL_TIMEOUT=10
```

스크립트는 Slurm의 `scontrol` 외에 컨트롤러의 `curl`과 `jq`를 씁니다. 임의의
로그 바이트를 올바른 JSON으로 바꾸는 일을 `jq`가 맡습니다. 직접 짠 이스케이프는
정확성 함정이고, 이 스크립트는 그 길을 택하지 않습니다.

**이 스크립트는 잡을 실패시킬 수 없습니다.** `EpilogSlurmctld`가 0이 아닌 값을
반환하면 slurmctld가 노드를 drain합니다. 그래서 `jq`가 없든, 출력 파일을 읽을
수 없든, VictoriaLogs가 죽어 있든 스크립트의 모든 경로는 stderr(slurmctld
로그)에 한 줄을 남기고 `exit 0`으로 끝납니다. 이 성질은 전달되는 어떤 로그보다
중요하므로, 스크립트를 고칠 일이 있다면 반드시 유지해야 하는 제약으로
취급하세요.

### 무엇이 보이나

**Algalon / Slurm Job Explorer** 대시보드 맨 아래에 전체 너비 **Job output
(stdout)** 패널이 추가됩니다. `logs_datasource` 변수에 바인딩되며 다음 LogsQL
스트림 필터로 질의합니다.

```logsql
{slurmjobid="$job_id"}
```

`slurmjobid`와 `user`는 ingest 시점의 스트림 필드이고, 그래서 이 필터가 전체
스캔이 아니라 스트림 조회가 됩니다. 각 줄에는 `jobname`, `exitcode`,
`nodelist`도 일반 필드로 함께 실리므로 Explore에서
`{slurmjobid="123"} | exitcode:!="0:0"` 같은 질의도 그대로 동작합니다.

다음 세 가지 평범한 상황에서 패널은 고장 난 것이 아니라 비어 있습니다. 잡이
아직 실행 중일 때(출력은 실시간이 아니라 종료 시점에 전송됩니다), 훅을 설치하기
전에 끝난 잡일 때, 그리고 저장소가 꺼져 있을 때입니다.

## 함께 보기

- [아키텍처](architecture.md) — 이 타깃들이 흘러드는 파이프라인
- [배포](deployment.md) — 배포 방식 선택
