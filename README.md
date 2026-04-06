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
2. **Generates** `CLAUDE.md` with full project context and a 4-phase quality workflow
3. **Creates** `.claude/commands/` with `/test`, `/build`, `/lint`, `/review`, `/check` + framework-specific commands
4. **Configures** `.claude/settings.json` with PostToolUse hooks that run your linter after every code change
5. **Updates** `.gitignore` to exclude `.claude/` local settings

Now when you run `claude`, it automatically follows: **Plan first, implement with quality checks, self-review, then report** — no manual commands needed.

## Why MangoLove

| | Claude Code alone | With MangoLove |
|---|---|---|
| Project setup | Write CLAUDE.md manually (30-60 min) | `mangolove init` (5 seconds) |
| Architecture context | Claude reads files each time | 22 controllers, 115 endpoints known instantly |
| Quality workflow | Depends on your prompt | Mandatory 4-phase: Analyze -> Implement -> Self-Review -> Report |
| Post-edit linting | Manual | Automatic via PostToolUse hooks |
| Context freshness | CLAUDE.md gets stale | `mangolove sync` detects changes |
| Team onboarding | Documentation + tribal knowledge | `--export` / `--from-team` one-command setup |
| Cost visibility | None | `mangolove cost` per-project token tracking |
| Project switching | `cd` + remember context | `mangolove switch crs-be` |

## Strict Mode: The Core Feature

```bash
mangolove init --strict
```

This generates a CLAUDE.md that enforces a 4-phase workflow for every task:

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

### Phase 4: Completion Report
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

**MangoLove** v0.5.0
