#!/bin/bash
# ─────────────────────────────────────────────
# MangoLove — Session Memory
# Persist context across Claude Code sessions
# ─────────────────────────────────────────────

set -o pipefail

MANGOLOVE_DIR="${MANGOLOVE_DIR:-$HOME/.mangolove}"
SESSIONS_DIR="$MANGOLOVE_DIR/sessions"

# Colors
R='\033[0m'
B='\033[1m'
DIM='\033[2m'
O='\033[38;5;208m'
G='\033[38;5;113m'
C='\033[38;5;117m'
Y='\033[38;5;220m'

# ─────────────────────────────────────────────
# Save session context
# Called at session end, captures what happened
# ─────────────────────────────────────────────
save_session() {
    local project_dir
    project_dir=$(pwd)
    local project_name
    project_name=$(basename "$project_dir")
    local session_file="$SESSIONS_DIR/${project_name}.md"

    mkdir -p "$SESSIONS_DIR"

    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local branch=""
    branch=$(git branch --show-current 2>/dev/null) || true

    # Collect recent git activity in this session
    local recent_commits=""
    local session_start_file="$MANGOLOVE_DIR/logs/.session_start"
    if [ -f "$session_start_file" ]; then
        local start_time
        start_time=$(cat "$session_start_file" 2>/dev/null) || true
        if [ -n "$start_time" ] && [ -d ".git" ]; then
            recent_commits=$(git log --after="$start_time" --format="- %h %s" --no-merges 2>/dev/null | head -20) || true
        fi
    fi

    # Collect modified files (uncommitted)
    local modified_files=""
    if [ -d ".git" ]; then
        modified_files=$(git diff --name-only HEAD 2>/dev/null | head -20) || true
    fi

    # Build session summary
    cat > "$session_file" << EOF
---
project: ${project_name}
path: ${project_dir}
branch: ${branch}
last_session: ${timestamp}
---

## Last Session Summary

**Date**: ${timestamp}
**Directory**: \`${project_dir}\`
**Branch**: ${branch:-N/A}
EOF

    if [ -n "$recent_commits" ]; then
        cat >> "$session_file" << EOF

### Commits Made
${recent_commits}
EOF
    fi

    if [ -n "$modified_files" ]; then
        cat >> "$session_file" << EOF

### Uncommitted Changes
$(echo "$modified_files" | sed 's/^/- /')
EOF
    fi

    # Check for failing tests
    if [ -f "CLAUDE.md" ]; then
        local test_cmd
        test_cmd=$(grep "Test:" "CLAUDE.md" 2>/dev/null | sed 's/.*`\(.*\)`.*/\1/' | head -1) || true
        if [ -n "$test_cmd" ]; then
            cat >> "$session_file" << EOF

### Test Command
\`${test_cmd}\`
EOF
        fi
    fi
}

# ─────────────────────────────────────────────
# Load session context for current project
# Returns markdown to inject into system prompt
# ─────────────────────────────────────────────
load_session() {
    local project_dir
    project_dir=$(pwd)
    local project_name
    project_name=$(basename "$project_dir")
    local session_file="$SESSIONS_DIR/${project_name}.md"

    if [ ! -f "$session_file" ]; then
        return 1
    fi

    # Check if session is from the same project path
    local saved_path
    saved_path=$(grep "^path:" "$session_file" 2>/dev/null | sed 's/^path: *//') || true
    if [ "$saved_path" != "$project_dir" ]; then
        return 1
    fi

    cat "$session_file"
}

# ─────────────────────────────────────────────
# Show session info (for mangolove resume)
# ─────────────────────────────────────────────
show_session() {
    local project_dir
    project_dir=$(pwd)
    local project_name
    project_name=$(basename "$project_dir")
    local session_file="$SESSIONS_DIR/${project_name}.md"

    if [ ! -f "$session_file" ]; then
        echo -e "  ${DIM}No previous session found for this directory.${R}"
        return 1
    fi

    echo ""
    echo -e "${O}${B}MangoLove — Session Memory${R}"
    echo -e "${DIM}──────────────────────────────────────${R}"

    local last_date
    last_date=$(grep "^last_session:" "$session_file" 2>/dev/null | sed 's/^last_session: *//') || true
    local branch
    branch=$(grep "^branch:" "$session_file" 2>/dev/null | sed 's/^branch: *//') || true

    echo -e "  Project : ${B}${project_name}${R}"
    echo -e "  Last    : ${C}${last_date}${R}"
    echo -e "  Branch  : ${DIM}${branch:-N/A}${R}"

    # Show commits
    local commits
    commits=$(sed -n '/### Commits Made/,/^###\|^$/p' "$session_file" 2>/dev/null | grep "^- " | head -5) || true
    if [ -n "$commits" ]; then
        echo ""
        echo -e "  ${DIM}Recent commits:${R}"
        echo "$commits" | sed 's/^/    /'
    fi

    # Show uncommitted
    local uncommitted
    uncommitted=$(sed -n '/### Uncommitted Changes/,/^###\|^$/p' "$session_file" 2>/dev/null | grep "^- " | head -5) || true
    if [ -n "$uncommitted" ]; then
        echo ""
        echo -e "  ${Y}Uncommitted files:${R}"
        echo "$uncommitted" | sed 's/^/    /'
    fi

    echo ""
    echo -e "${DIM}──────────────────────────────────────${R}"
    echo ""
}

# ─────────────────────────────────────────────
# List all saved sessions
# ─────────────────────────────────────────────
list_sessions() {
    echo ""
    echo -e "${O}${B}MangoLove — Saved Sessions${R}"
    echo -e "${DIM}──────────────────────────────────────${R}"

    mkdir -p "$SESSIONS_DIR"
    local count=0

    for session_file in "$SESSIONS_DIR"/*.md; do
        [ ! -f "$session_file" ] && continue

        local name
        name=$(basename "$session_file" .md)
        local last_date
        last_date=$(grep "^last_session:" "$session_file" 2>/dev/null | sed 's/^last_session: *//') || true
        local path
        path=$(grep "^path:" "$session_file" 2>/dev/null | sed 's/^path: *//') || true

        echo -e "  ${G}*${R} ${B}${name}${R} — ${DIM}${last_date}${R}"
        echo -e "    ${DIM}${path}${R}"
        count=$((count + 1))
    done

    if [ $count -eq 0 ]; then
        echo -e "  ${DIM}No saved sessions.${R}"
    fi

    echo ""
    echo -e "${DIM}──────────────────────────────────────${R}"
    echo ""
}

# ─────────────────────────────────────────────
# Clear session for current project
# ─────────────────────────────────────────────
clear_session() {
    local project_name
    project_name=$(basename "$(pwd)")
    local session_file="$SESSIONS_DIR/${project_name}.md"

    if [ -f "$session_file" ]; then
        rm "$session_file"
        echo -e "  ${G}Session cleared:${R} ${project_name}"
    else
        echo -e "  ${DIM}No session to clear.${R}"
    fi
}

# ─────────────────────────────────────────────
# Entrypoint
# ─────────────────────────────────────────────
case "${1:-}" in
    save)    save_session ;;
    load)    load_session ;;
    show)    show_session ;;
    list)    list_sessions ;;
    clear)   clear_session ;;
    *)       show_session ;;
esac
