# 개발

[English](../development.md) | **한국어**

모든 검증은 살아 있는 클러스터가 아니라 저장소를 대상으로 이루어집니다.
아래의 Make 타깃은 각각 실제 업스트림 검증 도구를 컨테이너로 실행하는
것이라, CI와 로컬 노트북이 동일한 결과를 내고 GPU도 필요하지 않습니다.

## 검증 타깃

| 타깃 | 검증 내용 |
| --- | --- |
| `make rules-validate` | rule 파일에 대한 `vmalert -dryRun` |
| `make rules-test` | `tests/rules/`의 rule 유닛 테스트 |
| `make scrape-validate` | `vmagent -promscrape.config -dryRun` |
| `make alertmanager-validate` | `amtool check-config` |
| `make compose-validate` | 프로파일 유무 양쪽에 대한 두 스택 검증 |
| `make dashboards-validate` | 대시보드 JSON 컨벤션 |
| `make helm-validate` | `helm lint` + `helm template \| kubeconform` |

커밋 전에 전체 게이트를 돌립니다.

```bash
make rules-validate rules-test scrape-validate alertmanager-validate \
  compose-validate dashboards-validate helm-validate
```

## rule 유닛 테스트

vmalert rule 그룹은 `vmalert-tool unittest`로 테스트합니다(`tests/rules/`에
있는 promtool 호환 테스트 파일). 테스트는 각 rule에 합성 시계열을 넣고
양성 케이스 — 알림이 정확한 라벨과 summary로 발생하는지 — 와 음성 케이스 —
정상적인 피어 노드는 조용한지 — 를 모두 확인합니다. rule을 추가할 때는 두
케이스를 함께 추가하세요. 절대 실패할 수 없는 테스트는 테스트가 없는 것보다
나쁩니다.

## 엔드투엔드 스모크 테스트

`make e2e-k3d`는 일회용 k3d 클러스터에 파이프라인 전체를 띄우고 네 가지를
확인합니다. 여섯 개 rule 그룹이 vmalert에 모두 로드되었는지, Watchdog
알림이 Alertmanager까지 도달하는지(알림 경로가 끝까지 살아 있다는 증거),
Kubernetes 서비스 디스커버리를 통한 노드 scrape이 동작하는지, 그리고 GPU
전용 DaemonSet이 GPU 없는 노드에서 의도대로 스케줄되지 않고 남아 있는지를
봅니다.

```bash
make e2e-k3d      # requires docker, k3d, helm, kubectl; takes a few minutes
```

클러스터는 성공하든 실패하든 종료 시점에 삭제됩니다.

## CI

푸시할 때마다 검증 게이트가 실행되고, k3d 스모크 테스트는 후속 잡으로
돌아갑니다. 컨트리뷰션 규칙과 이 코드베이스의 눈에 잘 띄지 않는 제약들은
[`AGENTS.md`](../../AGENTS.md)에 정리되어 있습니다.
