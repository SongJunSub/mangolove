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
    [[ "$output" == *"리스크 분포"* ]]
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

@test "efficacy: recorder failure never breaks the guard (unwritable ledger dir)" {
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

# ── 적대적 리뷰 회귀 (실설치 배선·cwd·게이트 비차단·invariant·JSON) ──

@test "efficacy: init --strict installs the recorder alongside the gate (real wiring)" {
    local proj; proj=$(create_fake_project "eff-install")
    echo '{"name":"app","scripts":{"test":"jest","lint":"eslint ."}}' > "$proj/package.json"
    echo '{}' > "$proj/.eslintrc.json"
    cd "$proj"
    bash "$MANGOLOVE_DIR/lib/project-init.sh" init --strict
    [ -f "$proj/.mangolove/hooks/efficacy-recorder.sh" ]
    [ -x "$proj/.mangolove/hooks/efficacy-recorder.sh" ]
}

@test "efficacy: installed gate records a block via real wiring (no manual cp)" {
    local proj; proj=$(create_fake_project "eff-e2e")
    echo '{"name":"app","scripts":{"test":"jest","lint":"eslint ."}}' > "$proj/package.json"
    echo '{}' > "$proj/.eslintrc.json"
    git -C "$proj" init -q
    cd "$proj"
    bash "$MANGOLOVE_DIR/lib/project-init.sh" init --strict
    printf '%s\n' 'GATE_LINT=block' 'LINT_CMD=false' 'GATE_TEST=off' 'GATE_SECRET=off' > "$proj/.mangolove/hooks/gate.conf"
    run bash "$proj/.mangolove/hooks/quality-gate.sh" precommit
    [ "$status" -eq 1 ]
    [ -f "$MANGOLOVE_DIR/efficacy/eff-e2e.jsonl" ]
    grep -q '"phase":"gate"' "$MANGOLOVE_DIR/efficacy/eff-e2e.jsonl"
}

@test "efficacy: guard records to the project ledger using stdin cwd" {
    local r; r=$(_git_repo "eff-guard-cwd")
    cp "$MANGOLOVE_DIR/lib/irreversible-guard.sh" "$MANGOLOVE_DIR/lib/efficacy-recorder.sh" "$r/"
    cd "$TEST_DIR"
    run bash "$r/irreversible-guard.sh" <<< "{\"tool_input\":{\"command\":\"rm -rf /\"},\"cwd\":\"$r\"}"
    [ "$status" -eq 2 ]
    [ -f "$MANGOLOVE_DIR/efficacy/eff-guard-cwd.jsonl" ]
    grep -q '"phase":"guard"' "$MANGOLOVE_DIR/efficacy/eff-guard-cwd.jsonl"
}

@test "efficacy: recorder failure never breaks the gate (exit codes preserved)" {
    local r; r=$(_git_repo "eff-gate-robust")
    cp "$MANGOLOVE_DIR/lib/quality-gate.sh" "$r/"
    printf '#!/usr/bin/env bash\nexit 99\n' > "$r/efficacy-recorder.sh"; chmod +x "$r/efficacy-recorder.sh"
    printf '%s\n' 'GATE_LINT=block' 'LINT_CMD=false' 'GATE_TEST=off' 'GATE_SECRET=off' > "$r/gate.conf"
    cd "$r"
    run bash "$r/quality-gate.sh" precommit
    [ "$status" -eq 1 ]
    run bash "$r/quality-gate.sh" pretooluse <<< "{\"tool_input\":{\"command\":\"git commit -m x\"},\"cwd\":\"$r\"}"
    [ "$status" -eq 2 ]
}

@test "efficacy: report bucket counts sum to total (no double-count)" {
    local r; r=$(_git_repo "eff-invariant")
    cd "$r"
    bash "$(REC)" record-block gate secret
    bash "$(REC)" record-block gate lint
    bash "$(REC)" record-block guard "rm -rf /"
    bash "$(REC)" record-block guard "git push --force"
    run bash "$(REC)" report
    [[ "$output" == *"총 4회"* ]]
    [[ "$output" != *"기타 차단"* ]]
}

@test "efficacy: record-block with special chars stays valid JSON" {
    command -v python3 >/dev/null 2>&1 || skip "needs python3"
    local r; r=$(_git_repo "eff-json")
    cd "$r"
    bash "$(REC)" record-block guard 'weird"quote\back'
    python3 -c "import json; [json.loads(l) for l in open('$MANGOLOVE_DIR/efficacy/eff-json.jsonl')]"
}

# ── under-triage (Phase 2 잔여) — 선언 트랙 vs 코드 floor 갭, 분모=선언된 커밋만 ──

# 트레일러 포함 커밋 (현재 cwd 레포에 add+commit)
_commit_track() {
    local subject="$1" track="$2"
    git add -A
    git -c user.email=t@t.com -c user.name=t \
        commit -qm "$(printf '%s\n\nChange-Track: %s\n' "$subject" "$track")" >/dev/null
}

@test "efficacy: report shows under-triage rate over declared commits" {
    local r; r=$(_git_repo "eff-under")
    cd "$r"
    # auth 변경을 Small 로 선언 → under_triage (floor Large)
    mkdir -p src/security; printf '@Secured("ADMIN")\n' > src/security/S.kt
    _commit_track "sec" "Small"
    # trivial 을 Trivial 로 선언 → ok
    echo x > a.txt; _commit_track "tweak" "Trivial"
    run bash "$(REC)" report
    [ "$status" -eq 0 ]
    [[ "$output" == *"under-triage"* ]]
    # seed(미선언) + 2선언 → n=3, 분모는 선언된 2개만, under 1건
    [[ "$output" == *"3커밋 중 2건 선언"* ]]
    [[ "$output" == *"under-triage: 선언 2건 중 1건"* ]]
    # 선언은 자기보고임을 정직하게 표기
    [[ "$output" == *"자기보고"* ]]
}

@test "efficacy: report reports zero coverage when no Change-Track declared" {
    local r; r=$(_git_repo "eff-nocover")
    cd "$r"
    echo x > a.txt; git add -A
    git -c user.email=t@t.com -c user.name=t commit -qm "no trailer here" >/dev/null
    run bash "$(REC)" report
    [ "$status" -eq 0 ]
    [[ "$output" == *"coverage 0"* ]]
}
