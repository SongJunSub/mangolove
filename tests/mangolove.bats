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

@test "doctor: reports installed project quality gate in cwd" {
    local proj="$TEST_DIR/doctor-gate"
    mkdir -p "$proj/.mangolove/hooks"
    cp "$MANGOLOVE_DIR/lib/quality-gate.sh" "$proj/.mangolove/hooks/quality-gate.sh"
    cd "$proj"
    run bash "$MANGOLOVE_DIR/bin/mangolove" doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"Project gate"* ]]
    [[ "$output" == *"Quality gate installed"* ]]
}

@test "doctor: reports a committed gate as version-controlled" {
    local proj="$TEST_DIR/doctor-gate-tracked"
    mkdir -p "$proj/.mangolove/hooks"
    cp "$MANGOLOVE_DIR/lib/quality-gate.sh" "$proj/.mangolove/hooks/quality-gate.sh"
    git -C "$proj" init -q
    git -C "$proj" -c user.email=t@t.com -c user.name=t add .mangolove
    git -C "$proj" -c user.email=t@t.com -c user.name=t commit -qm gate
    cd "$proj"
    run bash "$MANGOLOVE_DIR/bin/mangolove" doctor
    [[ "$output" == *"version-controlled"* ]]
}

@test "doctor: warns when the gate is not committed" {
    local proj="$TEST_DIR/doctor-gate-uncommitted"
    mkdir -p "$proj/.mangolove/hooks"
    cp "$MANGOLOVE_DIR/lib/quality-gate.sh" "$proj/.mangolove/hooks/quality-gate.sh"
    git -C "$proj" init -q
    cd "$proj"
    run bash "$MANGOLOVE_DIR/bin/mangolove" doctor
    [[ "$output" == *"not committed"* ]]
}

@test "doctor: warns when .mangolove is gitignored (silently disabled)" {
    local proj="$TEST_DIR/doctor-gate-ignored"
    mkdir -p "$proj/.mangolove/hooks"
    cp "$MANGOLOVE_DIR/lib/quality-gate.sh" "$proj/.mangolove/hooks/quality-gate.sh"
    git -C "$proj" init -q
    echo '.mangolove/' > "$proj/.gitignore"
    cd "$proj"
    run bash "$MANGOLOVE_DIR/bin/mangolove" doctor
    [[ "$output" == *"gitignored"* ]]
}

@test "doctor: reports session gates enabled" {
    cd "$TEST_DIR"
    run bash "$MANGOLOVE_DIR/bin/mangolove" doctor
    [[ "$output" == *"Session gates"* ]]
}

@test "session-settings: generate_session_settings writes valid JSON with both hooks" {
    command -v python3 >/dev/null 2>&1 || skip "needs python3"
    local out="$TEST_DIR/session-settings.json"
    run bash -c "source '$MANGOLOVE_DIR/bin/mangolove'; generate_session_settings '$out'"
    [ "$status" -eq 0 ]
    [ -f "$out" ]
    python3 -c "import json; json.load(open('$out'))"
    grep -q "PreToolUse" "$out"
    grep -q "irreversible-guard.sh" "$out"
    grep -q "quality-gate.sh" "$out"
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

# ── init / sync 가 project-init 으로 배선돼 있는가 (README 가 문서화 — claude 로 떨어지면 안 됨) ──

@test "init: dispatches to project-init and scaffolds CLAUDE.md (not passed to claude)" {
    cp "$BATS_TEST_DIRNAME/../bin/mangolove" "$MANGOLOVE_DIR/bin/mangolove"
    chmod +x "$MANGOLOVE_DIR/bin/mangolove"
    local proj; proj=$(create_fake_project "init-dispatch")
    echo '{"name":"app","scripts":{"test":"jest"}}' > "$proj/package.json"
    cd "$proj"
    run bash "$MANGOLOVE_DIR/bin/mangolove" init
    [ "$status" -eq 0 ]
    [ -f "$proj/CLAUDE.md" ]
}

@test "init --strict: scaffolds gate hooks via the wired command" {
    cp "$BATS_TEST_DIRNAME/../bin/mangolove" "$MANGOLOVE_DIR/bin/mangolove"
    chmod +x "$MANGOLOVE_DIR/bin/mangolove"
    local proj; proj=$(create_fake_project "init-strict-dispatch")
    echo '{"name":"app","scripts":{"test":"jest","lint":"eslint ."}}' > "$proj/package.json"
    echo '{}' > "$proj/.eslintrc.json"
    cd "$proj"
    run bash "$MANGOLOVE_DIR/bin/mangolove" init --strict
    [ "$status" -eq 0 ]
    [ -f "$proj/.mangolove/hooks/irreversible-guard.sh" ]
}

@test "sync: dispatches to project-init (recognized command, not a claude prompt)" {
    cp "$BATS_TEST_DIRNAME/../bin/mangolove" "$MANGOLOVE_DIR/bin/mangolove"
    chmod +x "$MANGOLOVE_DIR/bin/mangolove"
    local proj; proj=$(create_fake_project "sync-dispatch")
    echo '{"name":"app"}' > "$proj/package.json"
    cd "$proj"
    bash "$MANGOLOVE_DIR/bin/mangolove" init >/dev/null 2>&1
    run bash "$MANGOLOVE_DIR/bin/mangolove" sync
    [ "$status" -eq 0 ]
}
