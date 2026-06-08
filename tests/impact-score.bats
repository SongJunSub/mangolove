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

@test "impact: empty commit does not crash (set -u safe) -> Trivial" {
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

# ── 적대적 리뷰 회귀 (FP/FN/merge/입력검증/크로스스택/파일수밴드) ──

@test "impact: merge commit with auth change -> floor Large (not Trivial)" {
    local r; r=$(_repo "imp-merge")
    echo seed > "$r/seed.txt"; _mkcommit "$r" seed >/dev/null
    git -C "$r" checkout -q -b feat
    mkdir -p "$r/src/security"; printf '@PreAuthorize("x")\n' > "$r/src/security/Sec.kt"
    _mkcommit "$r" authchange >/dev/null
    git -C "$r" checkout -q -
    echo m > "$r/m.txt"; _mkcommit "$r" main2 >/dev/null
    git -C "$r" -c user.email=t@t.com -c user.name=t merge --no-ff -m merge feat >/dev/null 2>&1
    local sha; sha=$(git -C "$r" rev-parse HEAD)
    cd "$r"
    run bash "$(IMPACT)" score "$sha"
    [[ "$output" == *'"auth":true'* ]]
    [[ "$output" == *'"track_floor":"Large"'* ]]
}

@test "impact: invalid revision exits non-zero (not silent Trivial)" {
    local r; r=$(_repo "imp-badref")
    echo x > "$r/a.txt"; _mkcommit "$r" a >/dev/null
    cd "$r"
    run bash "$(IMPACT)" score deadbeefdeadbeef
    [ "$status" -ne 0 ]
}

@test "impact: filename-only keyword does not flag (axios in filename)" {
    local r; r=$(_repo "imp-fnfp")
    mkdir -p "$r/src"; printf 'export const TIMEOUT = 5000\n' > "$r/src/axios-config.js"
    local sha; sha=$(_mkcommit "$r" cfg)
    cd "$r"
    run bash "$(IMPACT)" score "$sha"
    [[ "$output" == *'"ext":false'* ]]
}

@test "impact: keyword in a doc file does not flag (CREATE TABLE in .md)" {
    local r; r=$(_repo "imp-docfp")
    mkdir -p "$r/docs"; printf 'Run CREATE TABLE users manually.\n' > "$r/docs/notes.md"
    local sha; sha=$(_mkcommit "$r" doc)
    cd "$r"
    run bash "$(IMPACT)" score "$sha"
    [[ "$output" == *'"db":false'* ]]
}

@test "impact: keyword in a comment does not flag (axios in comment)" {
    local r; r=$(_repo "imp-cmtfp")
    mkdir -p "$r/src"; printf 'const x = 1 // TODO migrate from axios\n' > "$r/src/x.js"
    local sha; sha=$(_mkcommit "$r" cmt)
    cd "$r"
    run bash "$(IMPACT)" score "$sha"
    [[ "$output" == *'"ext":false'* ]]
}

@test "impact: auth path prefix collision does not flag (src/author)" {
    local r; r=$(_repo "imp-authfp")
    mkdir -p "$r/src/author"; printf 'class Bio {}\n' > "$r/src/author/Bio.kt"
    local sha; sha=$(_mkcommit "$r" author)
    cd "$r"
    run bash "$(IMPACT)" score "$sha"
    [[ "$output" == *'"auth":false'* ]]
}

@test "impact: domain authorization word does not flag (order authorization)" {
    local r; r=$(_repo "imp-domainauth")
    mkdir -p "$r/src"; printf 'fun checkAuthorization(o: Order) = o.isAuthorized()\n' > "$r/src/Order.kt"
    local sha; sha=$(_mkcommit "$r" order)
    cd "$r"
    run bash "$(IMPACT)" score "$sha"
    [[ "$output" == *'"auth":false'* ]]
}

@test "impact: config getter does not flag api (app.get env)" {
    local r; r=$(_repo "imp-getter")
    mkdir -p "$r/src"; printf 'const e = config.app.get("env")\n' > "$r/src/Cfg.js"
    local sha; sha=$(_mkcommit "$r" getter)
    cd "$r"
    run bash "$(IMPACT)" score "$sha"
    [[ "$output" == *'"api":false'* ]]
}

@test "impact: cross-stack ext (Go http.Get)" {
    local r; r=$(_repo "imp-xext")
    printf 'resp, _ := http.Get("https://x")\n' > "$r/main.go"
    local sha; sha=$(_mkcommit "$r" goget)
    cd "$r"
    run bash "$(IMPACT)" score "$sha"
    [[ "$output" == *'"ext":true'* ]]
}

@test "impact: cross-stack api (Flask app.route)" {
    local r; r=$(_repo "imp-flask")
    printf '@app.route("/users")\ndef users(): pass\n' > "$r/app.py"
    local sha; sha=$(_mkcommit "$r" flask)
    cd "$r"
    run bash "$(IMPACT)" score "$sha"
    [[ "$output" == *'"api":true'* ]]
}

@test "impact: cross-stack db (Rails create_table in db/migrate)" {
    local r; r=$(_repo "imp-rails")
    mkdir -p "$r/db/migrate"; printf 'create_table :users\n' > "$r/db/migrate/001_x.rb"
    local sha; sha=$(_mkcommit "$r" rails)
    cd "$r"
    run bash "$(IMPACT)" score "$sha"
    [[ "$output" == *'"db":true'* ]]
    [[ "$output" == *'"track_floor":"Medium"'* ]]
}

@test "impact: untracked new file is scored in --working (new migration)" {
    local r; r=$(_repo "imp-untracked")
    echo base > "$r/a.txt"; _mkcommit "$r" base >/dev/null
    mkdir -p "$r/db/migration"; printf 'CREATE TABLE x(id int);\n' > "$r/db/migration/V9.sql"
    cd "$r"
    run bash "$(IMPACT)" score --working
    [[ "$output" == *'"db":true'* ]]
    [[ "$output" == *'"track_floor":"Medium"'* ]]
}

@test "impact triage: unknown predicted track exits 2" {
    local r; r=$(_repo "imp-tri-bad")
    echo x > "$r/a.txt"; local sha; sha=$(_mkcommit "$r" a)
    cd "$r"
    run bash "$(IMPACT)" triage Huge "$sha"
    [ "$status" -eq 2 ]
}

@test "impact triage: predicted track is case-insensitive" {
    local r; r=$(_repo "imp-tri-case")
    mkdir -p "$r/src/security"; printf '@Secured("x")\n' > "$r/src/security/S.kt"
    local sha; sha=$(_mkcommit "$r" sec)
    cd "$r"
    run bash "$(IMPACT)" triage large "$sha"
    [[ "$output" == *'"verdict":"ok"'* ]]
}

@test "impact: seven files -> file_pts 5 (band upper)" {
    local r; r=$(_repo "imp-seven")
    local i; for i in 1 2 3 4 5 6 7; do echo "x$i" > "$r/f$i.txt"; done
    local sha; sha=$(_mkcommit "$r" seven)
    cd "$r"
    run bash "$(IMPACT)" score "$sha"
    [[ "$output" == *'"files":7'* ]]
    [[ "$output" == *'"file_pts":5'* ]]
}

@test "impact: twelve files -> file_pts 8 + Medium" {
    local r; r=$(_repo "imp-twelve")
    local i; for i in $(seq 1 12); do echo "x$i" > "$r/f$i.txt"; done
    local sha; sha=$(_mkcommit "$r" twelve)
    cd "$r"
    run bash "$(IMPACT)" score "$sha"
    [[ "$output" == *'"file_pts":8'* ]]
    [[ "$output" == *'"track_from_score":"Medium"'* ]]
}
