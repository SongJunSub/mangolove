#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove — Skill Manager Tests
# ─────────────────────────────────────────────

load test_helper

setup() {
    setup_test_env
    cp "$BATS_TEST_DIRNAME/../lib/skill-manager.sh" "$MANGOLOVE_DIR/lib/"
    mkdir -p "$MANGOLOVE_DIR/skills"
}

teardown() {
    teardown_test_env
}

# ─────────────────────────────────────────────
# list command
# ─────────────────────────────────────────────

@test "list: shows built-in modes" {
    run bash "$MANGOLOVE_DIR/lib/skill-manager.sh" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"Built-in Modes"* ]]
    [[ "$output" == *"review"* ]]
}

@test "list: shows no skill packs when empty" {
    run bash "$MANGOLOVE_DIR/lib/skill-manager.sh" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"No skill packs installed"* ]]
}

@test "list: shows installed skill pack" {
    mkdir -p "$MANGOLOVE_DIR/skills/my-skill/prompts"
    cat > "$MANGOLOVE_DIR/skills/my-skill/skill.yaml" << 'EOF'
name: my-skill
version: 2.0.0
description: A custom skill
author: testuser
EOF
    echo "# Skill prompt" > "$MANGOLOVE_DIR/skills/my-skill/prompts/main.md"

    run bash "$MANGOLOVE_DIR/lib/skill-manager.sh" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"my-skill"* ]]
    [[ "$output" == *"2.0.0"* ]]
    [[ "$output" == *"A custom skill"* ]]
    [[ "$output" == *"1 prompt"* ]]
}

# ─────────────────────────────────────────────
# create command
# ─────────────────────────────────────────────

@test "create: creates skill pack template" {
    run bash "$MANGOLOVE_DIR/lib/skill-manager.sh" create "test-skill"
    [ "$status" -eq 0 ]
    [ -f "$MANGOLOVE_DIR/skills/test-skill/skill.yaml" ]
    [ -f "$MANGOLOVE_DIR/skills/test-skill/prompts/main.md" ]
    [ -f "$MANGOLOVE_DIR/skills/test-skill/README.md" ]
}

@test "create: refuses duplicate skill" {
    bash "$MANGOLOVE_DIR/lib/skill-manager.sh" create "dup-skill"
    run bash "$MANGOLOVE_DIR/lib/skill-manager.sh" create "dup-skill"
    [ "$status" -eq 1 ]
    [[ "$output" == *"already exists"* ]]
}

@test "create: shows usage when no name given" {
    run bash "$MANGOLOVE_DIR/lib/skill-manager.sh" create ""
    [ "$status" -eq 1 ]
}

# ─────────────────────────────────────────────
# remove command
# ─────────────────────────────────────────────

@test "remove: removes installed skill" {
    mkdir -p "$MANGOLOVE_DIR/skills/rm-skill"
    echo "name: rm-skill" > "$MANGOLOVE_DIR/skills/rm-skill/skill.yaml"

    run bash "$MANGOLOVE_DIR/lib/skill-manager.sh" remove "rm-skill"
    [ "$status" -eq 0 ]
    [ ! -d "$MANGOLOVE_DIR/skills/rm-skill" ]
}

@test "remove: fails for non-existent skill" {
    run bash "$MANGOLOVE_DIR/lib/skill-manager.sh" remove "nonexistent"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

# ─────────────────────────────────────────────
# install command
# ─────────────────────────────────────────────

@test "install: shows usage when no source given" {
    run bash "$MANGOLOVE_DIR/lib/skill-manager.sh" install ""
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "install: installs from local directory" {
    local src="$TEST_DIR/local-skill-src"
    mkdir -p "$src/prompts"
    echo "name: local-skill" > "$src/skill.yaml"
    echo "# Prompt" > "$src/prompts/main.md"

    run bash "$MANGOLOVE_DIR/lib/skill-manager.sh" install "$src"
    [ "$status" -eq 0 ]
    [ -d "$MANGOLOVE_DIR/skills/local-skill-src" ]
}

@test "install: rejects invalid skill pack (no manifest)" {
    local src=$(mktemp -d)
    echo "not a skill" > "$src/random.txt"

    run bash "$MANGOLOVE_DIR/lib/skill-manager.sh" install "$src"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid skill pack"* ]]
    rm -rf "$src"
}

# ─────────────────────────────────────────────
# prompts command
# ─────────────────────────────────────────────

@test "prompts: loads prompt content from skills" {
    mkdir -p "$MANGOLOVE_DIR/skills/prompt-skill/prompts"
    echo "name: prompt-skill" > "$MANGOLOVE_DIR/skills/prompt-skill/skill.yaml"
    echo "Always use strict typing." > "$MANGOLOVE_DIR/skills/prompt-skill/prompts/main.md"

    run bash "$MANGOLOVE_DIR/lib/skill-manager.sh" prompts
    [ "$status" -eq 0 ]
    [[ "$output" == *"strict typing"* ]]
}

@test "prompts: skips disabled skills" {
    mkdir -p "$MANGOLOVE_DIR/skills/disabled-skill/prompts"
    echo "name: disabled-skill" > "$MANGOLOVE_DIR/skills/disabled-skill/skill.yaml"
    echo "SHOULD NOT APPEAR" > "$MANGOLOVE_DIR/skills/disabled-skill/prompts/main.md"
    echo "enabled=false" > "$MANGOLOVE_DIR/skills/disabled-skill/config"

    run bash "$MANGOLOVE_DIR/lib/skill-manager.sh" prompts
    [ "$status" -eq 0 ]
    [[ "$output" != *"SHOULD NOT APPEAR"* ]]
}

@test "prompts: empty when no skills installed" {
    run bash "$MANGOLOVE_DIR/lib/skill-manager.sh" prompts
    [ "$status" -eq 0 ]
}
