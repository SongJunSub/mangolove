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
    # 버전은 bin/mangolove 의 MANGOLOVE_VERSION 이 단일 출처 — 하드코딩하면 릴리스마다 깨진다.
    local expected_version
    expected_version=$(grep -m1 '^MANGOLOVE_VERSION=' "$BATS_TEST_DIRNAME/../bin/mangolove" | cut -d'"' -f2)
    [ -n "$expected_version" ]
    [[ "$output" == *"$expected_version"* ]]
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

@test "session-settings: review gate injects PreToolUse+PostToolUse pair when on, nothing when off" {
    command -v python3 >/dev/null 2>&1 || skip "needs python3"
    local on="$TEST_DIR/on.json" off="$TEST_DIR/off.json"
    run bash -c "source '$MANGOLOVE_DIR/bin/mangolove'
      MANGOLOVE_REVIEW_GATE=on  generate_session_settings '$on'
      MANGOLOVE_REVIEW_GATE=off generate_session_settings '$off'"
    [ "$status" -eq 0 ]
    # 두 훅은 짝이어야 한다 — record 없이 pretooluse 만 있으면 원장이 비어 항상 차단된다.
    python3 -c "import json; json.load(open('$on'))"
    grep -qF 'review-gate.sh\" pretooluse' "$on"
    grep -qF 'review-gate.sh\" record' "$on"
    grep -q '"matcher": "Skill"' "$on"
    python3 -c "import json; json.load(open('$off'))"
    ! grep -q "review-gate.sh" "$off"
    ! grep -q "PostToolUse" "$off"
}

@test "doctor: reports review gate state" {
    cd "$TEST_DIR"
    run bash "$MANGOLOVE_DIR/bin/mangolove" doctor
    [[ "$output" == *"Review gate"* ]]
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

@test "defaults: 메서드러지 split + DoD 게이트 + 리뷰 게이트가 기본 on 이다" {
    # 이 세 기본값은 명시적 결정의 결과다(각각 컨텍스트 예산, 완료 검증, 리뷰 강제).
    # 우연히 되돌려지면 MangoLove 가 조용히 예전 동작으로 후퇴하므로 기본값 자체를 고정한다.
    local b="$MANGOLOVE_DIR/bin/mangolove"
    grep -qE '^MANGOLOVE_METHODOLOGY_MODE="?split"?$' "$b"
    grep -qE '^MANGOLOVE_DOD_GATE=on$' "$b"
    grep -qE '^MANGOLOVE_REVIEW_GATE=on$' "$b"
}

@test "doctor: split 기본에서 메서드러지 모드를 split 으로 보고한다" {
    cd "$TEST_DIR"
    run bash "$MANGOLOVE_DIR/bin/mangolove" doctor
    [[ "$output" == *"Methodology mode: split"* ]]
}
