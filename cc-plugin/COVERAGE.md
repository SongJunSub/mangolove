# Methodology coverage map

`methodology/strict.md` 는 방법론의 **단일 출처**다. `methodology/core.md` 와 `cc-plugin/skills/*`
는 `lib/gen-methodology.sh` 가 strict.md 에서 **줄 범위로 추출**해 생성한다(손 편집 금지).
`tests/methodology-split.bats` 가 재생성 일치, 커버리지, 안전절차 상주를 강제한다.

**줄 번호는 어디에도 적지 않는다.** 생성기는 아래 섹션 헤딩의 **텍스트**로 경계를 찾아
범위를 계산한다. 그래서 섹션 안에서 줄을 고치는 데는 아무 수작업이 필요 없다.
테스트는 범위를 다시 적지 않고 `gen-methodology.sh --print-ranges` 로 물어본다.

구조가 바뀌면 생성기가 큰소리로 실패한다. 경계 헤딩이 바뀌거나 중복되면, 꼬리 영역에
새 `## ` 섹션이 생기면, `## Large Track 워크플로우` 헤더와 `### 1단계` 사이에 내용이
끼면 즉시 멈춘다. 새 섹션의 목적지(코어 상주 vs 온디맨드 스킬)는 사람이 정해야 하는
결정이라 자동으로 흡수시키지 않는다. 이 가드레일은 `tests/methodology-split.bats` 의
변이 테스트 5건이 지킨다.

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
