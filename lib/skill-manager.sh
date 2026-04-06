#!/bin/bash
# ─────────────────────────────────────────────
# MangoLove — Skill Manager
# Install, manage, and compose skill packs
# ─────────────────────────────────────────────

set -eo pipefail

MANGOLOVE_DIR="${MANGOLOVE_DIR:-$HOME/.mangolove}"
SKILLS_DIR="$MANGOLOVE_DIR/skills"

# shellcheck source=colors.sh
source "${MANGOLOVE_DIR}/lib/colors.sh"

# ─────────────────────────────────────────────
# List installed skills
# ─────────────────────────────────────────────
list_skills() {
    echo ""
    echo -e "${O}${B}MangoLove — Skills${R}"
    echo -e "${DIM}──────────────────────────────────────${R}"

    # Built-in modes
    echo -e "  ${DIM}Built-in Modes:${R}"
    for mode_file in "$MANGOLOVE_DIR/prompts/modes"/*.md; do
        [ ! -f "$mode_file" ] && continue
        local name
        name=$(basename "$mode_file" .md)
        local desc
        desc=$(head -1 "$mode_file" | sed 's/^# MangoLove — //;s/ Mode$//')
        echo -e "    ${G}*${R} ${B}${name}${R} ${DIM}(built-in)${R} — ${desc}"
    done

    echo ""

    # Installed skill packs
    local skill_count=0
    echo -e "  ${DIM}Installed Skill Packs:${R}"
    for skill_dir in "$SKILLS_DIR"/*/; do
        [ ! -d "$skill_dir" ] && continue
        local manifest="$skill_dir/skill.yaml"
        [ ! -f "$manifest" ] && manifest="$skill_dir/skill.md"
        [ ! -f "$manifest" ] && continue

        local skill_name
        skill_name=$(basename "$skill_dir")
        local description=""
        local version=""
        local author=""
        description=$(grep "^description:" "$manifest" 2>/dev/null | sed 's/^description: *//')
        version=$(grep "^version:" "$manifest" 2>/dev/null | sed 's/^version: *//')
        author=$(grep "^author:" "$manifest" 2>/dev/null | sed 's/^author: *//')

        echo -e "    ${C}+${R} ${B}${skill_name}${R} ${DIM}v${version}${R} — ${description}"
        [ -n "$author" ] && echo -e "      ${DIM}by ${author}${R}"

        # List skill's modes/prompts
        local prompt_count=0
        for pf in "$skill_dir/prompts"/*.md; do
            [ ! -f "$pf" ] && continue
            prompt_count=$((prompt_count + 1))
        done
        [ $prompt_count -gt 0 ] && echo -e "      ${DIM}${prompt_count} prompt(s)${R}"

        echo ""
        skill_count=$((skill_count + 1))
    done

    if [ $skill_count -eq 0 ]; then
        echo -e "    ${DIM}No skill packs installed.${R}"
        echo -e "    ${DIM}Install with: mangolove skill install <git-url>${R}"
        echo ""
    fi

    echo -e "${DIM}──────────────────────────────────────${R}"
    echo ""
}

# ─────────────────────────────────────────────
# Install a skill pack from git URL
# ─────────────────────────────────────────────
install_skill() {
    local source="$1"
    if [ -z "$source" ]; then
        echo "Usage: mangolove skill install <git-url|path>"
        return 1
    fi

    # Determine skill name from URL
    local skill_name
    skill_name=$(basename "$source" .git)

    local target_dir="$SKILLS_DIR/$skill_name"
    if [ -d "$target_dir" ]; then
        echo -e "  ${Y}Skill already installed:${R} ${skill_name}"
        echo -e "  ${DIM}Use 'mangolove skill update ${skill_name}' to update.${R}"
        return 1
    fi

    echo -e "  Installing skill: ${B}${skill_name}${R}..."

    if [[ "$source" == http* ]] || [[ "$source" == git@* ]]; then
        git clone "$source" "$target_dir" 2>/dev/null
    elif [ -d "$source" ]; then
        cp -r "$source" "$target_dir"
    else
        echo -e "  ${RED}Invalid source:${R} ${source}"
        return 1
    fi

    # Validate
    if [ ! -f "$target_dir/skill.yaml" ] && [ ! -f "$target_dir/skill.md" ]; then
        echo -e "  ${RED}Invalid skill pack:${R} missing skill.yaml or skill.md"
        rm -rf "$target_dir"
        return 1
    fi

    echo -e "  ${G}Skill installed:${R} ${skill_name}"

    # Show skill info
    local description=""
    description=$(grep "^description:" "$target_dir/skill.yaml" "$target_dir/skill.md" 2>/dev/null | head -1 | sed 's/^.*description: *//') || true
    [ -n "$description" ] && echo -e "  ${DIM}${description}${R}"
    echo ""
}

# ─────────────────────────────────────────────
# Remove a skill pack
# ─────────────────────────────────────────────
remove_skill() {
    local skill_name="$1"
    if [ -z "$skill_name" ]; then
        echo "Usage: mangolove skill remove <name>"
        return 1
    fi

    local target_dir="$SKILLS_DIR/$skill_name"
    if [ ! -d "$target_dir" ]; then
        echo -e "  ${RED}Skill not found:${R} ${skill_name}"
        return 1
    fi

    rm -rf "$target_dir"
    echo -e "  ${G}Skill removed:${R} ${skill_name}"
}

# ─────────────────────────────────────────────
# Update a skill pack
# ─────────────────────────────────────────────
update_skill() {
    local skill_name="$1"
    if [ -z "$skill_name" ]; then
        # Update all
        for skill_dir in "$SKILLS_DIR"/*/; do
            [ ! -d "$skill_dir/.git" ] && continue
            local name
            name=$(basename "$skill_dir")
            echo -e "  Updating ${B}${name}${R}..."
            (cd "$skill_dir" && git pull origin main 2>/dev/null) || true
        done
        return 0
    fi

    local target_dir="$SKILLS_DIR/$skill_name"
    if [ ! -d "$target_dir" ]; then
        echo -e "  ${RED}Skill not found:${R} ${skill_name}"
        return 1
    fi

    if [ -d "$target_dir/.git" ]; then
        (cd "$target_dir" && git pull origin main 2>/dev/null)
        echo -e "  ${G}Updated:${R} ${skill_name}"
    else
        echo -e "  ${Y}Cannot update:${R} ${skill_name} (not a git repository)"
    fi
}

# ─────────────────────────────────────────────
# Create a new skill pack template
# ─────────────────────────────────────────────
create_skill() {
    local skill_name="$1"
    if [ -z "$skill_name" ]; then
        echo "Usage: mangolove skill create <name>"
        return 1
    fi

    local target_dir="$SKILLS_DIR/$skill_name"
    if [ -d "$target_dir" ]; then
        echo -e "  ${Y}Skill already exists:${R} ${skill_name}"
        return 1
    fi

    mkdir -p "$target_dir/prompts"

    cat > "$target_dir/skill.yaml" << EOF
name: ${skill_name}
version: 1.0.0
description: Custom skill pack
author: $(git config user.name 2>/dev/null || echo "unknown")
compatibility: ">=0.2.0"
EOF

    cat > "$target_dir/prompts/main.md" << EOF
# ${skill_name}

## Instructions
<!-- Add skill-specific instructions here -->

## Rules
<!-- Add rules the agent should follow -->

## Output Format
<!-- Define expected output format -->
EOF

    cat > "$target_dir/README.md" << EOF
# ${skill_name}

A custom MangoLove skill pack.

## Installation

\`\`\`bash
mangolove skill install /path/to/${skill_name}
\`\`\`

## Usage

This skill's prompts are automatically loaded when active.
EOF

    echo -e "  ${G}Skill created:${R} ${target_dir}"
    echo -e "  ${DIM}Edit skill.yaml and prompts/main.md to customize.${R}"
    echo ""
}

# ─────────────────────────────────────────────
# Load skill prompts for system prompt building
# ─────────────────────────────────────────────
load_skill_prompts() {
    local combined=""

    for skill_dir in "$SKILLS_DIR"/*/; do
        [ ! -d "$skill_dir" ] && continue

        # Check if skill has a config with enabled=false
        if [ -f "$skill_dir/config" ] && grep -q "^enabled=false" "$skill_dir/config" 2>/dev/null; then
            continue
        fi

        for prompt_file in "$skill_dir/prompts"/*.md; do
            [ ! -f "$prompt_file" ] && continue
            local content
            content=$(cat "$prompt_file")
            if [ -n "$content" ]; then
                combined="${combined}

${content}"
            fi
        done
    done

    echo "$combined"
}

# ─────────────────────────────────────────────
# Entrypoint
# ─────────────────────────────────────────────
case "${1:-}" in
    list)    list_skills ;;
    install) install_skill "$2" ;;
    remove)  remove_skill "$2" ;;
    update)  update_skill "${2:-}" ;;
    create)  create_skill "$2" ;;
    prompts) load_skill_prompts ;;
    *)       list_skills ;;
esac
