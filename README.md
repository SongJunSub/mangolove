# MangoLove

**The best way to use Claude Code.** One command to set up any project for optimal AI-assisted development.

MangoLove scans your project, generates the right configuration, and gives Claude Code the context it needs to be maximally productive — including a mandatory quality workflow that catches issues before they reach code review.

> **Origin of the name**
> Named after two Jindo dogs — Mango and Sarang (Love).

## What It Does

```bash
cd ~/my-project
mangolove init --strict
```

This single command:
1. **Scans** your project (tech stack, dependencies, architecture, API endpoints)
2. **Generates** `CLAUDE.md` with full project context and a 5-phase quality workflow
3. **Creates** `.claude/commands/` with `/test`, `/build`, `/lint`, `/review`, `/check` + framework-specific commands
4. **Configures** `.claude/settings.json` with PostToolUse hooks that run your linter after every code change
5. **Updates** `.gitignore` to exclude `.claude/` local settings

Now when you run `claude`, it automatically follows: **Plan first, implement with quality checks, self-review, 3-agent parallel review, then report** — no manual commands needed.

## Why MangoLove

| | Claude Code alone | With MangoLove |
|---|---|---|
| Project setup | Write CLAUDE.md manually (30-60 min) | `mangolove init` (5 seconds) |
| Architecture context | Claude reads files each time | 22 controllers, 115 endpoints known instantly |
| Quality workflow | Depends on your prompt | Mandatory 5-phase: Analyze -> Implement -> Self-Review -> 3-Agent Review -> Report |
| Post-edit linting | Manual | Automatic via PostToolUse hooks |
| Context freshness | CLAUDE.md gets stale | `mangolove sync` detects changes |
| Team onboarding | Documentation + tribal knowledge | `--export` / `--from-team` one-command setup |
| Cost visibility | None | `mangolove cost` per-project token tracking |
| Project switching | `cd` + remember context | `mangolove switch crs-be` |

## Strict Mode: The Core Feature

```bash
mangolove init --strict
```

This generates a CLAUDE.md that enforces a 5-phase workflow for every task:

### Phase 1: Analysis (Always First)
When you describe a problem, Claude automatically:
- Reads all related files and traces the full call chain
- Identifies every affected file
- Presents a plan and **waits for your approval** before coding

### Phase 2: Implementation
After you approve, Claude implements with built-in verification for:
- **Security** — SQL injection, XSS, hardcoded secrets, auth gaps, input validation
- **Style** — Runs your linter, matches existing patterns, no dead code
- **Performance** — N+1 queries, unnecessary allocations, blocking in async code
- **Maintainability** — Single responsibility, clear naming, no magic numbers
- **Null Safety** — Optional types, specific exceptions, context in error messages

### Phase 3: Self-Review (Mandatory)
After implementation, Claude performs a hostile self-review against a 10-point checklist:
- OWASP Top 10, performance anti-patterns, test coverage, code duplication, thread safety, API consistency
- Any failure triggers automatic fix + re-verification

### Phase 4: 3-Agent Parallel Independent Code Review
Before commit & push, 3 independent review agents run in parallel:
- Each agent reviews the **full scope** — code quality, security, performance, edge cases, reusability, efficiency, design consistency
- Not 1 reviewer per topic, but 3 reviewers each doing a full review from different perspectives
- All issues from all 3 reviews must be fixed before commit & push

### Phase 5: Completion Report
```
Changes:
  - ReservationService.java: added cancellation validation
  - ReservationController.java: new DELETE /v1/reservations/{id}

Verification:
  - Build: PASS
  - Lint: PASS
  - Tests: PASS (45 passed, 2 new)

Self-Review:
  - Security: PASS
  - Performance: PASS
  - Style: PASS
  - Maintainability: PASS
```

**Goal**: Code quality high enough to pass automated code review (Gemini, CodeRabbit, etc.) with zero issues on first submission.

> **Why 3 agents instead of 1?**
> A single reviewer has blind spots shaped by its context. Three independent reviewers, each doing a full review without seeing each other's findings, catch issues that any single pass would miss — the same principle behind requiring multiple approvals on production PRs.

## All Features

### Project Setup
```bash
mangolove init                # Generate CLAUDE.md + commands + hooks
mangolove init --strict       # Same + 4-phase quality workflow
mangolove init --force        # Regenerate even if CLAUDE.md exists
mangolove init --export       # Export .mangolove.md for team sharing
mangolove init --from-team    # Setup from team's .mangolove.md
mangolove sync                # Update CLAUDE.md with current project state
```

### Cost Tracking
```bash
mangolove cost                # This week's token usage and cost
mangolove cost today          # Today only
mangolove cost month          # This month
mangolove cost all            # All time
```

Output:
```
Total Cost
  Estimated  : $408.55
  Sessions   : 49
  Messages   : 5381

By Project
  CRS-crs    — $101.94 (14 sessions, 430.3K output)
  crs-be     — $89.37 (8 sessions, 298.0K output)
  crs-admin  — $74.05 (7 sessions, 250.5K output)
```

### Productivity
```bash
mangolove stats               # Git-based productivity dashboard
mangolove stats today         # Today's commits, files, LOC
mangolove stats month         # Monthly breakdown by type
```

### Project Navigation
```bash
mangolove switch              # List all registered projects
mangolove switch crs-be       # Switch + auto-sync + launch claude
mangolove projects            # List project profiles
```

### Session Memory
```bash
mangolove resume              # Continue with previous session context
mangolove sessions            # List saved sessions
```

### Other
```bash
mangolove doctor              # Health check
mangolove update              # Update MangoLove
mangolove help                # Full command list
```

## Deep Project Analysis

`mangolove init` doesn't just detect "Java + Spring Boot". It performs deep source code analysis:

```
Detected:
  Tech Stack : Java, Spring Boot
  Database   : MySQL, Redis
  Infra      : GitHub Actions
  Build      : ./gradlew build
  Test       : ./gradlew test
  Lint       : ./gradlew check
  Modules    : crs-be-core, crs-be-back
  Controllers: 22
  Services   : 22
  Entities   : 3
  Endpoints  : GET:73 POST:20 PUT:20 DELETE:2
```

The generated CLAUDE.md includes:
- All API endpoint paths (`/v1/users`, `/v1/payments`, ...)
- Base package name (`me.onda.crs`)
- Component counts by type
- Framework-specific slash commands (`/entity`, `/api`, `/migration` for Spring Boot)

## Supported Tech Stacks

- **Java/Kotlin**: Gradle, Maven, Spring Boot, JPA, QueryDSL, WebFlux
- **Node.js**: npm, yarn, pnpm, bun, TypeScript, React, Next.js, Vue, NestJS, Express
- **Python**: pip, Django, FastAPI, Flask, pytest, ruff, mypy
- **Go**: go modules, golangci-lint
- **Rust**: Cargo, clippy
- **Databases**: MySQL, PostgreSQL, MongoDB, Redis, ElasticSearch
- **Infrastructure**: Docker, Kubernetes, GitHub Actions, Jenkins, Terraform

## Requirements

- [Claude Code](https://claude.ai/claude-code) — `claude` command must be in PATH
- [GitHub CLI](https://cli.github.com/) (`gh`) — Optional, for work logging
- Git
- python3 — Required for cost tracking

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/SongJunSub/mangolove/main/install.sh | bash
```

Or manually:

```bash
git clone https://github.com/SongJunSub/mangolove.git ~/.mangolove
chmod +x ~/.mangolove/bin/mangolove
ln -sf ~/.mangolove/bin/mangolove ~/.local/bin/mangolove
```

Verify:

```bash
mangolove --version
mangolove doctor
```

## Testing

```bash
bats tests/          # 108 tests
```

## Contributing

1. Fork this repository
2. Create your feature branch
3. Ensure `bats tests/` and `shellcheck -x bin/mangolove lib/*.sh` pass
4. Open a Pull Request

## License

MIT License — see [LICENSE](LICENSE) for details.

---

# MangoLove (한국어)

**Claude Code를 제대로 쓰는 방법.** 한 번의 명령으로 모든 프로젝트를 AI 개발 환경에 최적화합니다.

MangoLove는 프로젝트를 스캔하고, 적절한 설정을 생성하며, Claude Code가 최대한 생산적으로 동작하는 데 필요한 컨텍스트를 제공합니다. 코드 리뷰에 도달하기 전에 문제를 잡아내는 필수 품질 워크플로우를 포함합니다.

> **이름의 유래**
> 두 마리 진도견 — 망고(Mango)와 사랑(Love)의 이름에서 따왔습니다.

## 주요 기능

```bash
cd ~/my-project
mangolove init --strict
```

이 한 줄의 명령이:
1. 프로젝트를 **분석** (기술 스택, 의존성, 아키텍처, API 엔드포인트)
2. `CLAUDE.md`를 **생성** (전체 프로젝트 컨텍스트 + 5단계 품질 워크플로우)
3. `.claude/commands/`에 슬래시 커맨드를 **생성** (`/test`, `/build`, `/lint`, `/review`, `/check` + 프레임워크별 커맨드)
4. `.claude/settings.json`에 PostToolUse 훅을 **설정** (코드 변경 시 자동 린터 실행)
5. `.gitignore`를 **업데이트** (`.claude/` 로컬 설정 제외)

`claude`를 실행하면 자동으로: **분석 -> 구현 -> 셀프 리뷰 -> 3인 병렬 리뷰 -> 완료 보고** — 별도 명령 불필요.

## Strict Mode: 5단계 품질 워크플로우

### 1단계: 분석 (항상 먼저)
- 관련 파일을 모두 읽고 전체 호출 체인을 추적
- 영향받는 모든 파일을 식별하고 계획을 제시
- **사용자 승인을 기다린 후** 코딩 시작

### 2단계: 구현
보안(OWASP Top 10), 스타일, 성능, 유지보수성, Null Safety 등 내장 검증을 수행하며 구현

### 3단계: 셀프 리뷰 (필수)
10개 항목의 적대적 셀프 리뷰 — 실패 시 자동 수정 + 재검증

### 4단계: 3인 병렬 독립 코드 리뷰
커밋 & 푸시 전, 3개의 독립 리뷰 에이전트를 병렬 실행:
- 각 에이전트가 **전체 관점** (코드 품질 / 보안 / 성능 / 엣지 케이스 / 재사용성 / 효율성 / 설계 의도와의 일관성)을 모두 검토
- 관점별 1명이 아니라 3명이 각각 전체 리뷰를 수행하여 서로 다른 시각에서 이슈 발견
- 3명의 리뷰에서 발견된 이슈를 모두 수정한 후에만 커밋 & 푸시

> **왜 3명인가?**
> 단일 리뷰어는 자기 컨텍스트에 의한 사각지대가 있습니다. 서로의 결과를 보지 않고 독립적으로 전체 리뷰를 수행하는 3명은, 단일 패스에서 놓칠 수 있는 이슈를 잡아냅니다.

### 5단계: 완료 보고
```
변경 사항:
  - ReservationService.java: 취소 검증 추가
  - ReservationController.java: DELETE /v1/reservations/{id} 신규

검증 결과:
  - 빌드: PASS
  - 린트: PASS
  - 테스트: PASS (45개 통과, 2개 신규)

셀프 리뷰:
  - 보안: PASS
  - 성능: PASS
  - 스타일: PASS
  - 유지보수성: PASS
```

**목표**: 자동 코드 리뷰(Gemini, CodeRabbit 등)에서 첫 제출에 지적사항 제로.

---

**MangoLove** v0.6.0
