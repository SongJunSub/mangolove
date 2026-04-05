# MangoLove

**Autonomous Development Agent** — Built on [Claude Code](https://claude.ai/claude-code)

MangoLove is an autonomous development agent built on top of Claude Code. It remembers project-specific context and handles the full workflow from analysis to implementation.

> **Origin of the name**
> Named after two Jindo dogs.
> - **Mango** — a white Jindo with scattered golden spots
> - **Sarang (Love)** — a pure white Jindo
>
> Mango + Love = **MangoLove**

## Features

- **Autonomous Execution** — Automatically performs analysis, planning, implementation, and verification for given tasks
- **Project Profiles** — Remembers and applies per-project tech stacks, conventions, and architecture
- **Work Logging** — Records work history to a GitHub private repository
- **Prompt Modes** — Specialized modes for debugging, code review, refactoring, PR creation, security audit, and planning
- **Shell Completions** — Tab completion support for Bash and Zsh
- **Plugin System** — Extensible architecture via plugins
- **Claude Code Compatible** — Full access to all Claude Code features (`/commands`, MCP, hooks, etc.)

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

### Project Profiles

```bash
# List registered projects
mangolove projects

# Manually add a profile
mangolove profile add

# Running in a project directory for the first time will prompt profile creation
cd ~/my-project && mangolove
```

### Work Logging

```bash
# Initialize the work log repository (one-time setup)
mangolove log init

# View work logs in the browser
mangolove log view
```

### Options

```bash
mangolove help
```

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
│   └── plugin-manager.sh      # Plugin manager
├── prompts/
│   ├── system-prompt.md       # Core system prompt
│   └── modes/                 # Specialized prompt modes
│       ├── debug.md
│       ├── plan.md
│       ├── pr.md
│       ├── refactor.md
│       ├── review.md
│       └── security.md
├── completions/
│   ├── mangolove.bash         # Bash completions
│   └── _mangolove             # Zsh completions
├── plugins/                   # Plugin directory
├── projects/                  # Project profiles (auto-generated)
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

## License

MIT License — see [LICENSE](LICENSE) for details.

---

**MangoLove** v0.2.0 — Built with Claude Code
