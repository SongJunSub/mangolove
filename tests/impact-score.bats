#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove — Impact Score (Phase 2 / D6) 결정적 트랙 분류
# ─────────────────────────────────────────────

load test_helper

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

IMPACT() { echo "$MANGOLOVE_DIR/lib/impact-score.sh"; }

_repo() {
    local r="$TEST_DIR/$1"
    mkdir -p "$r"
    git -C "$r" init -q
    echo "$r"
}

# 현재 스테이징/워킹 파일을 커밋하고 SHA 를 echo
_mkcommit() {
    git -C "$1" add -A
    git -C "$1" -c user.email=t@t.com -c user.name=t commit -qm "$2" >/dev/null
    git -C "$1" rev-parse HEAD
}

# ── 점수 계산 ──

@test "impact: single benign file -> Trivial" {
    local r; r=$(_repo "imp-trivial")
    echo "x" > "$r/a.txt"
    local sha; sha=$(_mkcommit "$r" "add a")
    cd "$r"
    run bash "$(IMPACT)" score "$sha"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"files":1'* ]]
    [[ "$output" == *'"track_from_score":"Trivial"'* ]]
    [[ "$output" == *'"track_floor":"Trivial"'* ]]
}

@test "impact: three files -> Small" {
    local r; r=$(_repo "imp-small")
    echo a > "$r/a.txt"; echo b > "$r/b.txt"; echo c > "$r/c.txt"
    local sha; sha=$(_mkcommit "$r" "three")
    cd "$r"
    run bash "$(IMPACT)" score "$sha"
    [[ "$output" == *'"files":3'* ]]
    [[ "$output" == *'"track_from_score":"Small"'* ]]
}

@test "impact: DB migration -> db flag + floor Medium" {
    local r; r=$(_repo "imp-db")
    mkdir -p "$r/db/migration"
    printf 'CREATE TABLE users (id INT);\n' > "$r/db/migration/V1__init.sql"
    local sha; sha=$(_mkcommit "$r" "schema")
    cd "$r"
    run bash "$(IMPACT)" score "$sha"
    [[ "$output" == *'"db":true'* ]]
    [[ "$output" == *'"track_floor":"Medium"'* ]]
}

@test "impact: auth change -> auth flag + floor Large" {
    local r; r=$(_repo "imp-auth")
    mkdir -p "$r/src/security"
    printf '@PreAuthorize("hasRole(ADMIN)")\nfun secure() {}\n' > "$r/src/security/SecurityConfig.kt"
    local sha; sha=$(_mkcommit "$r" "security")
    cd "$r"
    run bash "$(IMPACT)" score "$sha"
    [[ "$output" == *'"auth":true'* ]]
    [[ "$output" == *'"track_floor":"Large"'* ]]
}

@test "impact: new API mapping -> api flag" {
    local r; r=$(_repo "imp-api")
    mkdir -p "$r/src"
    printf '@GetMapping("/v1/users")\nfun list() {}\n' > "$r/src/UserController.kt"
    local sha; sha=$(_mkcommit "$r" "api")
    cd "$r"
    run bash "$(IMPACT)" score "$sha"
    [[ "$output" == *'"api":true'* ]]
}

@test "impact: external API client -> ext flag + floor Medium" {
    local r; r=$(_repo "imp-ext")
    mkdir -p "$r/src"
    printf 'val client = WebClient.create("https://api.example.com")\n' > "$r/src/Client.kt"
    local sha; sha=$(_mkcommit "$r" "ext")
    cd "$r"
    run bash "$(IMPACT)" score "$sha"
    [[ "$output" == *'"ext":true'* ]]
    [[ "$output" == *'"track_floor":"Medium"'* ]]
}

@test "impact: empty/merge commit does not crash (set -u safe) -> Trivial" {
    local r; r=$(_repo "imp-empty")
    echo seed > "$r/seed.txt"; _mkcommit "$r" "seed" >/dev/null
    git -C "$r" -c user.email=t@t.com -c user.name=t commit -q --allow-empty -m empty
    local sha; sha=$(git -C "$r" rev-parse HEAD)
    cd "$r"
    run bash "$(IMPACT)" score "$sha"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"files":0'* ]]
    [[ "$output" == *'"track_floor":"Trivial"'* ]]
}

@test "impact: --working reflects uncommitted changes" {
    local r; r=$(_repo "imp-working")
    echo base > "$r/a.txt"; _mkcommit "$r" "base" >/dev/null
    mkdir -p "$r/src/security"
    printf '@PreAuthorize("x")\n' > "$r/src/security/Sec.kt"   # uncommitted
    git -C "$r" add -A
    cd "$r"
    run bash "$(IMPACT)" score --working
    [[ "$output" == *'"auth":true'* ]]
    [[ "$output" == *'"track_floor":"Large"'* ]]
}

# ── triage (under/over/ok) ──

@test "impact triage: predicted Small but auth change -> under_triage" {
    local r; r=$(_repo "tri-under")
    mkdir -p "$r/src/security"; printf '@Secured("ADMIN")\n' > "$r/src/security/S.kt"
    local sha; sha=$(_mkcommit "$r" "sec")
    cd "$r"
    run bash "$(IMPACT)" triage Small "$sha"
    [[ "$output" == *'"track_floor":"Large"'* ]]
    [[ "$output" == *'"verdict":"under_triage"'* ]]
}

@test "impact triage: predicted Large matches floor -> ok" {
    local r; r=$(_repo "tri-ok")
    mkdir -p "$r/src/security"; printf '@Secured("ADMIN")\n' > "$r/src/security/S.kt"
    local sha; sha=$(_mkcommit "$r" "sec")
    cd "$r"
    run bash "$(IMPACT)" triage Large "$sha"
    [[ "$output" == *'"verdict":"ok"'* ]]
}

@test "impact triage: predicted Large for a small change -> over_triage" {
    local r; r=$(_repo "tri-over")
    echo a > "$r/a.txt"; echo b > "$r/b.txt"; echo c > "$r/c.txt"
    local sha; sha=$(_mkcommit "$r" "three")
    cd "$r"
    run bash "$(IMPACT)" triage Large "$sha"
    [[ "$output" == *'"verdict":"over_triage"'* ]]
}

# ── report + CLI ──

@test "impact report: shows track_floor and promotion note" {
    local r; r=$(_repo "rep")
    mkdir -p "$r/src/security"; printf '@PreAuthorize("x")\n' > "$r/src/security/S.kt"
    local sha; sha=$(_mkcommit "$r" "sec")
    cd "$r"
    run bash "$(IMPACT)" report "$sha"
    [[ "$output" == *"track_floor"* ]]
    [[ "$output" == *"Large"* ]]
    [[ "$output" == *"승격"* ]]
}

@test "impact: mangolove impact dispatches to a human report" {
    local r; r=$(_repo "cli")
    echo x > "$r/a.txt"; local sha; sha=$(_mkcommit "$r" "a")
    cp "$BATS_TEST_DIRNAME/../bin/mangolove" "$MANGOLOVE_DIR/bin/mangolove"
    chmod +x "$MANGOLOVE_DIR/bin/mangolove"
    cd "$r"
    run bash "$MANGOLOVE_DIR/bin/mangolove" impact "$sha"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Impact"* ]]
}

@test "impact: errors cleanly outside a git repository" {
    local d="$TEST_DIR/nogit"; mkdir -p "$d"
    cd "$d"
    run bash "$(IMPACT)" score --working
    [ "$status" -eq 1 ]
}
