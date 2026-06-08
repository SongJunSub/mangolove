#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove — Efficacy Ledger (Phase 2 / D5)
# 게이트/가드 차단이 실시간 기록되고, report 가 결정적 효능을 집계하는지 검증한다.
# ─────────────────────────────────────────────

load test_helper

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

REC() { echo "$MANGOLOVE_DIR/lib/efficacy-recorder.sh"; }

_git_repo() {
    local r="$TEST_DIR/$1"; mkdir -p "$r"
    git -C "$r" init -q
    echo seed > "$r/seed.txt"
    git -C "$r" -c user.email=t@t.com -c user.name=t add -A
    git -C "$r" -c user.email=t@t.com -c user.name=t commit -qm seed >/dev/null
    echo "$r"
}

@test "efficacy: record-block appends to the project ledger" {
    local r; r=$(_git_repo "eff-rec")
    cd "$r"
    bash "$(REC)" record-block gate secret
    bash "$(REC)" record-block guard "git push --force"
    [ -f "$MANGOLOVE_DIR/efficacy/eff-rec.jsonl" ]
    grep -q '"phase":"gate"' "$MANGOLOVE_DIR/efficacy/eff-rec.jsonl"
    grep -q '"kind":"secret"' "$MANGOLOVE_DIR/efficacy/eff-rec.jsonl"
    grep -q '"phase":"guard"' "$MANGOLOVE_DIR/efficacy/eff-rec.jsonl"
}

@test "efficacy: report aggregates blocks + impact distribution" {
    local r; r=$(_git_repo "eff-report")
    cd "$r"
    bash "$(REC)" record-block gate secret
    bash "$(REC)" record-block guard "rm -rf /"
    run bash "$(REC)" report
    [ "$status" -eq 0 ]
    [[ "$output" == *"방법론 효능"* ]]
    [[ "$output" == *"시크릿 커밋 차단"* ]]
    [[ "$output" == *"최근 커밋 리스크 분포"* ]]
}

@test "efficacy: gate block is recorded (and gate still blocks)" {
    local r; r=$(_git_repo "eff-gate")
    cp "$MANGOLOVE_DIR/lib/quality-gate.sh" "$MANGOLOVE_DIR/lib/efficacy-recorder.sh" "$r/"
    printf '%s\n' 'GATE_LINT=block' 'LINT_CMD=false' 'GATE_TEST=off' 'GATE_SECRET=off' > "$r/gate.conf"
    cd "$r"
    run bash "$r/quality-gate.sh" precommit
    [ "$status" -eq 1 ]
    [ -f "$MANGOLOVE_DIR/efficacy/eff-gate.jsonl" ]
    grep -q '"phase":"gate"' "$MANGOLOVE_DIR/efficacy/eff-gate.jsonl"
    grep -q '"kind":"lint"' "$MANGOLOVE_DIR/efficacy/eff-gate.jsonl"
}

@test "efficacy: guard block is recorded (and guard still blocks)" {
    local r; r=$(_git_repo "eff-guard")
    cp "$MANGOLOVE_DIR/lib/irreversible-guard.sh" "$MANGOLOVE_DIR/lib/efficacy-recorder.sh" "$r/"
    cd "$r"
    run bash "$r/irreversible-guard.sh" <<< '{"tool_input":{"command":"git push --force origin main"}}'
    [ "$status" -eq 2 ]
    [ -f "$MANGOLOVE_DIR/efficacy/eff-guard.jsonl" ]
    grep -q '"phase":"guard"' "$MANGOLOVE_DIR/efficacy/eff-guard.jsonl"
}

@test "efficacy: recorder failure never breaks the gate (unwritable ledger dir)" {
    local r; r=$(_git_repo "eff-robust")
    cp "$MANGOLOVE_DIR/lib/irreversible-guard.sh" "$MANGOLOVE_DIR/lib/efficacy-recorder.sh" "$r/"
    cd "$r"
    # 기록 실패해도 가드는 정상 차단해야 함
    run env MANGOLOVE_DIR=/proc/nonexistent/x bash "$r/irreversible-guard.sh" <<< '{"tool_input":{"command":"rm -rf /"}}'
    [ "$status" -eq 2 ]
}

@test "efficacy: mangolove efficacy dispatches to a report" {
    cp "$BATS_TEST_DIRNAME/../bin/mangolove" "$MANGOLOVE_DIR/bin/mangolove"
    chmod +x "$MANGOLOVE_DIR/bin/mangolove"
    local r; r=$(_git_repo "eff-cli")
    cd "$r"
    run bash "$MANGOLOVE_DIR/bin/mangolove" efficacy
    [ "$status" -eq 0 ]
    [[ "$output" == *"방법론 효능"* ]]
}
