#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove — Commit-boundary Quality Gate (D2)
# 산문 강제 -> 결정적 차단 게이트. 설치 + 동작(block/warn/bypass)을 검증한다.
# ─────────────────────────────────────────────

load test_helper

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

# lint + test 둘 다 있는 strict 노드 프로젝트를 만든다.
_strict_node_project() {
    local proj
    proj=$(create_fake_project "$1")
    echo '{"name":"app","scripts":{"test":"jest","lint":"eslint ."}}' > "$proj/package.json"
    echo '{}' > "$proj/.eslintrc.json"
    echo "$proj"
}

# ── 설치 ──

@test "gate: --strict installs executable quality-gate.sh and gate.conf" {
    local proj; proj=$(_strict_node_project "gate-install")
    cd "$proj"
    run bash "$MANGOLOVE_DIR/lib/project-init.sh" init --strict
    [ "$status" -eq 0 ]
    [ -f "$proj/.mangolove/hooks/quality-gate.sh" ]
    [ -x "$proj/.mangolove/hooks/quality-gate.sh" ]
    [ -f "$proj/.mangolove/hooks/gate.conf" ]
    grep -q "LINT_CMD=" "$proj/.mangolove/hooks/gate.conf"
    grep -q "TEST_CMD=" "$proj/.mangolove/hooks/gate.conf"
}

@test "gate: settings.json adds PreToolUse gate and stays valid JSON" {
    local proj; proj=$(_strict_node_project "gate-settings")
    cd "$proj"
    bash "$MANGOLOVE_DIR/lib/project-init.sh" init --strict
    grep -q "PreToolUse" "$proj/.claude/settings.json"
    grep -q "PostToolUse" "$proj/.claude/settings.json"
    grep -q "SessionStart" "$proj/.claude/settings.json"
    grep -q "quality-gate.sh" "$proj/.claude/settings.json"
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "import json; json.load(open('$proj/.claude/settings.json'))"
    fi
}

@test "gate: non-strict init installs no gate" {
    local proj; proj=$(create_fake_project "gate-nonstrict")
    echo '{"name":"app","scripts":{"test":"jest"}}' > "$proj/package.json"
    cd "$proj"
    bash "$MANGOLOVE_DIR/lib/project-init.sh" init
    [ ! -d "$proj/.mangolove/hooks" ]
}

@test "gate: installs MangoLove-managed git pre-commit when .git exists" {
    local proj; proj=$(_strict_node_project "gate-precommit")
    mkdir -p "$proj/.git"
    cd "$proj"
    bash "$MANGOLOVE_DIR/lib/project-init.sh" init --strict
    [ -f "$proj/.git/hooks/pre-commit" ]
    [ -x "$proj/.git/hooks/pre-commit" ]
    grep -q "MangoLove" "$proj/.git/hooks/pre-commit"
}

@test "gate: preserves an existing non-MangoLove pre-commit" {
    local proj; proj=$(_strict_node_project "gate-precommit-existing")
    mkdir -p "$proj/.git/hooks"
    printf '#!/bin/sh\necho mine\n' > "$proj/.git/hooks/pre-commit"
    cd "$proj"
    bash "$MANGOLOVE_DIR/lib/project-init.sh" init --strict
    grep -q "echo mine" "$proj/.git/hooks/pre-commit"
    ! grep -q "MangoLove" "$proj/.git/hooks/pre-commit"
}

# ── 동작 (controlled gate.conf) ──

# $1=dir suffix, $2..=gate.conf 라인 -> 게이트 디렉토리 경로를 echo
_gate_with_conf() {
    local gdir="$TEST_DIR/$1/.mangolove/hooks"
    mkdir -p "$gdir"
    cp "$MANGOLOVE_DIR/lib/quality-gate.sh" "$gdir/quality-gate.sh"
    shift
    printf '%s\n' "$@" > "$gdir/gate.conf"
    echo "$gdir"
}

@test "gate: precommit blocks (exit 1) when a block step fails" {
    local g; g=$(_gate_with_conf "g-block" 'GATE_LINT=block' 'LINT_CMD=false' 'GATE_TEST=off')
    run bash "$g/quality-gate.sh" precommit
    [ "$status" -eq 1 ]
}

@test "gate: pretooluse blocks (exit 2) on git commit when block step fails" {
    local g; g=$(_gate_with_conf "g-block2" 'GATE_LINT=block' 'LINT_CMD=false' 'GATE_TEST=off')
    run bash "$g/quality-gate.sh" pretooluse <<< '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}'
    [ "$status" -eq 2 ]
}

@test "gate: pretooluse allows (exit 0) non-commit commands regardless" {
    local g; g=$(_gate_with_conf "g-noncommit" 'GATE_LINT=block' 'LINT_CMD=false' 'GATE_TEST=off')
    run bash "$g/quality-gate.sh" pretooluse <<< '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
    [ "$status" -eq 0 ]
}

@test "gate: warn step failure does not block (exit 0)" {
    local g; g=$(_gate_with_conf "g-warn" 'GATE_LINT=warn' 'LINT_CMD=false' 'GATE_TEST=off')
    run bash "$g/quality-gate.sh" precommit
    [ "$status" -eq 0 ]
}

@test "gate: passes (exit 0) when block step succeeds" {
    local g; g=$(_gate_with_conf "g-pass" 'GATE_LINT=block' 'LINT_CMD=true' 'GATE_TEST=off')
    run bash "$g/quality-gate.sh" precommit
    [ "$status" -eq 0 ]
}

@test "gate: MANGOLOVE_SKIP_GATE=1 bypasses a failing block step (audited)" {
    local g; g=$(_gate_with_conf "g-skip" 'GATE_LINT=block' 'LINT_CMD=false' 'GATE_TEST=off')
    export MANGOLOVE_SKIP_GATE=1
    run bash "$g/quality-gate.sh" precommit
    [ "$status" -eq 0 ]
}
