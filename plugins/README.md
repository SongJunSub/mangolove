# MangoLove Plugins

Each plugin lives in its own directory under `~/.mangolove/plugins/`.

## Plugin Structure
```
plugins/
└── my-plugin/
    ├── plugin.sh    # Plugin script (required)
    └── config       # Plugin config (optional, auto-created)
```

## Available Hooks

| Hook | When | Use Case |
|------|------|----------|
| `on_session_start` | Before Claude Code launches | Setup, notifications |
| `on_session_end` | After Claude Code exits | Cleanup, reporting |
| `on_prompt_build` | During system prompt build | Add custom instructions (stdout) |
| `on_profile_load` | When a project profile loads | Project-specific setup |

## Quick Start
```bash
mangolove plugin create my-plugin
# Edit ~/.mangolove/plugins/my-plugin/plugin.sh
```

## Example: Slack Notification Plugin
```bash
#!/bin/bash
# Description: Notify Slack on session events
# Version: 1.0.0

on_session_start() {
    curl -s -X POST "$SLACK_WEBHOOK" \
        -d "{\"text\":\"🥭 MangoLove session started in $(pwd)\"}" > /dev/null
}

on_session_end() {
    curl -s -X POST "$SLACK_WEBHOOK" \
        -d "{\"text\":\"🥭 MangoLove session ended\"}" > /dev/null
}
```
