#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove — Main CLI Tests
# ─────────────────────────────────────────────

load test_helper

setup() {
    setup_test_env
    # Copy main executable
    cp "$BATS_TEST_DIRNAME/../bin/mangolove" "$MANGOLOVE_DIR/bin/mangolove"
    chmod +x "$MANGOLOVE_DIR/bin/mangolove"
}

teardown() {
    teardown_test_env
}

# ─────────────────────────────────────────────
# version
# ─────────────────────────────────────────────

@test "version: displays version string" {
    run bash "$MANGOLOVE_DIR/bin/mangolove" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"MangoLove"* ]]
    [[ "$output" == *"0.5.0"* ]]
}

@test "version: -v shorthand works" {
    run bash "$MANGOLOVE_DIR/bin/mangolove" -v
    [ "$status" -eq 0 ]
    [[ "$output" == *"MangoLove"* ]]
}

# ─────────────────────────────────────────────
# help
# ─────────────────────────────────────────────

@test "help: displays usage information" {
    run bash "$MANGOLOVE_DIR/bin/mangolove" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"Commands"* ]]
    [[ "$output" == *"Modes"* ]]
    [[ "$output" == *"Options"* ]]
}

@test "help: --help flag works" {
    run bash "$MANGOLOVE_DIR/bin/mangolove" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "help: -h shorthand works" {
    run bash "$MANGOLOVE_DIR/bin/mangolove" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "help: lists all available modes" {
    run bash "$MANGOLOVE_DIR/bin/mangolove" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"review"* ]]
    [[ "$output" == *"debug"* ]]
    [[ "$output" == *"refactor"* ]]
    [[ "$output" == *"security"* ]]
    [[ "$output" == *"plan"* ]]
    [[ "$output" == *"pr"* ]]
}

@test "help: lists all subcommands" {
    run bash "$MANGOLOVE_DIR/bin/mangolove" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"projects"* ]]
    [[ "$output" == *"profile"* ]]
    [[ "$output" == *"plugin"* ]]
    [[ "$output" == *"log"* ]]
    [[ "$output" == *"update"* ]]
    [[ "$output" == *"doctor"* ]]
}

# ─────────────────────────────────────────────
# doctor
# ─────────────────────────────────────────────

@test "doctor: runs without error" {
    run bash "$MANGOLOVE_DIR/bin/mangolove" doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"Doctor"* ]]
}

@test "doctor: checks for Git" {
    run bash "$MANGOLOVE_DIR/bin/mangolove" doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"Git"* ]]
}

@test "doctor: reports MangoLove component status" {
    run bash "$MANGOLOVE_DIR/bin/mangolove" doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"System prompt"* ]]
    [[ "$output" == *"Banner"* ]]
    [[ "$output" == *"Work logger"* ]]
    [[ "$output" == *"Profile manager"* ]]
}

@test "doctor: reports profile and mode counts" {
    run bash "$MANGOLOVE_DIR/bin/mangolove" doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"Project profiles"* ]]
    [[ "$output" == *"Modes"* ]]
}

# ─────────────────────────────────────────────
# mode validation
# ─────────────────────────────────────────────

@test "mode: rejects unknown mode" {
    run bash "$MANGOLOVE_DIR/bin/mangolove" --mode nonexistent
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown mode"* ]]
    [[ "$output" == *"Available modes"* ]]
}

@test "mode: shows usage when --mode has no argument" {
    run bash "$MANGOLOVE_DIR/bin/mangolove" --mode
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

# ─────────────────────────────────────────────
# projects subcommand
# ─────────────────────────────────────────────

@test "projects: delegates to profile-manager list" {
    run bash "$MANGOLOVE_DIR/bin/mangolove" projects
    [ "$status" -eq 0 ]
    [[ "$output" == *"Project Profiles"* ]]
}

# ─────────────────────────────────────────────
# log subcommand
# ─────────────────────────────────────────────

@test "log: shows usage with no arguments" {
    run bash "$MANGOLOVE_DIR/bin/mangolove" log
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

# ─────────────────────────────────────────────
# plugin subcommand
# ─────────────────────────────────────────────

@test "plugin: lists plugins with no arguments" {
    run bash "$MANGOLOVE_DIR/bin/mangolove" plugin
    [ "$status" -eq 0 ]
    [[ "$output" == *"Plugins"* ]]
}

@test "plugins: alias works" {
    run bash "$MANGOLOVE_DIR/bin/mangolove" plugins
    [ "$status" -eq 0 ]
    [[ "$output" == *"Plugins"* ]]
}
