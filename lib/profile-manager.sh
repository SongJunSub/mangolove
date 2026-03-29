#!/bin/bash
# ─────────────────────────────────────────────
# 🥭 MangoLove — Project Profile Manager
# ─────────────────────────────────────────────

MANGOLOVE_DIR="${MANGOLOVE_DIR:-$HOME/.mangolove}"
PROJECTS_DIR="$MANGOLOVE_DIR/projects"

# Colors
R='\033[0m'
B='\033[1m'
DIM='\033[2m'
Y='\033[38;5;220m'
O='\033[38;5;208m'
G='\033[38;5;113m'
C='\033[38;5;117m'
W='\033[38;5;255m'
RED='\033[38;5;203m'

list_profiles() {
    echo ""
    echo -e "${O}${B}🥭 MangoLove — Project Profiles${R}"
    echo -e "${DIM}──────────────────────────────────────${R}"

    local count=0
    for profile in "$PROJECTS_DIR"/*.md; do
        [ "$(basename "$profile")" = "README.md" ] && continue
        [ ! -f "$profile" ] && continue

        local name=$(grep "^name:" "$profile" 2>/dev/null | sed 's/^name: *//')
        local path=$(grep "^path:" "$profile" 2>/dev/null | sed 's/^path: *//')
        local stack=$(grep "^tech_stack:" "$profile" 2>/dev/null | sed 's/^tech_stack: *//')

        # Check if path exists
        local status="${G}✓${R}"
        [ ! -d "$path" ] && status="${RED}✗ path not found${R}"

        echo -e "  ${G}▸${R} ${B}${name}${R} ${status}"
        echo -e "    ${DIM}Path :${R} ${path}"
        echo -e "    ${DIM}Stack:${R} ${stack}"
        echo ""
        count=$((count + 1))
    done

    if [ $count -eq 0 ]; then
        echo -e "  ${DIM}No profiles yet.${R}"
        echo -e "  ${DIM}Start mangolove in a project directory to auto-create one.${R}"
        echo ""
    fi

    echo -e "${DIM}──────────────────────────────────────${R}"
    echo -e "  ${DIM}Profiles directory: ${PROJECTS_DIR}/${R}"
    echo ""
}

add_profile() {
    echo ""
    echo -e "${O}${B}🥭 MangoLove — Add Project Profile${R}"
    echo -e "${DIM}──────────────────────────────────────${R}"
    echo ""

    read -p "  Project name: " proj_name
    read -p "  Project path [$(pwd)]: " proj_path
    proj_path="${proj_path:-$(pwd)}"
    read -p "  Tech stack (comma-separated): " proj_stack
    read -p "  Build command [./gradlew build]: " proj_build
    proj_build="${proj_build:-./gradlew build}"
    read -p "  Test command [./gradlew test]: " proj_test
    proj_test="${proj_test:-./gradlew test}"

    local filename=$(echo "$proj_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9-]//g')

    mkdir -p "$PROJECTS_DIR"
    cat > "$PROJECTS_DIR/${filename}.md" << EOF
---
name: ${proj_name}
path: ${proj_path}
tech_stack: [${proj_stack}]
build_cmd: ${proj_build}
test_cmd: ${proj_test}
---

## Architecture
<!-- Describe the project architecture -->

## Conventions
<!-- Describe coding conventions -->

## Notes
<!-- Any important notes for the agent -->
EOF

    echo ""
    echo -e "  ${G}✅ Profile created:${R} ${PROJECTS_DIR}/${filename}.md"
    echo -e "  ${DIM}Edit the file to add architecture and convention details.${R}"
    echo ""
}

remove_profile() {
    local name="$1"
    if [ -z "$name" ]; then
        echo "Usage: mangolove profile remove <name>"
        return 1
    fi

    local file="$PROJECTS_DIR/${name}.md"
    if [ -f "$file" ]; then
        rm "$file"
        echo -e "  ${G}✅ Profile removed:${R} ${name}"
    else
        echo -e "  ${RED}✗ Profile not found:${R} ${name}"
    fi
}

# Load project context for current directory
load_project_context() {
    local current_dir=$(pwd)

    for profile in "$PROJECTS_DIR"/*.md; do
        [ "$(basename "$profile")" = "README.md" ] && continue
        [ ! -f "$profile" ] && continue

        local profile_path=$(grep "^path:" "$profile" 2>/dev/null | sed 's/^path: *//')
        if [ -n "$profile_path" ] && [[ "$current_dir" == "$profile_path"* ]]; then
            cat "$profile"
            return 0
        fi
    done

    return 1
}

# Entrypoint
case "${1:-}" in
    list)    list_profiles ;;
    add)     add_profile ;;
    remove)  remove_profile "$2" ;;
    load)    load_project_context ;;
    *)       list_profiles ;;
esac
