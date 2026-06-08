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

@test "gate: pretooluse allows read-only git that merely mentions commit" {
    local g; g=$(_gate_with_conf "g-gitlog" 'GATE_LINT=block' 'LINT_CMD=false' 'GATE_TEST=off')
    run bash "$g/quality-gate.sh" pretooluse <<< '{"tool_name":"Bash","tool_input":{"command":"git log --grep=commit --oneline"}}'
    [ "$status" -eq 0 ]
    run bash "$g/quality-gate.sh" pretooluse <<< '{"tool_name":"Bash","tool_input":{"command":"git config commit.gpgsign true"}}'
    [ "$status" -eq 0 ]
}

@test "gate: pretooluse still gates git -C <dir> commit" {
    local g; g=$(_gate_with_conf "g-gitc" 'GATE_LINT=block' 'LINT_CMD=false' 'GATE_TEST=off')
    run bash "$g/quality-gate.sh" pretooluse <<< '{"tool_name":"Bash","tool_input":{"command":"git -C /repo commit -m x"}}'
    [ "$status" -eq 2 ]
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

# ── 시크릿 스캔 ──

# git 레포에 게이트를 설치하고 (시크릿 스캔만 켠) gate.conf 를 둔 디렉토리를 echo
_secret_repo() {
    local repo="$TEST_DIR/$1"
    mkdir -p "$repo/.mangolove/hooks"
    cp "$MANGOLOVE_DIR/lib/quality-gate.sh" "$repo/.mangolove/hooks/quality-gate.sh"
    printf '%s\n' 'GATE_LINT=off' 'GATE_TEST=off' 'GATE_SECRET=block' 'SECRET_SCANNER=builtin' \
        > "$repo/.mangolove/hooks/gate.conf"
    git -C "$repo" init -q
    git -C "$repo" config user.email t@t.com
    git -C "$repo" config user.name tester
    echo "$repo"
}

@test "gate: secret scan blocks staged AWS-key-like content" {
    local repo; repo=$(_secret_repo "sec-block")
    printf 'const k = "AKIAIOSFODNN7EXAMPLE";\n' > "$repo/leak.js"
    git -C "$repo" add leak.js
    cd "$repo"
    run bash "$repo/.mangolove/hooks/quality-gate.sh" precommit
    [ "$status" -eq 1 ]
}

@test "gate: secret scan never prints the secret value" {
    local repo; repo=$(_secret_repo "sec-mask")
    printf 'const k = "AKIAIOSFODNN7EXAMPLE";\n' > "$repo/leak.js"
    git -C "$repo" add leak.js
    cd "$repo"
    run bash "$repo/.mangolove/hooks/quality-gate.sh" precommit
    [[ "$output" != *"AKIAIOSFODNN7EXAMPLE"* ]]
}

@test "gate: secret scan passes clean staged content" {
    local repo; repo=$(_secret_repo "sec-clean")
    printf 'export const greeting = "hello world";\n' > "$repo/ok.js"
    git -C "$repo" add ok.js
    cd "$repo"
    run bash "$repo/.mangolove/hooks/quality-gate.sh" precommit
    [ "$status" -eq 0 ]
}

@test "gate: secret scan blocks staged private key" {
    local repo; repo=$(_secret_repo "sec-pk")
    printf -- '-----BEGIN RSA PRIVATE KEY-----\nMIIEabcdef\n-----END RSA PRIVATE KEY-----\n' > "$repo/key.pem"
    git -C "$repo" add key.pem
    cd "$repo"
    run bash "$repo/.mangolove/hooks/quality-gate.sh" precommit
    [ "$status" -eq 1 ]
}

@test "gate: secret scan blocks staged GitHub token" {
    local repo; repo=$(_secret_repo "sec-ghp")
    # 토큰을 런타임 조립한다 — GitHub 푸시 보호가 .bats 파일의 리터럴을 시크릿으로 막지 않도록.
    local tok="ghp""_$(printf '0%.0s' $(seq 36))"
    printf 'const t = "%s";\n' "$tok" > "$repo/leak.js"
    git -C "$repo" add leak.js
    cd "$repo"
    run bash "$repo/.mangolove/hooks/quality-gate.sh" precommit
    [ "$status" -eq 1 ]
}

@test "gate: secret scan blocks staged Stripe live key" {
    local repo; repo=$(_secret_repo "sec-stripe")
    local tok="sk""_live_zz0000000000000000000000zz"
    printf 'KEY=%s\n' "$tok" > "$repo/conf.env"
    git -C "$repo" add conf.env
    cd "$repo"
    run bash "$repo/.mangolove/hooks/quality-gate.sh" precommit
    [ "$status" -eq 1 ]
}

@test "gate: secret scan blocks staged JWT" {
    local repo; repo=$(_secret_repo "sec-jwt")
    local tok="ey""J0eXAiOiJKV1abcdef.eyJzdWIiOiIxMjabcdef.SflKxwRJSMeKabcdef"
    printf 'token=%s\n' "$tok" > "$repo/t.txt"
    git -C "$repo" add t.txt
    cd "$repo"
    run bash "$repo/.mangolove/hooks/quality-gate.sh" precommit
    [ "$status" -eq 1 ]
}

@test "gate: generic keyword=value warns but does not block (heuristic)" {
    local repo; repo=$(_secret_repo "sec-generic")
    printf 'password = "abcdefghij1234567890XYZ"\n' > "$repo/conf.txt"
    git -C "$repo" add conf.txt
    cd "$repo"
    run bash "$repo/.mangolove/hooks/quality-gate.sh" precommit
    [ "$status" -eq 0 ]
    [[ "$output" == *"휴리스틱"* ]]
}

@test "gate: secret scan does not flag a benign password length check" {
    local repo; repo=$(_secret_repo "sec-fp")
    printf 'if (password.length >= 8) { ok(); }\n' > "$repo/ok.js"
    git -C "$repo" add ok.js
    cd "$repo"
    run bash "$repo/.mangolove/hooks/quality-gate.sh" precommit
    [ "$status" -eq 0 ]
}

@test "gate: pretooluse commit -am scans unstaged tracked changes for secrets" {
    local repo; repo=$(_secret_repo "sec-commit-a")
    printf 'x = 1\n' > "$repo/app.py"
    git -C "$repo" add app.py
    git -C "$repo" commit -qm init
    printf 'KEY = "AKIAIOSFODNN7EXAMPLE"\n' >> "$repo/app.py"   # unstaged 수정
    cd "$repo"
    run bash "$repo/.mangolove/hooks/quality-gate.sh" pretooluse <<< '{"tool_name":"Bash","tool_input":{"command":"git commit -am wip"}}'
    [ "$status" -eq 2 ]
}

@test "gate: pretooluse commit -m (no -a) does not scan unstaged changes" {
    local repo; repo=$(_secret_repo "sec-commit-m")
    printf 'x = 1\n' > "$repo/app.py"
    git -C "$repo" add app.py
    git -C "$repo" commit -qm init
    printf 'KEY = "AKIAIOSFODNN7EXAMPLE"\n' >> "$repo/app.py"   # unstaged (커밋되지 않음)
    cd "$repo"
    run bash "$repo/.mangolove/hooks/quality-gate.sh" pretooluse <<< '{"tool_name":"Bash","tool_input":{"command":"git commit -m wip"}}'
    [ "$status" -eq 0 ]
}

@test "gate: pretooluse uses stdin cwd to locate the project (session hook)" {
    local repo; repo=$(_secret_repo "sec-cwd")
    printf 'KEY = "AKIAIOSFODNN7EXAMPLE"\n' > "$repo/leak.py"
    git -C "$repo" add leak.py
    # 게이트를 repo 가 아닌 다른 cwd 에서 실행하되 stdin cwd 로 repo 를 지정 (세션 hook 시나리오)
    cd "$TEST_DIR"
    run bash "$repo/.mangolove/hooks/quality-gate.sh" pretooluse <<< "{\"tool_input\":{\"command\":\"git commit -m x\"},\"cwd\":\"$repo\"}"
    [ "$status" -eq 2 ]
}

# ── 게이트가 추적되는 위치에 설치되는지 (D4: 버전관리/감사 가능) ──
