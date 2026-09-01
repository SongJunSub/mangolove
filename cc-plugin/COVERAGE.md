# Methodology coverage map

`methodology/strict.md` 는 방법론의 **단일 출처**다. `methodology/core.md` 와 `cc-plugin/skills/*`
는 `lib/gen-methodology.sh` 가 strict.md 에서 **줄 범위로 추출**해 생성한다(손 편집 금지).
`tests/methodology-split.bats` 가 재생성 일치, 커버리지, 안전절차 상주를 강제한다.

**줄 번호는 여기 적지 않는다.** strict.md 를 고칠 때마다 세 곳(생성기, 테스트, 이 문서)을 손으로
맞춰야 하면 그 자체가 드리프트의 원인이 된다. 실제 범위는 `lib/gen-methodology.sh` 의
`assert_anchor` 와 `sed -n 'N,Mp'` 가 유일한 출처이고, 테스트는 그 값을 생성기에서 파싱한다.

| strict.md 섹션 | 목적지 | 비고 |
|---|---|---|
| 해결 접근 원칙, 구현 선택 원칙, 자동 행동 전환, 작업 규모 분류, 트랙별 필수 리뷰, 스킵 금지, 승인 원칙, 작은 편집 루프, 세션 위생, 진행 외부화, 메모리 루프, 자가수정 루프, 경계면 교차검증, Dry-run 게이트, 마이그레이션 전략 | **core.md** | 트랙 판정, 승인, **안전 절차** 전부 코어 상주 |
| `## Large Track 워크플로우` 헤더 | *(드롭)* | core.md 의 "트랙 워크플로우 상세" 포인터로 대체 |
| 1~5단계: 분석, Spec, 7종 템플릿, Spec 적대 리뷰, Product/Eng 리뷰, 최종 승인 | **skill: mangolove-spec** | Medium/Large Spec 단계 |
| 6~10단계: 구현, 셀프 리뷰, 3인 find→verify, Dashboard, 완료 보고 | **skill: mangolove-large-review** | Large 구현~완료 |
| 스마트 리뷰 라우팅 | **core.md** | 짧음, 상주 |
| 서브에이전트 병렬 작업 규칙 | **skill: mangolove-subagent-worktree** | 병렬 작업 시에만 |
| CI/CD 워크플로우 작업 규칙 | **skill: mangolove-cicd** | CI/CD 변경 시에만 |
| 신뢰성 게이트 | **core.md** | 메타원칙, 상주 |

## 에이전트

`cc-plugin/agents/` 는 생성물이 아니라 손으로 관리하는 정의다. Large 트랙 3인 탈상관 리뷰의
구성을 세션마다 즉흥으로 짓지 않기 위해 존재한다.

| 에이전트 | 렌즈 |
|---|---|
| `mangolove-reviewer-close-read` | 정독 |
| `mangolove-reviewer-refute` | 적대적 반증 |
| `mangolove-reviewer-counterexample` | 반례 생성 |
| `mangolove-verifier` | find→verify 의 verify (기본 판정 REFUTED) |

넷 다 읽기 전용이다(`Edit`/`Write` 없음). 리뷰어가 코드를 고칠 수 있으면 리뷰가 아니라 두 번째 구현이다.

재생성: `bash lib/gen-methodology.sh`, strict.md 변경 시 반드시 재실행하고 diff 를 커밋한다.
