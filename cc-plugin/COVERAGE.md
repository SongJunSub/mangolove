# Methodology coverage map

`methodology/strict.md` 는 방법론의 **단일 출처**다. `methodology/core.md` 와 `cc-plugin/skills/*`
는 `lib/gen-methodology.sh` 가 strict.md 에서 **줄 범위로 추출**해 생성한다(손 편집 금지).
`tests/methodology-split.bats` 가 재생성 일치·커버리지·안전절차 상주를 강제한다.

| strict.md 섹션 (줄) | 목적지 | 비고 |
|---|---|---|
| 해결 접근 원칙 · 자동 행동 전환 · 작업 규모 분류 · 트랙 스킵 금지 · 승인 원칙 · 작은 편집 루프 · 진행 외부화 · 메모리 루프 · 자가수정 · 경계면 · Dry-run 게이트 · 마이그레이션 전략 (1–431) | **core.md** | 트랙 판정·승인·**안전 절차** 전부 코어 상주 |
| `## Large Track 워크플로우` 헤더 (432–433) | *(드롭)* | core.md 의 "트랙 워크플로우 상세" 포인터로 대체 |
| 1–5단계: 분석·Spec·7템플릿·Spec 적대리뷰·Product/Eng·최종승인 (434–662) | **skill: mangolove-spec** | Medium/Large Spec 단계 |
| 6–10단계: 구현·셀프리뷰·3인 find→verify·Dashboard·완료보고 (663–934) | **skill: mangolove-large-review** | Large 구현~완료 |
| 스마트 리뷰 라우팅 (935–946) | **core.md** | 짧음, 상주 |
| 서브에이전트 병렬 작업 규칙 (947–990) | **skill: mangolove-subagent-worktree** | 병렬 작업 시에만 |
| CI/CD 워크플로우 작업 규칙 (991–1012) | **skill: mangolove-cicd** | CI/CD 변경 시에만 |
| 신뢰성 게이트 (1013–1047) | **core.md** | 메타원칙, 상주 |

재생성: `bash lib/gen-methodology.sh` — strict.md 변경 시 반드시 재실행하고 diff 를 커밋한다.
