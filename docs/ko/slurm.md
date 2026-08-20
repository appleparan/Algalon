# Slurm 연동

[English](../slurm.md) | **한국어**

Algalon은 하드웨어 관점의 지표와 함께 Slurm 스케줄러가 보는 클러스터를 같이
읽을 수 있습니다. 어떤 잡이 큐에 쌓여 있는지, 스케줄러가 어떤 노드를
포기했는지, 그리고 잡 단위로 누가 그 잡의 주인이며 잡이 붙잡고 있는 GPU가
실제로 일을 하고 있는지까지요. 이 연동은 완전히 opt-in입니다. scrape 잡
두 개가 추가될 뿐이고, 타깃을 등록하지 않으면 시계열도, 알림도 생기지
않으며 대시보드 세 개가 비어 있을 뿐입니다.

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

다른 대시보드와 마찬가지로 **Algalon** 폴더에 자동 프로비저닝되는 세 개가
추가됩니다.

- **Algalon / Slurm Queue** (`algalon-slurm-queue`) — 스케줄러 관점.
  pending·running 잡 수, down·drain 노드 수, 시간에 따른 상태별 잡 추이,
  노드 상태 타임라인(alloc / idle / drain / down), 파티션별 표.
- **Algalon / Slurm Job Explorer** (`algalon-slurm-jobs`) — `job_id`
  변수로 한 번에 한 잡씩. 소유자와 account, cgroup 메모리, 프로세스 수,
  GPU 수, GPU별 사용률·메모리·전력, 그리고 아래에서 설명하는 노드 조인
  패널들.
- **Algalon / Scheduler Analytics** (`algalon-scheduler`) — 운영용이 아니라
  정책용인 7일 관점. [스케줄러 분석](#스케줄러-분석-선택)에서 설명하는 선택적
  accounting collector가 데이터를 채웁니다. collector 없이 동작하는 패널은
  pending 대 idle 패널 하나뿐입니다.

Job Explorer에는 스케줄러가 답할 수 없는 질문 — *이 잡이 붙잡은 GPU가 실제로
계산을 하고 있는가* — 에 답하는 패널 두 개도 있습니다. 운영자가 아니라 잡
소유자를 향해 쓰였습니다. 이 패널들이 속한 4계층 체계는
[GPU 활용도 품질](architecture.md#gpu-활용도-품질)을 보세요.

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

## 스케줄러 분석 (선택)

위의 두 exporter는 *스케줄러가 지금 무엇을 하고 있는가*에 답합니다. 하지만
파티션 구성이 적절한지는 둘 다 알려 주지 못합니다. 둘 다 게이지를 내보내기
때문입니다. 한 시간만 지나면 여섯 시간을 큐에서 기다린 잡과 바로 시작한 잡을
구분할 수 없습니다. 정책 검토에서 실제로 던지는 질문 — 이 파티션의 시간 제한을
올려야 하나, 지나치게 오래 기다리는 사람이 있나, 어느 account가 클러스터를
소모하고 있나 — 은 모두 잡 단위 이력을 필요로 하고, 그 이력은 Slurm 자신의
accounting 데이터베이스에 있습니다.

`monitoring/slurm/sacct-textfile.sh`가 그것을 읽습니다. 이 스크립트는
컨트롤러에서 cron이나 systemd 타이머로 실행되어, 종료된 잡의 윈도우를 누적
카운터에 접어 넣고 node_exporter가 노출할 위치에 씁니다. epilog 훅과
마찬가지로 Algalon은 스크립트와 그것을 읽는 rule·대시보드를 제공할 뿐,
배포하거나 스케줄링하지는 않습니다.

이것은 세 번째의, 별개인 opt-in입니다. 위의 두 exporter 중 어느 것도 필요하지
않지만, 큐 exporter가 함께 돌고 있으면 Scheduler Analytics 대시보드가 더
쓸모 있습니다.

### 왜 exporter가 아니라 textfile collector인가

`sacct`는 값싼 읽기가 아니라 데이터베이스 질의입니다. exporter로 만들면 30초
scrape마다 slurmdbd 왕복이 동기적으로 끼어들고, accounting 데이터베이스가
느려지는 순간 그것이 exporter 장애로 보이게 됩니다. `.prom` 파일을 쓰는 cron
잡은 둘을 분리합니다. node_exporter는 마지막으로 성공한 스냅샷을 메모리
속도로 서빙하고, 멈춘 `sacct`는 scrape를 깨는 대신 데이터를 늦출 뿐입니다.

그 대신 collector가 자기 상태를 직접 들고 있어야 합니다. `.prom` 파일은
스크립트가 소유한 상태 파일을 그대로 렌더링한 결과이며, 카운터가 실행 간에도
재부팅 후에도 단조 증가하는 이유가 바로 이것입니다
([상태, 리셋, 재시작](#상태-리셋-재시작) 참고).

### 무엇을 내보내고, 각 메트릭이 무엇을 결정하나

<!-- markdownlint-disable MD013 -->
| 메트릭 | 타입 | 레이블 | 이것으로 내리는 결정 |
| --- | --- | --- | --- |
| `slurm_jobs_completed_total` | counter | `state`, `partition`, `account` | 결과가 어디에 몰리는가. `timeout` 비중이 계속 오른다면 walltime 제한이 실제 작업량보다 낮게 잡힌 것입니다. `account` 분해는 [실패의 확산](#실패-횟수와-실패-분포)을 보이게 하는 축입니다 |
| `slurm_job_node_failures_total` | counter | `node` | **어느 노드가 아픈가.** FAILED와 NODE_FAIL 잡을 그 잡이 점유한 모든 노드에 한 번씩 계상합니다. Slurm의 압축 노드리스트는 펼쳐서 씁니다. 평평한 것이 정상이고, 실패를 쌓아 두는 노드는 drain 후보입니다 |
| `slurm_job_wait_seconds` | histogram | `partition` | **파티션과 QOS 제한.** p50은 보통 사용자가 겪는 것을, p90은 누가 굶고 있는지를 알려 줍니다. p50이 평평한데 p90이 올라간다면 제약은 용량이 아니라 제한값입니다 |
| `slurm_job_runtime_seconds` | histogram | `partition` | **파티션 구성.** p90 실행 시간이 몇 분인 파티션에 며칠짜리 최대 시간은 필요 없고, p50이 이미 제한값 근처인 파티션은 계속 timeout을 만들어 냅니다 |
| `slurm_job_timelimit_used_ratio` | histogram | `partition` | **백필 효율.** `Elapsed / Timelimit`입니다. 낮은 쪽에 몰린 분포는 부풀린 walltime이고, 스케줄러는 너무 짧다고 판단한 틈에 잡을 백필하지 못하므로 과다 요청은 꽉 찬 큐 앞에서 노드를 놀립니다. 1.0을 넘는 분포는 제한이 죽인 잡들입니다 |
| `slurm_job_gpu_seconds_total` | counter | `partition`, `account` | **Fairshare.** account별 할당 GPU 초. 의도한 몫보다 훨씬 위에 있는 account는 하드웨어를 더 사자는 근거가 아니라 fairshare나 QOS를 바꾸자는 근거입니다 |
| `slurm_sacct_collector_last_run_timestamp_seconds` | gauge | — | 타이머가 아직 돌고 있는지. 값이 오래되었다면 클러스터가 조용한 것이 아니라 cron 잡이 죽은 것입니다 |
| `slurm_sacct_collector_errors_total` | counter | — | 파서가 읽지 못한 행. 값이 오르면 `sacct` 출력이 스크립트의 기대와 어긋난 것입니다 — [여전히 놀랄 수 있는 것들](#여전히-놀랄-수-있는-것들)을 보세요 |
<!-- markdownlint-enable MD013 -->

`slurm_job_gpu_seconds_total`은 **사용된** GPU 초가 아니라 **할당된** GPU
초를 셉니다. 놀고 있는 GPU를 붙잡은 잡도 전부 계산됩니다. 그 옆에
`SlurmJobGpuIdle`이 존재하는 이유가 정확히 이것입니다. 한쪽은 무엇이
나갔는지를, 다른 한쪽은 그것이 일을 했는지를 말합니다.

wait 히스토그램은 recording rule 하나로도 이어집니다.
[`monitoring/rules/slo.yml`](../../monitoring/rules/slo.yml)의
`algalon:sli:job_wait_ok_1h`로, 제출 후 30분 안에 시작한 잡의 비율입니다.
이 비율의 30일 버전은 **SLO Overview**의 stat 타일이며, 시간당 rule을
평균 내지 않고 원본 히스토그램에서 다시 계산합니다. 그래야 바쁜 오후가
한산한 밤보다 더 무겁게 반영됩니다. 알림은 없습니다 —
[실패 횟수와 실패 분포](#실패-횟수와-실패-분포)를 보세요.

### 컨트롤러에 설치하기

컨트롤러가 실행할 수 있는 위치에 스크립트를 두고 상태 디렉터리를 만듭니다.

```bash
install -m 0755 monitoring/slurm/sacct-textfile.sh \
  /usr/local/bin/algalon-sacct-textfile
install -d -m 0755 /var/lib/algalon-sacct
install -d -m 0755 /var/lib/node_exporter/textfile
```

선택적인 환경 변수 세 개를 읽습니다.

```bash
SACCT_STATE_DIR=/var/lib/algalon-sacct
TEXTFILE_DIR=/var/lib/node_exporter/textfile
ALGALON_SACCT_LOOKBACK_S=3600   # 최초 실행에만 사용, 이후에는 이어서 실행
```

`ALGALON_SACCT_LOOKBACK_S`는 상태가 아직 없을 때 **한 번만** 쓰입니다. 이후
실행은 직전 윈도우의 끝에서 이어지므로 아래의 주기와 이 값은 서로 독립적입니다.
cron 주기를 바꿔도 구멍이 생기거나 중복 집계되지 않습니다.

`sacct`가 응답해 줄 사용자로 실행하세요. 스크립트는 `--allusers`를 넘기는데,
이는 호출자가 Slurm operator나 admin이어야 한다는 뜻입니다. 그 권한이 없으면
`sacct`는 호출자 자신의 잡만 조용히 보고하고, collector는 0에 가까운 카운터를
아무렇지 않게 게시하게 됩니다.

cron, 5분마다. 위의 두 경로는 스크립트의 기본값이므로, 위치를 옮기지 않았다면
아무것도 넘길 필요가 없습니다.

```cron
*/5 * * * * root /usr/local/bin/algalon-sacct-textfile
```

또는 systemd 타이머. 문제가 생겼을 때 들여다보기가 더 쉽습니다.
`/etc/systemd/system/algalon-sacct.service`:

```ini
[Unit]
Description=Algalon sacct textfile collector
After=slurmdbd.service

[Service]
Type=oneshot
User=root
Environment=SACCT_STATE_DIR=/var/lib/algalon-sacct
Environment=TEXTFILE_DIR=/var/lib/node_exporter/textfile
ExecStart=/usr/local/bin/algalon-sacct-textfile
```

`/etc/systemd/system/algalon-sacct.timer`:

```ini
[Unit]
Description=Run the Algalon sacct textfile collector every 5 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
AccuracySec=30s

[Install]
WantedBy=timers.target
```

```bash
systemctl daemon-reload
systemctl enable --now algalon-sacct.timer
```

epilog와 달리 이 스크립트는 **실패하면 0이 아닌 값으로 종료합니다.** 여기서는
노드가 drain될 위험이 없고, 조용히 실패하는 cron 잡은 아무도 알아채지 못하는
cron 잡이기 때문입니다. `systemctl status algalon-sacct.service`나 cron 메일이
무엇이 잘못됐는지 보여 줍니다.

### 파일을 노출하기

`.prom` 파일은 같은 호스트의 node_exporter가 읽어야만 쓸모가 있습니다. 즉
컨트롤러에도 다음 옵션으로 기동한 node_exporter가 필요합니다.

```bash
node_exporter --collector.textfile.directory=/var/lib/node_exporter/textfile
```

그리고 그것을 향한 scrape 타깃이 필요합니다. Compose 경로에서는 다른 머신과
똑같이 컨트롤러를 `deploy/compose/host/targets/node-targets.yml`에 추가하면
됩니다.

컨트롤러가 클러스터 노드이고 Algalon의 node-exporter DaemonSet이 이미 돌고
있는 Helm 경로에서는, exporter를 하나 더 띄우는 대신 차트의
`nodeExporter.textfileDirectory`를 호스트 디렉터리로 설정하세요.

```yaml
nodeExporter:
  textfileDirectory: /var/lib/node_exporter/textfile
```

그러면 DaemonSet이 해당 호스트 경로를 같은 위치에 읽기 전용으로 마운트하고
textfile collector를 켭니다. 기본값이 비어 있고, 그래서 opt-in하지 않은
사용자에게는 collector가 꺼진 채로 남습니다. 이 값은 DaemonSet이 덮는 *모든*
노드에 적용된다는 점에 유의하세요. `.prom` 파일이 없는 노드는 아무것도
기여하지 않을 뿐입니다.

컨트롤러가 Kubernetes 노드가 아니라면 그 호스트에 node_exporter를 두고
`nodeExporter.staticTargets`에 등록하세요.

### 상태, 리셋, 재시작

`$SACCT_STATE_DIR/state`에는 마지막으로 처리한 윈도우의 끝과 모든 누적
카운터·버킷이 들어 있습니다. 알아 둘 만한 결과가 셋 있습니다.

- **카운터는 재부팅을 견딥니다.** 시간 윈도우에서 다시 계산하는 값이 하나도
  없으므로 컨트롤러를 재시작해도 카운터는 초기화되지 않습니다. 다음 실행이
  직전 실행이 멈춘 지점에서 이어갈 뿐입니다.
- **상태 디렉터리를 지우면 전부 0으로 리셋됩니다.** 그것은 평범한 카운터
  리셋이고 `increase()`와 `rate()`가 알아서 처리합니다. 잃는 것은 이력이지
  정확성이 아닙니다. rule과 대시보드의 모든 질의가 그 함수들로 쓰인 이유가
  바로 이것입니다.
- **실패한 실행은 잡을 잃지 않습니다.** 윈도우의 모든 잡을 접어 넣은 뒤에야
  윈도우 끝이 전진하므로, 중단된 실행은 다음 실행이 같은 잡을 다시 조회하게
  만듭니다. 겹치는 구간은 각 잡의 종료 시각으로 중복 제거되므로 다시
  조회해도 두 번 세지 않습니다.

`.prom` 파일은 임시 파일에 쓴 뒤 rename하므로 node_exporter가 절반만 쓰인
exposition을 읽는 일은 없습니다. 이전 스냅샷이거나 새 스냅샷이거나 둘 중
하나만 보입니다.

### 카디널리티

레이블은 `partition`(클러스터당 몇 개), `account`(수십 개), 그리고
히스토그램 자신의 `le`뿐입니다. 많아야 수백 개의 시계열이고, 클러스터
사용량에 따라 늘어나지 않습니다.

`user`는 **의도적으로** 레이블이 아닙니다. 사용자 수는 상한 없이 늘어나고,
사용자 한 명마다 히스토그램 세 개가 곱해집니다. 이 collector를 카디널리티
문제로 만들 유일한 차원이 바로 이 collector가 거부하는 차원입니다. 사용자별
귀속은 시계열이 아니라 `sacct` 질의의 일입니다. (잡 exporter는 `user`를
달고 있지만, 그것은 지금 실행 중인 잡에만 해당하는 유계 집합입니다.)

### 실패 횟수와 실패 분포

`slurm_jobs_completed_total` 위에 얹고 싶어지는 가장 뻔한 것이 소진율
알림이 달린 성공률이고, Algalon은 의도적으로 그것을 만들지 않았습니다.

공용 연구 클러스터에서 `FAILED` 잡의 대부분은 사용자 실수입니다. 배치
스크립트의 오타, 사용자가 고른 batch size로 인한 OOM, 잘못된 module load.
간헐적인 실패 하나든, 한 사용자가 연달아 마흔 번 실패하든 마찬가지입니다.
두 번째는 장애가 아니라 누군가 디버깅 중인 것입니다. 그 비율로 운영자를
호출하는 것은 그가 고칠 수 없는 실수로 그를 호출하는 것이고, 대응할 수 없는
호출을 받은 운영자는 같은 출처의 모든 호출을 무시하는 법을 배웁니다 — 노드에
불이 났다는 호출까지 포함해서요. 비용은 낭비된 알림 하나가 아니라 거기에
쓰인 신뢰입니다.

이 논증은 빈틈이 없지만, **총량**에 대해서만 그렇습니다. 사용자 실수로
설명되지 않는 것은 그 실패들의 *분포* 변화이고, 축은 둘입니다.

**집중 — 한 노드가 실패를 불균형하게 끌어모으는 경우.** 노드를 고르는 것은
사용자가 아니라 스케줄러이므로 실수는 클러스터 전체에 대체로 고르게
떨어집니다. 어느 노드가 실패를 쌓기 시작했다면 그 노드에 유독 운 없는 사람이
몰린 것이 아니라 노드가 고장 난 것입니다. 죽어 가는 GPU, 잘못된 드라이버,
가득 찬 로컬 디스크, 부하에서 패킷을 흘리는 NIC. 이것은 drain 후보이고, 바로
운영자가 손댈 수 있는 대상입니다. 그래서
`slurm_job_node_failures_total{node}`과 `SlurmNodeFailureConcentration`이
있습니다. 이 rule은 절대 하한과 과반 점유를 모두 요구하므로, 평범한 이탈이
우연히 한 노드에 몰린 정도로는 울리지 않습니다.

`node` 레이블은 Algalon의 다른 모든 `node` 레이블과 같은 값을 갖도록
의도적으로 맞춰 두었습니다([`on(node)` 조인 계약](#onnode-조인-계약) 참고).
두 가지가 따라옵니다. 의심스러운 노드를 Node Health와 DCGM에서 곧바로 찾아
하드웨어 증거를 대조할 수 있고, Alertmanager의 억제 규칙 — 노드 범위의
critical은 같은 노드의 warning을 억제합니다 — 이 `GpuXidFellOffBus` 같은
critical이 이미 원인을 지목했을 때 이 집중 warning을 자동으로 잠재웁니다.
그 실패들은 그 critical의 증상이지 두 번째 장애가 아닙니다.

**확산 — 여러 account에서 동시에 실패가 나는 경우.** 한 사용자의 실수는
구조적으로 그 사용자의 account 안에 갇힙니다. 서로 무관한 세 팀을 같은 30분
안에 실패시킬 수는 없습니다. 공유 인프라는 할 수 있습니다. 사라진
파일시스템, 아픈 slurmctld, 만료된 자격 증명, 잘못된 module 업데이트. 그래서
`account` 레이블과 `SlurmFailureSpreadAcrossAccounts`가 있습니다. 이 rule은
account 수와 실제 볼륨을 모두 요구합니다. 세 account가 각각 한 잡씩 실패한
것은 한산한 오후일 뿐이기 때문입니다.

추론이 아예 필요 없는 경우도 하나 있습니다. `SlurmNodeFailJobs`는 Slurm
자신의 `NODE_FAIL` 판정에 반응합니다. 어떤 사용자도 잡을 그 상태로 만들 수
없으므로, 정의상 사용자 실수일 수가 없습니다.

네 신호 모두 `action: investigate`가 붙은 warning이고, 다른 스케줄러 알림
옆의 `monitoring/rules/slurm.yml`에 함께 있으며, collector가 없는
클러스터에서는 전부 침묵합니다.

한 줄로 줄이면 이렇습니다. **실패 횟수는 사용자를 재고, 실패 분포는
클러스터를 잽니다.**

### 여전히 놀랄 수 있는 것들

- **Accounting 지연.** 윈도우는 "지금"에서 끝나므로, 방금 끝났지만 아직
  slurmdbd에 커밋되지 않은 잡은 이번 윈도우에도 다음 윈도우에도 들어오지
  않습니다. 바쁜 클러스터에서 실행당 몇 개 수준입니다. 신경 쓰인다면 윈도우가
  아니라 실행 주기를 넓히세요.
- **타입이 붙은 GRES.** GPU 수는 `AllocTRES`의 타입 없는 `gres/gpu=N`
  토큰에서 옵니다. Slurm은 타입이 붙은 항목(`gres/gpu:a100=2`)과 함께 이
  토큰도 내보내므로 타입 요청도 한 번만 세어집니다. 다만 타입 없는 토큰을
  없앤 사이트에서는 GPU 초가 0으로 보입니다.
- **시작조차 하지 못한 잡.** pending 상태에서 `CANCELLED`된 잡에는 시작
  시각이 없습니다. 이런 잡은 `slurm_jobs_completed_total`에는 세어지고 세
  히스토그램 모두에서는 빠집니다. 실행된 적 없는 잡의 대기 시간을 0으로
  치면 모든 분위수가 바닥으로 끌려가기 때문입니다.
- **`UNLIMITED`과 `Partition_Limit` walltime**에는 사용 비율이 없으므로
  `slurm_job_timelimit_used_ratio`에서 아예 빠집니다.
- **노드 이름이 `node` 레이블과 일치해야 합니다.**
  `slurm_job_node_failures_total`의 노드 이름은 Slurm 자신의 노드리스트에서
  옵니다. scrape 타깃이 같은 머신에 다른 이름을 붙이고 있다면 이 실패
  카운터는 DCGM이나 node-exporter와 맞물리지 않습니다.
  slurm-job-exporter 타깃에 적용되는 것과 같은 주의사항이고, 해결책도
  같습니다. 레이블 값이 완전히 같은 문자열이어야 합니다.
- **배열 잡과 이종(heterogeneous) 잡**은 할당 단위(`--allocations`)로
  세어집니다. 태스크 1000개짜리 배열 잡은 태스크마다 한 행씩 1000행이 되고,
  배열 전체를 나타내는 행은 따로 없습니다.

## 함께 보기

- [아키텍처](architecture.md) — 이 타깃들이 흘러드는 파이프라인
- [배포](deployment.md) — 배포 방식 선택
