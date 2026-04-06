# MangoLove

**The best way to use Claude Code.** One command to set up any project for optimal AI-assisted development.

MangoLove scans your project, generates the right configuration, and gives Claude Code the context it needs to be 10x more productive.

> **Origin of the name**
> Named after two Jindo dogs — Mango and Sarang (Love).

## What It Does

```bash
cd ~/my-project
mangolove init
```

This single command:
1. Scans your project (tech stack, dependencies, build tools, linters)
2. Generates `CLAUDE.md` with project context and conventions
3. Creates `.claude/commands/` with `/test`, `/build`, `/lint`, `/review`, `/check`
4. Sets up `.claude/settings.json` with appropriate hooks

Now when you run `claude` in that directory, it already knows your project.

## Key Features

| Feature | What it does |
|---------|-------------|
| `mangolove init` | One-command project setup for Claude Code |
| `mangolove init --strict` | Same + quality gates (auto lint/test enforcement) |
| `mangolove resume` | Continue from where you left off (cross-session memory) |
| `mangolove stats` | Git-based productivity dashboard |
| `mangolove skill install` | Install composable skill packs |
| 9 specialized modes | TDD, strict, review, debug, refactor, security, docs, PR, plan |

## How It Compares

| | Claude Code alone | With MangoLove |
|---|---|---|
| Project context | Write CLAUDE.md manually | Auto-generated from project scan |
| Slash commands | Create .claude/commands/ manually | Auto-generated (/test, /build, /lint, /review, /check) |
| Session memory | Lost between sessions | Persisted and auto-injected |
| Productivity tracking | None | `mangolove stats` |
| Quality enforcement | Manual | `--strict` mode |

## Requirements

- [Claude Code](https://claude.ai/claude-code) — `claude` command must be available in PATH
- [GitHub CLI](https://cli.github.com/) (`gh`) — Optional, for work logging
- Git

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

## Quick Start

```bash
# 1. Initialize your project
cd ~/my-project
mangolove init

# 2. Use Claude Code as usual — it now has full project context
claude

# 3. Try the generated commands
# /test, /build, /lint, /review, /check
```

## Usage

### Project Setup

```bash
mangolove init                # Generate CLAUDE.md + commands + hooks
mangolove init --strict       # Same + quality gates
mangolove init --force        # Regenerate even if CLAUDE.md exists
```

### Session Memory

```bash
mangolove resume              # Continue from last session with context
mangolove sessions            # List all saved sessions
```

### Productivity

```bash
mangolove stats               # This week's stats
mangolove stats today         # Today's stats
mangolove stats month         # This month's stats
```

### Modes (via wrapper)

```bash
mangolove --mode tdd          # Test-driven development
mangolove --mode strict       # Auto build/lint/test pipeline
mangolove --mode review       # Code review
mangolove --mode debug        # Debugging
mangolove --mode refactor     # Refactoring
mangolove --mode security     # Security audit
mangolove --mode docs         # Documentation sync
mangolove --mode pr           # PR creation
mangolove --mode plan         # Planning
```

### Skill Packs

```bash
mangolove skill               # List skills
mangolove skill install <url> # Install from git
mangolove skill create <name> # Create template
mangolove skill update        # Update all
```

### Other

```bash
mangolove doctor              # Health check
mangolove update              # Update MangoLove
mangolove help                # Full command list
```

## Supported Tech Stacks

MangoLove auto-detects and configures for:

- **Java/Kotlin**: Gradle, Maven, Spring Boot, JPA, QueryDSL, WebFlux
- **Node.js**: npm, yarn, pnpm, bun, TypeScript, React, Next.js, Vue, NestJS, Express
- **Python**: pip, Django, FastAPI, Flask, pytest, ruff, mypy
- **Go**: go modules, golangci-lint
- **Rust**: Cargo, clippy
- **Databases**: MySQL, PostgreSQL, MongoDB, Redis, ElasticSearch
- **Infrastructure**: Docker, Kubernetes, GitHub Actions, Jenkins, Terraform

## Testing

```bash
# Requires bats-core
bats tests/          # 104 tests
```

## Contributing

1. Fork this repository
2. Create your feature branch
3. Ensure `bats tests/` and `shellcheck -x bin/mangolove lib/*.sh` pass
4. Open a Pull Request

## License

MIT License — see [LICENSE](LICENSE) for details.

---

**MangoLove** v0.4.0
