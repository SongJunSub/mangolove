# MangoLove

> **이름의 유래**
>
> 제가 키우는 두 마리 진돗개 — 망고(Mango)와 사랑이(Love)의 이름에서 따왔습니다.

**Claude Code를 제대로 쓰는 방법.** `claude` 대신 `mangolove`를 실행하면 모든 세션에 위험도 기반 품질 방법론과 결정적 안전망이 함께 따라옵니다.

MangoLove는 Claude Code를 감쌉니다 — 4-track 방법론을 시스템 프롬프트로 주입하고, 위험 명령과 시크릿 커밋을 실행 전에 차단하며, 실제로 무엇을 잡았는지 측정합니다. 그래서 품질이 *희망*이 아니라 *기본값이자 숫자*가 됩니다.

## `claude` vs `mangolove`

인자 없이 **`mangolove`**를 실행하면 — 내부적으로 같은 `claude`지만 — 방법론과 안전 게이트가 이미 연결된(`claude --settings`로 시작 시 주입) 대화형 세션이 뜹니다. 프로젝트에 설정 파일을 깔거나 스캐폴딩하는 단계는 없습니다 — **그냥 `mangolove`를 실행하면 됩니다.**

| | `claude` (맨) | `mangolove` (bare, 대화형) |
|---|---|---|
| **방법론** | 없음 — 프롬프트에 전적으로 의존 | `strict.md`(4-track Change Impact Score)를 시스템 프롬프트로 주입 |
| **위험 명령** | 그대로 실행 | **실행 전 차단** — force-push, `rm -rf /`/`$PWD`, SQL `DROP`/`TRUNCATE`/`WHERE` 없는 `DELETE`, Mongo `dropDatabase`/`deleteMany({})`, `kubectl delete`, `terraform destroy` (PreToolUse 가드, exit 2) |
| **시크릿 커밋** | 미검사 | 커밋 시점에 시크릿 스캔 게이트로 **차단** |
| **작업 분류** | 없음 | **Trivial / Small / Medium / Large** 자동 분류, 비례 워크플로우 |
| **코드 리뷰** | 요청해야 수행 | Large 트랙에서 **find → verify** 탈상관 멀티에이전트 리뷰 |
| **품질 측정** | 측정 안 됨 | `mangolove efficacy`(게이트가 막은 것 + under-triage), `mangolove eval`(결정적 부품 점수) |
| **오버헤드** | 0 | 훅 몇 개 + 크고 위험한 변경에 더 무거운 절차(사소한 작업은 가볍게 유지) |

**`claude`**는 의견도 오버헤드도 0인 즉석 탐색에, **`mangolove`**는 안전망·일관된 절차·측정 가능한 품질이 중요한 실제 프로젝트 작업에 쓰세요.

> **정직한 경계**: 방법론은 *프롬프트*로 주입됩니다 — 모델에게 따르라고 *요청*하는 것. **게이트·가드는 결정적**(exit code로 실제 차단)이지만, 산문 규율은 확률적으로 지켜집니다. MangoLove는 그 규율을 기본값으로 만들고 단단한 결정적 안전망을 더하는 것이지, 모델을 무오류로 만들지는 않습니다. 실제로 무엇이 측정되고 무엇이 안 되는지는 `mangolove eval` 참조.

## Strict Mode: 위험도 기반 품질 워크플로우

모든 작업이 **Change Impact Score**로 4개 트랙(**Trivial / Small / Medium / Large**)으로 자동 분류되고, 트랙별로 비례하는 워크플로우가 적용됩니다. 방법론의 단일 출처는 [`methodology/strict.md`](methodology/strict.md)이며 **런타임에 시스템 프롬프트로 주입**됩니다(`CLAUDE.md`에 복제하지 않으므로 낡지 않음).

네 트랙은 위험도에 비례해 절차를 키웁니다 — 무거운 트랙은 가벼운 단계를 **건너뛰지 않고 추가**합니다:

| 트랙 | 언제 | 워크플로우 |
|---|---|---|
| **Trivial** | 오타, 설정값, 로그 레벨 | 구현 → 빌드/린트 → 보고 |
| **Small** | 필드 추가, 검증 보강, 버그 수정 | 분석 → 구현 → 셀프 리뷰 → 빌드/린트/테스트 → 보고 |
| **Medium** | 새 비즈니스 로직, API 수정, 서비스 연동 | + Spec → 승인 → 1인 리뷰 |
| **Large** | 신규 API, DB 스키마, 인증 변경, 대규모 리팩토링 | + 적대적 Spec 리뷰 → Product/Engineering 리뷰 → 3인 탈상관 리뷰 |

트랙은 파일 수 + 신호로 계산되고, [`lib/impact-score.sh`](lib/impact-score.sh)의 결정적 floor가 점수와 무관하게 **승격 트리거**를 강제합니다 — DB 스키마 변경은 최소 **Medium**, 외부 API 연동은 최소 **Medium**, 인증 변경은 최소 **Large**. (`mangolove impact`로 임의 변경의 계산된 트랙 확인.)

### 멀티에이전트 리뷰 (Medium & Large) — find → verify

리뷰는 이슈를 *찾기만* 하지 않습니다. 각 발견은 수정 대상이 되기 전에 **적대적으로 검증**됩니다:

- **탈상관 렌즈** — 리뷰어를 도메인(보안 / 성능 / 비즈니스 로직)만이 아니라 *방법*(정독 / 적대적 반증 / 반례 생성)으로도 나눕니다. 같은 모델·같은 프레임은 같은 맹점을 공유하기 때문.
- **find → verify** — 각 Critical/Major 발견은 별도 에이전트가 반증(기본값 refuted)을 시도해 살아남은 것만 수정 대상이 되고, 고위험 변경은 다수결 검증을 씁니다. 정밀도가 올라 — 그럴듯하나 틀린 발견이 불필요한 수정을 유발하지 않습니다.
- 신뢰의 근거는 **검증을 통과한 발견**이지 "N명이 동의함"이 아닙니다(상관된 동의는 독립 검증이 아님).

### 완료 보고
무엇이 바뀌었는지, 빌드/린트/테스트 결과(산출물 경로 포함), Medium/Large는 **확정 vs 반증** 발견까지 보고합니다. 목표는 자동 코드 리뷰(Gemini, CodeRabbit 등)를 첫 제출에 통과하되 — *왜 믿을 수 있는지의 근거와 함께* — "PASS"만 보고하지 않는 것입니다.

### 메서드러지 전달 — monolith / split
방법론의 단일 출처는 [`methodology/strict.md`](methodology/strict.md)입니다. 전달 방식은 두 가지:

- **`monolith`** (기본) — strict.md 전체를 시스템 프롬프트로 주입. 동작 검증된 안전 기본값.
- **`split`** (옵트인) — 린 [`methodology/core.md`](methodology/core.md)만 주입하고, 무거운 절차(Spec 템플릿·Large 리뷰·CI/CD·worktree)는 `cc-plugin` 네이티브 스킬로 **온디맨드 로드**(`--plugin-dir`, mangolove 세션 한정 → bare `claude`는 0 오버헤드). 안전 절차(dry-run·메모리·경계면)와 트랙 판정은 코어에 상주. 상시 주입 토큰 ~43% 감소.

`core.md`/스킬은 [`lib/gen-methodology.sh`](lib/gen-methodology.sh)가 strict.md에서 생성하며(손 편집 금지), `tests/methodology-split.bats`가 재생성 일치·커버리지를 강제합니다. 전환: `MANGOLOVE_METHODOLOGY_MODE=split`.

## 전체 기능

### 비용 추적
```bash
mangolove cost                # 이번 주 토큰 사용량·비용
mangolove cost today          # 오늘
mangolove cost month          # 이번 달
mangolove cost all            # 전체 기간
```

### 생산성
```bash
mangolove stats               # git 기반 생산성 대시보드
mangolove stats today         # 오늘의 커밋·파일·LOC
mangolove stats month         # 월간 유형별 분석
```

### 프로젝트 네비게이션
```bash
mangolove switch              # 등록된 프로젝트 목록
mangolove switch crs-be       # 프로젝트로 전환 + claude 실행
mangolove projects            # 프로젝트 프로필 목록
```

### 세션 메모리
```bash
mangolove resume              # 이전 세션 컨텍스트 이어가기
mangolove sessions            # 저장된 세션 목록
```

### 측정 · 자가평가
```bash
mangolove impact [sha]        # 변경의 결정적 트랙/영향도 (워킹트리 또는 커밋)
mangolove efficacy            # 게이트/가드가 실제로 막은 것 + 트랙 under-triage
mangolove eval                # 자가평가 — impact-score 보정도 + 가드 정밀도/재현율 (정직한 known-gap 포함)
mangolove ab                  # A/B 하니스 (방법론 vs 맨 claude): 게이트 보호 + 채점 엔진
```
세션 중 타이핑하는 명령이 아니라, 프로젝트에서 시스템을 점검할 때 쓰는 ops/CI용 명령입니다.

### 안전 게이트 (모든 `mangolove` 세션에서 활성)
두 개의 PreToolUse 훅이 자동 동작합니다 — 설정·설치 불필요:
- **커밋 게이트** — 스테이징된 변경에서 시크릿(+선택적 lint/test)을 스캔해 발견 시 **커밋을 차단**.
- **비가역 명령 가드** — force-push, 위험 루트의 `rm -rf`, 파괴적 SQL/Mongo, `kubectl delete`, `terraform destroy` 를 실행 전 차단. 의도된 실행: `MANGOLOVE_ALLOW_DANGER=1`(감사 대상).
- **DoD 게이트**(옵트인, `MANGOLOVE_DOD_GATE=on`) — Stop 훅이 완료 직전 `./.mangolove/dod.sh`(모델이 외부화한 실행형 DoD)를 검증해, **통과 전에는 턴을 끝내지 못하게** 차단. 자기채점이 아니라 코드로 닫는 검증 루프. `MANGOLOVE_DOD_MAX_ATTEMPTS`(기본 3) 회 후 무한루프 방지 해제.

차단된 건은 로컬 효능 원장에 기록돼 `mangolove efficacy`가 무엇을 잡았는지 보고합니다.

### 커밋 트레일러 — `Change-Track:`
방법론은 에이전트가 사용한 트랙을 커밋 footer에 기록하도록 요청합니다:
```
Change-Track: <Trivial|Small|Medium|Large>
```
`mangolove efficacy`가 이 선언값을 코드가 계산한 floor와 대조해 **under-triage**(영향도보다 가볍게 선언된 변경 — 리뷰 누락 신호)를 보고합니다. 미기재 시 측정에서만 빠질 뿐 동작에는 영향 없습니다.

### 기타
```bash
mangolove doctor              # 헬스 체크
mangolove update              # MangoLove 업데이트
mangolove help                # 전체 명령 목록
```

## 지원 기술 스택

- **Java/Kotlin**: Gradle, Maven, Spring Boot, JPA, QueryDSL, WebFlux
- **Node.js**: npm, yarn, pnpm, bun, TypeScript, React, Next.js, Vue, NestJS, Express
- **Python**: pip, Django, FastAPI, Flask, pytest, ruff, mypy
- **Go**: go modules, golangci-lint
- **Rust**: Cargo, clippy
- **Databases**: MySQL, PostgreSQL, MongoDB, Redis, ElasticSearch
- **Infrastructure**: Docker, Kubernetes, GitHub Actions, Jenkins, Terraform

(impact-score의 결정적 트랙 분류는 위에 더해 C#/.NET·PHP/Laravel·Ruby/Elixir의 일부 관용구도 커버합니다 — 정확한 커버리지는 `mangolove eval`이 known-gap과 함께 보고.)

## 요구사항

- [Claude Code](https://claude.ai/claude-code) — `claude` 명령이 PATH에 있어야 함
- [GitHub CLI](https://cli.github.com/) (`gh`) — 선택(작업 로깅용)
- Git
- python3 — 비용 추적에 필요

## 설치

```bash
curl -fsSL https://raw.githubusercontent.com/SongJunSub/mangolove/main/install.sh | bash
```

또는 수동으로:

```bash
git clone https://github.com/SongJunSub/mangolove.git ~/.mangolove
chmod +x ~/.mangolove/bin/mangolove
ln -sf ~/.mangolove/bin/mangolove ~/.local/bin/mangolove
```

확인:

```bash
mangolove --version
mangolove doctor
```

## 테스트

```bash
bats tests/                              # 전체 스위트
shellcheck -x bin/mangolove lib/*.sh     # 린트
```

## 기여

1. 이 저장소를 Fork
2. 기능 브랜치 생성
3. `bats tests/`와 `shellcheck -x bin/mangolove lib/*.sh` 통과 확인
4. Pull Request 생성

## 라이선스

MIT License — 자세한 내용은 [LICENSE](LICENSE) 참조.

---

**MangoLove** v0.5.0
