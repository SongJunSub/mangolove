# MangoLove

**Autonomous Development Agent** — Built on [Claude Code](https://claude.ai/claude-code)

MangoLove is an autonomous development agent built on top of Claude Code. It remembers project-specific context, enforces development best practices, and handles the full workflow from analysis to implementation.

> **Origin of the name**
> Named after two Jindo dogs.
> - **Mango** — a white Jindo with scattered golden spots
> - **Sarang (Love)** — a pure white Jindo
>
> Mango + Love = **MangoLove**

## Features

- **Autonomous Execution** — Analyzes, plans, implements, and verifies tasks end-to-end
- **Project Profiles** — Remembers per-project tech stacks, conventions, and architecture
- **Skill Packs** — Composable, installable skill packs from git repositories or local directories
- **9 Specialized Modes** — TDD, strict (auto lint/test/build), code review, debugging, refactoring, security audit, documentation sync, PR creation, and planning
- **Work Logging** — Records session history to a GitHub private repository
- **Plugin System** — Hook-based extensibility with 4 hook types
- **Shell Completions** — Tab completion for Bash and Zsh
- **Config Validation** — Syntax checking before sourcing configuration
- **Claude Code Compatible** — Full access to all Claude Code features

## Requirements

- [Claude Code](https://claude.ai/claude-code) — `claude` command must be available in PATH
- [GitHub CLI](https://cli.github.com/) (`gh`) — Required for work logging
- Git

## Installation

### Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/SongJunSub/mangolove/main/install.sh | bash
```

### Manual Install

```bash
git clone https://github.com/SongJunSub/mangolove.git ~/.mangolove
chmod +x ~/.mangolove/bin/mangolove
ln -sf ~/.mangolove/bin/mangolove ~/.local/bin/mangolove
```

> Ensure `~/.local/bin` is included in your PATH.
> If not, add the following to `~/.zshrc` or `~/.bashrc`:
> ```bash
> export PATH="$HOME/.local/bin:$PATH"
> ```

### Verify Installation

```bash
mangolove --version
mangolove help
```

## Usage

### Basic

```bash
# Start an interactive session
mangolove

# Execute a task directly
mangolove "Refactor the reservation API"

# Resume the last session
mangolove -c

# Print mode (for piping)
mangolove -p "Review this code"
```

### Modes

```bash
mangolove --mode review       # Code review mode
mangolove --mode debug        # Debug and root-cause analysis
mangolove --mode refactor     # Refactoring mode
mangolove --mode security     # Security audit mode
mangolove --mode plan         # Planning mode
mangolove --mode pr           # PR creation mode
mangolove --mode tdd          # Test-driven development (RED-GREEN-REFACTOR)
mangolove --mode strict       # Strict mode (auto build/lint/test pipeline)
mangolove --mode docs         # Documentation sync mode
```

### Skill Packs

```bash
# List built-in modes and installed skill packs
mangolove skill

# Install a skill pack from a git repository
mangolove skill install https://github.com/user/my-skill-pack.git

# Install from a local directory
mangolove skill install ./my-local-skill

# Create a new skill pack template
mangolove skill create my-custom-skill

# Update all installed skill packs
mangolove skill update

# Remove a skill pack
mangolove skill remove my-skill-pack
```

### Project Profiles

```bash
# List registered projects
mangolove projects

# Auto-generate profile by scanning project directory
mangolove profile auto

# Manually add a profile
mangolove profile add

# Export profile for team sharing
mangolove profile export my-project

# Import a shared .mangolove.md file
mangolove profile import .mangolove.md
```

### Work Logging

```bash
# Initialize the work log repository (one-time setup)
mangolove log init

# View work logs in the browser
mangolove log view

# Search work logs
mangolove log search "refactoring"

# Show recent session summary
mangolove log recent
```

### Options

All Claude Code options can be passed through directly:

```bash
mangolove --model opus           # Select model
mangolove --effort max           # Maximum effort mode
mangolove -r                     # Select and resume a session
mangolove --worktree             # Work in a separate worktree
```

## Directory Structure

```
~/.mangolove/
├── bin/
│   └── mangolove              # Main executable
├── lib/
│   ├── banner.sh              # UI banner
│   ├── work-logger.sh         # GitHub work logger
│   ├── profile-manager.sh     # Project profile manager
│   ├── plugin-manager.sh      # Plugin manager
│   └── skill-manager.sh       # Skill pack manager
├── prompts/
│   ├── system-prompt.md       # Core system prompt
│   └── modes/                 # Specialized prompt modes (9 modes)
├── skills/                    # Installed skill packs
├── completions/
│   ├── mangolove.bash         # Bash completions
│   └── _mangolove             # Zsh completions
├── plugins/                   # Plugin directory
├── projects/                  # Project profiles (auto-generated)
├── tests/                     # BATS test suite
├── logs/                      # Local work logs
├── config.sh                  # User configuration
├── install.sh                 # Installer
└── uninstall.sh               # Uninstaller
```

## Configuration

Customize settings in `~/.mangolove/config.sh`:

```bash
# GitHub work log repository (default: {your-username}/mangolove-work-logs)
# Set to "disabled" to turn off work logging entirely
MANGOLOVE_LOG_REPO=""

# Auto-log sessions to GitHub (true / false)
MANGOLOVE_AUTO_LOG=true

# Show banner on startup (true / false)
MANGOLOVE_SHOW_BANNER=true

# Extra text appended to system prompt (for personal preferences)
MANGOLOVE_EXTRA_PROMPT=""

# Default Claude model (leave empty to use Claude Code default)
MANGOLOVE_MODEL=""

# Default effort level (low / medium / high / max / auto)
MANGOLOVE_EFFORT=""
```

## Creating Skill Packs

A skill pack is a directory with a `skill.yaml` manifest and prompt files:

```
my-skill/
├── skill.yaml          # Manifest (name, version, description, author)
├── prompts/
│   └── main.md         # Prompt instructions (auto-loaded)
└── README.md           # Documentation
```

Example `skill.yaml`:
```yaml
name: my-skill
version: 1.0.0
description: Custom skill for domain-specific tasks
author: your-name
compatibility: ">=0.2.0"
```

Skill prompts are automatically injected into the system prompt when active.

## Creating Project Profiles

When running `mangolove` in a project directory for the first time, it will automatically suggest creating a profile.

To create one manually, add a file at `~/.mangolove/projects/{name}.md`:

```markdown
---
name: My Awesome Project
path: /Users/me/projects/awesome
tech_stack: [Java, Spring Boot, MySQL, Redis]
build_cmd: ./gradlew build
test_cmd: ./gradlew test
---

## Architecture
- Spring Boot multi-module project
- Hexagonal architecture

## Conventions
- Google Java Style Guide
- Conventional Commits
```

## Testing

MangoLove includes a comprehensive BATS test suite:

```bash
# Run all tests (requires bats-core)
bats tests/

# Run tests for a specific module
bats tests/profile-manager.bats
bats tests/plugin-manager.bats
bats tests/skill-manager.bats
```

## Update

```bash
mangolove update
```

Or manually:

```bash
cd ~/.mangolove && git pull origin main
```

## Contributing

1. Fork this repository
2. Create your feature branch (`git checkout -b feat/amazing-feature`)
3. Commit your changes (`git commit -m 'feat: add amazing feature'`)
4. Push to the branch (`git push origin feat/amazing-feature`)
5. Open a Pull Request

All contributions must pass the test suite (`bats tests/`) and ShellCheck (`shellcheck -x bin/mangolove lib/*.sh`).

## License

MIT License — see [LICENSE](LICENSE) for details.

---

**MangoLove** v0.3.0 — Built with Claude Code
