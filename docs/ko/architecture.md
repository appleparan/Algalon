# 아키텍처

[English](../architecture.md) | **한국어**

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../images/architecture-dark.svg">
  <img alt="Algalon 아키텍처" src="../images/architecture.svg">
</picture>

모든 GPU 노드는 소수의 exporter만 실행하고, 중앙 호스트가 저장·평가·알림
파이프라인을 담당합니다. 워커가 데이터를 push하는 일은 없습니다. 중앙
vmagent가 30초마다 scrape하기 때문에, 워커가 할 일은 exporter를 계속 열어
두는 것뿐입니다.

## 구성 요소

| 구성 요소 | 역할 |
| --- | --- |
| dcgm-exporter | GPU 텔레메트리: XID 에러, ECC 및 row-remap 카운터, 온도, 전력, throttling |
| node-exporter | OS 텔레메트리: 인터럽트, 실행 가능 프로세스, page-out, NFS `mountstats` |
| all-smi *(선택)* | 크로스 플랫폼 가속기 및 프로세스 단위 뷰 |
| vmagent | exporter를 scrape해 VictoriaMetrics로 remote-write |
| VictoriaMetrics | 시계열 저장소 |
| VictoriaLogs *(선택)* | 잡 stdout. epilog가 잡 종료 시 한 번 push |
| vmalert | rule 그룹을 30초마다 평가하고 recording rule을 다시 기록 |
| Alertmanager | 알림을 라우팅·그룹핑·억제하고 Slack으로 전달 |
| Grafana | 자동 프로비저닝되는 열 개 대시보드 |

VictoriaLogs는 아무도 scrape하지 않는 유일한 구성 요소입니다. Slurm
컨트롤러에서 `EpilogSlurmctld`로 도는 `monitoring/slurm/epilog-logpush.sh`가
이 저장소에 씁니다. 두 배포 경로 모두에서 명시적으로 켜기 전까지는 꺼져
있습니다(compose `logs` 프로파일, 또는 차트의 `victorialogs.enabled`).
[잡 로그](slurm.md#잡-로그-선택)를 보세요.

컨트롤러와 계산 노드 쪽에는 선택적인 Slurm 관련 구성 요소 세 가지가 붙습니다.
각각이 별개의 opt-in이고 어느 것도 Algalon이 배포하지 않습니다. exporter 두
개(`prometheus-slurm-exporter`, `slurm-job-exporter`), 위의 epilog 로그
push, 그리고 `monitoring/slurm/sacct-textfile.sh` — Slurm accounting을
node_exporter textfile로 바꿔 Scheduler Analytics 대시보드에 공급하는 cron
또는 타이머 잡입니다. [Slurm 통합](slurm.md)을 보세요.

rule, 대시보드, scrape 설정, Alertmanager 정책, DCGM 카운터 세트의 단일
진실 공급원은 `monitoring/` 디렉터리입니다. Docker Compose는 이 디렉터리를
bind-mount하고 Helm은 ConfigMap으로 패키징합니다. `deploy/` 아래로 복사되는
파일은 하나도 없습니다.

## 일곱 개의 핵심 rule 그룹

`monitoring/rules/`의 각 그룹은 Lablup 리포트의 분석 결과 하나씩을 구현하며,
모든 rule에는 근거가 된 절·표·그림 번호가 인라인 인용으로 달려 있습니다.

### `gpu-xid` — XID 분류

리포트의 Table 3은 NVIDIA XID 에러 코드를 실제로 필요한 복구 조치에
매핑하는데, Algalon의 severity는 이 매핑을 그대로 따릅니다. XID 31/43/94는
애플리케이션 재시작이 필요하다는 뜻이라 warning, 119/145/149는 GPU 리셋이
필요하므로 critical, 79 — GPU가 버스에서 떨어져 나간 경우 — 는 노드
리부팅이 필요하므로 critical입니다. 분류되지 않은 0이 아닌 XID는 별도의
포괄 알림으로 처리합니다.

### `gpu-ecc` — 메모리 열화

row-remap 카운터는 GPU에 누적된 영구 손상 기록입니다. 이 그룹은 눈에 띄는
알림(uncorrectable remap, `ROW_REMAP_FAILURE`, pending remap, double-bit
ECC) 외에도 24시간 동안의 correctable remap *증가 추세*를 함께 감시합니다.
리포트의 gpu124 사례에서 해당 GPU는 XID 에러가 단 한 번도 없는 상태로 55일
동안 correctable remap을 254개 누적한 뒤 호스트에서 아예 사라졌기
때문입니다.

### `gpu-health` — 발열과 throttling

GPU 다이와 HBM의 온도 구간, 그리고 지속적인 하드웨어 throttling을 다룹니다
(리포트 Table 8). throttle rule은 무해한 원인(idle, application clock,
software power cap)을 마스킹하고 실제 성능 저하를 뜻하는 비트에서만
발생합니다. 리포트가 완전한 장애보다 잡아내기 어렵다고 지적한 "fail-slow"
유형이 바로 이것입니다.

### `node-precursor` — 조기 경보 신호

XID 에러는 사후 부검에 가깝습니다. 로그에 남는 시점이면 GPU는 이미 멈춘
뒤입니다. 리포트(§4.1.2, Figs 2–3)는 장애가 표면화되기 *전에* OS 레벨
메트릭이 먼저 움직인다는 것을 보여주며, 그래서 이 그룹은 각 노드를 클러스터
중앙값과 비교합니다. 인터럽트 발생률 급감, 실행 가능 프로세스 수 급감,
page-out 급증이 대상입니다. 셋 모두 warning 전용이고 최소 세 대 이상의
노드가 살아 있을 때만 동작합니다. 리포트의 finding F1이 정확히 "지배적인
단일 전조 신호는 존재하지 않는다"이므로, 이 신호들은 호출을 울릴 근거가
아니라 보조 근거로 다뤄야 합니다.

### `storage-nfs` — 체크포인트 I/O

recording rule이 NFS 처리량을 기준으로 학습 루프를 save/load 구간으로
분류합니다(save는 클러스터 전체에서 20 GB/s를 넘는 쓰기 폭주, load는 GPU
사용률이 낮은 상태로 지속되는 읽기). 알림은 NFS/RPC 큐잉을 겨냥합니다.
리포트 §4.2.5에서 WRITE 지연의 93.1 %가 서버 응답 시간이 아니라 클라이언트
측 큐 대기 시간이었기 때문입니다. 이 그룹 전체는 node-exporter의
`--collector.mountstats`를 필요로 합니다.

### `slo` — 서비스 수준 지표

다른 그룹들이 *무엇이 고장났는가*에 답한다면, 이 그룹은 *클러스터가
사용자에게 제대로 서비스하고 있는가*에 답합니다. Google SRE golden
signals 계층의 최상단에 있는 증상(symptom) 레이어이며, 알림이 하나도 없는
유일한 그룹입니다. 네 개의 recording rule이 순간값 0–1 비율을
`algalon:sli:*`로 기록합니다. exporter 가용성(`avg(up)`, Algalon 자신의
SLI), Slurm 노드 가용성(DOWN과 DRAIN 모두 사용 불가로 계산), GPU
건전성(92 °C 미만이면서 *동시에* 하드웨어 throttling이 없는 상태), NFS
지연(활성 `(instance, operation)` 경로가 100 ms/op 예산 안에 있는지, 유휴
파일시스템은 정상으로 계산)입니다. 다섯 번째 rule은 최근 한 시간 동안 새로
실패한 잡 수를 기록하는데, 큐 exporter가 게이지만 노출하기 때문에 비율이
아니라 개수입니다. 정확한 성공 비율은 sacct 수집기를 기다립니다.

임계값은 알림 그룹에서 그대로 재사용합니다. 92 °C는 `GpuTempCritical`,
비트마스크 ≥ 8은 `GpuClocksThrottled`, 100 ms/op은 `NfsOperationSlow`이며,
덕분에 SLI와 호출이 "비정상"의 정의를 두고 어긋날 일이 없습니다. SLO
목표치, 30일 윈도우, 에러 버짓은 이 파일이 아니라 대시보드에 있습니다.
클러스터마다 달라지는 결정이고, recording rule에 윈도우를 박아 넣으면
쿼리 시점에 다시 물어볼 수 없기 때문입니다. Slurm 기반 SLI는 선택 사항인
Slurm exporter가 없으면 시계열 자체를 만들지 않습니다. 대시보드가 이를 0이나
1로 단정하지 않고 "측정되지 않음"으로 보여주게 하기 위해서입니다.

### `meta` — 모니터링을 모니터링하기

exporter down 알림, "타깃은 살아 있는데 DCGM만 조용한" 상황을 잡는 가드,
그리고 `Watchdog` 데드맨 스위치로 구성됩니다. Watchdog은 항상 발생하도록
만들어 null receiver로 보내는 알림이며, 수신 측에서 이 알림이 *보이지
않는다는 사실* 자체가 알림 파이프라인이 망가졌다는 증거가 됩니다.

일곱 그룹 전체에 대한 rule 유닛 테스트는 `tests/rules/`에 있고, GPU 하드웨어
없이 실행됩니다.

Slurm 통합을 켜면 큐·잡 accounting 알림을 담은 선택적 여덟 번째 그룹
(`slurm`)이 추가됩니다 — [Slurm 통합](slurm.md)을 참고하세요.

## 알림 정책

Alertmanager는 `severity="critical"`과 `severity="warning"`을 서로 다른
Slack 웹훅으로 라우팅하고, `alertname`과 `node`로 알림을 그룹핑하며, 이미
critical로 호출 중인 노드의 warning은 억제합니다. 웹훅 URL은 항상 시크릿
파일로 주입됩니다. git에 저장되는 값은 하나도 없고, 값이 없으면 조용히
망가진 알림 채널을 배포하는 대신 배포 자체가 요란하게 실패합니다.

## 대시보드

`monitoring/dashboards/`의 Grafana 대시보드 열 개가 **Algalon** 폴더로
자동 프로비저닝됩니다.

- **SLO Overview** — 증상부터 보는 진입점. 각 SLI의 30일 준수율을 SLO
  목표치와 비교해 보여주고, 남은 에러 버짓, 지금 발생 중인 알림,
  노드 가용성 소진율(burn rate)을 함께 제공합니다.
- **Alert Center** — 지금 발생 중인 알림을 severity와 노드별로 보여주고,
  Watchdog 파이프라인 점검과 exporter up/down 매트릭스를 함께 제공합니다.
- **GPU Fleet Overview** — GPU별 사용률을 시간축 스트라이프로 표시해(연한
  스트라이프가 낙오된 GPU를 드러냅니다) 클러스터 stat 타일, 노드별 온도와
  메모리를 보여줍니다.
- **Node Health (Precursors)** — 각 전조 메트릭을 P5–P95 피어 밴드로 그리고
  선택한 노드를 그 위에 겹쳐, 리포트의 Figs 2–3을 재현합니다.
- **Checkpoint & Storage I/O** — `algalon:checkpoint_*` recording rule에서
  나온 save/load 구간 밴드를 처리량·큐 대기 시간 패널 위에 얹어 리포트의
  Fig 5를 재현합니다.
- **all-smi (Optional)** — 크로스 플랫폼 하드웨어 뷰. all-smi 프로파일을
  켰을 때만 데이터가 채워집니다.
- **Slurm Queue / Slurm Job Explorer** — 큐 상태와 잡별 accounting 뷰.
  [Slurm 통합](slurm.md)을 구성했을 때만 데이터가 채워집니다.
- **Scheduler Analytics** — Slurm accounting 위에서 보는 7일짜리 정책 관점.
  파티션별 큐 대기·실행 시간 분위수, walltime 정확도, 잡 결과, account별
  GPU 시간을 보여줍니다. 선택적인
  [sacct textfile collector](slurm.md#스케줄러-분석-선택)가 데이터를
  채웁니다. 여기서 호출되는 알림은 하나도 없습니다. 잡 성공률 SLO는
  의도적으로 만들지 않았습니다. 잡 실패의 대부분은 사용자 실수이고, 거기에
  소진율 알림을 걸면 운영자가 고칠 수 없는 실수로 운영자를 호출하게 되기
  때문입니다.
- **GPU Utilization Quality** — 클러스터의 GPU 시간이 실제로 일을 하고
  있는가? 아래 [GPU 활용도 품질](#gpu-활용도-품질)을 보세요.

## GPU 활용도 품질

`DCGM_FI_DEV_GPU_UTIL`은 누구나 먼저 집어 드는 숫자이면서 이 문서에서 가장
약한 신호입니다. 이 값이 말하는 것은 샘플 시점에 *커널이 디바이스에 올라와
있었다*는 사실뿐입니다. dataloader가 속도를 못 맞추는 잡이나 NCCL
all-reduce에서 막혀 있는 잡도 커널은 올라가 있으므로 아무것도 계산하지 않으면서
100%에 가깝게 나옵니다. 그 숫자를 근거로 GPU를 더 사면 함께 기다릴 GPU를 더
사는 것입니다.

그래서 Algalon은 활용도를 네 계층으로 다룹니다. 각 계층은 그 위 계층보다 좁은
질문에 답하고, 인접한 두 계층 사이의 간격이 곧 낭비입니다.

<!-- markdownlint-disable MD013 -->
| 계층 | 답하는 질문 | 메트릭 | 어디서 보나 |
| --- | --- | --- | --- |
| 1. 할당됨 | 이 GPU를 붙잡고 있는 잡이 있는가? | `slurm_job_utilization_gpu` (잡별 cgroup) | `SlurmJobGpuIdle`, Slurm Job Explorer |
| 2. 바쁨 | 커널이 디바이스에 올라와 있는가? | `DCGM_FI_DEV_GPU_UTIL` | GPU Fleet Overview — **단독으로는 약함**: 올라와 있는 것과 실행 중인 것은 다르고, 굶주렸거나 막힌 커널도 100%를 기록합니다 |
| 3. 실제로 계산 중 | warp가 실행되고 있는가? | `DCGM_FI_PROF_SM_ACTIVE`, `DCGM_FI_PROF_SM_OCCUPANCY` | GPU Utilization Quality, `GpuBusyButHollow` |
| 4. 효율적으로 계산 중 | 사려던 연산 유닛을 쓰고 있는가? | `DCGM_FI_PROF_PIPE_TENSOR_ACTIVE`, `DCGM_FI_PROF_DRAM_ACTIVE`, `DCGM_FI_DEV_POWER_USAGE / DCGM_FI_DEV_ENFORCED_POWER_LIMIT` | GPU Utilization Quality |
<!-- markdownlint-enable MD013 -->

전력 대 제한값은 따로 언급할 만합니다. 두 메트릭 모두 기본 카운터 세트에 있어서
프로파일링 필드가 전혀 필요 없는 4계층 신호이기 때문입니다. 실제 학습 작업은
TDP의 0.7–1.0 근처에, 할당만 붙잡은 채 idle 클럭에 머무는 GPU는 0.1–0.3에
있습니다. DCP를 켤 수 없는 클러스터에서는 이 비율이 품질 이야기의 전부입니다.

### 네 가지 낭비 패턴

각각은 두 *계층이 어긋나는* 형태이고, 그래서 메트릭 하나로는 잡히지 않습니다.

- **할당해 놓고 놀림(allocated-idle)** — 잡이 GPU를 붙잡고 있는데 커널이 없음.
  1계층은 높고 2계층이 낮습니다. 노드별 잡 exporter가 존재하는 이유인
  `SlurmJobGpuIdle`이 잡아냅니다.
- **바쁜데 속 빈(busy-but-hollow)** — 커널은 올라와 있는데 warp가 거의 실행되지
  않음. 2계층은 높고 3계층이 낮습니다. 입력 파이프라인, CPU 바운드 전처리,
  collective 대기의 서명입니다. `GpuBusyButHollow`와 GPU Utilization Quality의
  claimed-vs-actual 패널이 드러냅니다.
- **메모리만 붙잡음(memory-holding)** — 프레임버퍼는 차 있는데 SM도 메모리
  인터페이스도 아무것도 하지 않음. `DCGM_FI_DEV_FB_USED`는 높고 3·4계층은 0에
  가깝습니다. DRAM active 대 SM active 패널에서 보입니다.
- **스로틀링(throttled)** — warp는 돌고 싶은데 하드웨어가 막고 있음.
  `DCGM_FI_DEV_CLOCKS_EVENT_REASONS >= 8`이고, 코드 변경 없이 tensor·SM 활동이
  꺼지는 모양으로 나타납니다. `GpuClocksThrottled`가 잡아냅니다. 모델을 탓하기
  전에 먼저 확인하세요.

### 내 잡을 직접 읽기

이 숫자들은 운영자 전용이 아닙니다. 연구자는 **Slurm Job Explorer**를 열어
자신의 `job_id`를 고르고, 자기 실행에 대해 같은 계층을 읽습니다. cgroup에서
나온 GPU별 활용도, 그리고 바로 그 아래의 *SM active on your job's nodes*와
*Power / TDP on your job's nodes*입니다. 활용도는 높은데 SM active가 낮다면
병목은 GPU가 아니라 입력 파이프라인이고, 하드웨어를 더 붙여도 해결되지
않습니다.

운영자는 **GPU Utilization Quality**에서 같은 사실을 클러스터 전체 관점으로
봅니다. 어휘 하나에 청중 둘입니다. 운영자가 "이 잡이 속 빈 채로 돈다"고 말하고
소유자가 자기 대시보드를 열면, 둘 다 3계층이 2계층과 어긋나는 지점을 보고 있는
것입니다.

### 프로파일링 필드 켜기

3·4계층은 `monitoring/exporters/dcgm-counters.csv`에 추가한 DCGM DCP 필드에서
옵니다. 주의사항이 셋 있습니다.

- **Volta 이상.** 그 이전 하드웨어는 이 필드를 노출하지 않습니다. 시계열이 그냥
  없을 뿐이고, 이를 읽는 모든 rule과 패널은 틀린 값을 보이는 대신 비어 있습니다.
- **동시에 도는 프로파일러와 충돌합니다.** 같은 GPU에 붙은 Nsight나 `nvprof`
  세션이 프로파일링 하드웨어를 독점하므로 그동안 DCP 샘플링이 멈춥니다.
- **약간의 샘플링 오버헤드**가 있습니다. "이 GPU가 일을 하고 있는가"에 정직하게
  답하는 유일한 방법의 값입니다.

카운터 세트에는 이미 `DCGM_FI_PROF_NVLINK_*`가 있었으므로 이 CSV를 쓰는
클러스터라면 exporter의 DCP 경로는 이미 검증된 셈입니다. 새 메커니즘이 아니라
새 필드일 뿐입니다.

### 왜 이것이 스케줄러 분석 단계에 있나

활용도 품질은 QoS 정책의 **결과 지표**입니다. Scheduler Analytics는 정책이
무엇을 나눠 줬는지 — account별 GPU 시간, 파티션별 대기, walltime 정확도 —
말합니다. 이쪽은 그중 얼마가 계산으로 바뀌었는지를 말합니다. 앞의 절반만 보는
정책 검토는 시간을 잘 나눠 주는 방향으로 최적화되고, 둘을 함께 보는 검토라야
그 시간이 무언가를 했는지를 묻습니다. Scheduler Analytics의 *Effective fleet
utilization (7d)* 타일이 account별 GPU 시간 옆에 있는 이유가 이것입니다.

account별 유효 시간은 의도적으로 계산하지 **않습니다.** 그러려면 잡 단위 GPU
귀속이 필요하고, 그것은 전용 노드에서만 신뢰할 수 있습니다
([`on(node)` 조인의 한계](slurm.md#onnode-조인-계약) 참고). Algalon은 책임질 수
없는 숫자를 게시하지 않습니다.
