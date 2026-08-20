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
| Grafana | 자동 프로비저닝되는 여덟 개 대시보드 |

VictoriaLogs는 아무도 scrape하지 않는 유일한 구성 요소입니다. Slurm
컨트롤러에서 `EpilogSlurmctld`로 도는 `monitoring/slurm/epilog-logpush.sh`가
이 저장소에 씁니다. 두 배포 경로 모두에서 명시적으로 켜기 전까지는 꺼져
있습니다(compose `logs` 프로파일, 또는 차트의 `victorialogs.enabled`).
[잡 로그](slurm.md#잡-로그-선택)를 보세요.

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

`monitoring/dashboards/`의 Grafana 대시보드 여덟 개가 **Algalon** 폴더로
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
