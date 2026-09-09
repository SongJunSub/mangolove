#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove: Impact Score (Phase 2 / D6) 결정적 트랙 분류
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

# ── 크로스스택 커버리지 보강 (C#/.NET, Rust, EF) ──

@test "impact: C# Authorize attribute -> auth flag + floor Large" {
    local r; r=$(_repo "imp-csauth")
    mkdir -p "$r/src"; printf '[Authorize(Roles = "Admin")]\npublic class C {}\n' > "$r/src/UserController.cs"
    local sha; sha=$(_mkcommit "$r" "csauth")
    cd "$r"
    run bash "$(IMPACT)" score "$sha"
    [[ "$output" == *'"auth":true'* ]]
    [[ "$output" == *'"track_floor":"Large"'* ]]
}

@test "impact: Rust reqwest -> ext flag + floor Medium" {
    local r; r=$(_repo "imp-rustext")
    mkdir -p "$r/src"; printf 'let b = reqwest::get("https://api.example.com").await?;\n' > "$r/src/client.rs"
    local sha; sha=$(_mkcommit "$r" "rustext")
    cd "$r"
    run bash "$(IMPACT)" score "$sha"
    [[ "$output" == *'"ext":true'* ]]
    [[ "$output" == *'"track_floor":"Medium"'* ]]
}

@test "impact: EF migrationBuilder.CreateTable -> db flag + floor Medium" {
    local r; r=$(_repo "imp-efdb")
    mkdir -p "$r/src/Data"; printf 'migrationBuilder.CreateTable(name: "Users");\n' > "$r/src/Data/SchemaSetup.cs"
    local sha; sha=$(_mkcommit "$r" "efdb")
    cd "$r"
    run bash "$(IMPACT)" score "$sha"
    [[ "$output" == *'"db":true'* ]]
    [[ "$output" == *'"track_floor":"Medium"'* ]]
}

@test "impact: Rust tower auth middleware -> auth flag + floor Large" {
    local r; r=$(_repo "imp-rustauth")
    mkdir -p "$r/src/net"; printf 'use tower_http::auth::RequireAuthorizationLayer;\n' > "$r/src/net/mw.rs"
    local sha; sha=$(_mkcommit "$r" "rustauth")
    cd "$r"
    run bash "$(IMPACT)" score "$sha"
    [[ "$output" == *'"auth":true'* ]]
    [[ "$output" == *'"track_floor":"Large"'* ]]
}

# ── declared-track + triage-commit (Phase 2 잔여 / under_triage) ──

# 트레일러 포함 커밋 생성 (subject + 빈 줄 + Change-Track) → SHA echo
_mkcommit_track() {
    local r="$1" subject="$2" track="$3"
    git -C "$r" add -A
    git -C "$r" -c user.email=t@t.com -c user.name=t \
        commit -qm "$(printf '%s\n\nChange-Track: %s\n' "$subject" "$track")" >/dev/null
    git -C "$r" rev-parse HEAD
}

@test "impact declared-track: extracts a valid Change-Track trailer" {
    local r; r=$(_repo "dt-ok")
    echo x > "$r/a.txt"
    local sha; sha=$(_mkcommit_track "$r" "feat: x" "Small")
    cd "$r"
    run bash "$(IMPACT)" declared-track "$sha"
    [ "$status" -eq 0 ]
    [ "$output" = "Small" ]
}

@test "impact declared-track: empty when no trailer" {
    local r; r=$(_repo "dt-none")
    echo x > "$r/a.txt"; local sha; sha=$(_mkcommit "$r" "no trailer")
    cd "$r"
    run bash "$(IMPACT)" declared-track "$sha"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "impact declared-track: invalid value yields empty (undeclared)" {
    local r; r=$(_repo "dt-bad")
    echo x > "$r/a.txt"; local sha; sha=$(_mkcommit_track "$r" "x" "Huge")
    cd "$r"
    run bash "$(IMPACT)" declared-track "$sha"
    [ -z "$output" ]
}

@test "impact declared-track: a Change-Track line in prose body is NOT captured (footer-only)" {
    local r; r=$(_repo "dt-prose")
    echo x > "$r/a.txt"; git -C "$r" add -A
    # 'Change-Track: Large ...' 가 본문 중간에 있고, 진짜 마지막 단락은 산문 → 트레일러 아님
    git -C "$r" -c user.email=t@t.com -c user.name=t \
        commit -qm "$(printf 'feat: x\n\nChange-Track: Large is just a concept here.\n\nActual body paragraph, no trailer.\n')" >/dev/null
    local sha; sha=$(git -C "$r" rev-parse HEAD)
    cd "$r"
    run bash "$(IMPACT)" declared-track "$sha"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "impact declared-track: last trailer wins and is case-insensitive" {
    local r; r=$(_repo "dt-last")
    echo x > "$r/a.txt"; git -C "$r" add -A
    git -C "$r" -c user.email=t@t.com -c user.name=t \
        commit -qm "$(printf 'x\n\nChange-Track: small\nChange-Track: LARGE\n')" >/dev/null
    local sha; sha=$(git -C "$r" rev-parse HEAD)
    cd "$r"
    run bash "$(IMPACT)" declared-track "$sha"
    [ "$output" = "Large" ]
}

@test "impact triage-commit: no trailer -> verdict undeclared (declared null)" {
    local r; r=$(_repo "tc-undecl")
    echo x > "$r/a.txt"; local sha; sha=$(_mkcommit "$r" "x")
    cd "$r"
    run bash "$(IMPACT)" triage-commit "$sha"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"declared":null'* ]]
    [[ "$output" == *'"verdict":"undeclared"'* ]]
}

@test "impact triage-commit: declared Small but auth change -> under_triage" {
    local r; r=$(_repo "tc-under")
    mkdir -p "$r/src/security"; printf '@Secured("ADMIN")\n' > "$r/src/security/S.kt"
    local sha; sha=$(_mkcommit_track "$r" "sec" "Small")
    cd "$r"
    run bash "$(IMPACT)" triage-commit "$sha"
    [[ "$output" == *'"declared":"Small"'* ]]
    [[ "$output" == *'"track_floor":"Large"'* ]]
    [[ "$output" == *'"verdict":"under_triage"'* ]]
}

@test "impact triage-commit: declared Large matches floor -> ok" {
    local r; r=$(_repo "tc-ok")
    mkdir -p "$r/src/security"; printf '@Secured("ADMIN")\n' > "$r/src/security/S.kt"
    local sha; sha=$(_mkcommit_track "$r" "sec" "Large")
    cd "$r"
    run bash "$(IMPACT)" triage-commit "$sha"
    [[ "$output" == *'"verdict":"ok"'* ]]
}

@test "impact triage-commit: declared Large for a trivial change -> over_triage" {
    local r; r=$(_repo "tc-over")
    echo x > "$r/a.txt"
    local sha; sha=$(_mkcommit_track "$r" "x" "Large")
    cd "$r"
    run bash "$(IMPACT)" triage-commit "$sha"
    [[ "$output" == *'"verdict":"over_triage"'* ]]
}

# ── 범위 ref (A...B) 와 경로 제한: push 경계 게이트가 쓰는 입력 ──
#
# 세 점 범위를 쓰는 이유는 merge base 다. 이미 upstream 에 있는 머지 내용은 자동으로
# 빠지고, upstream 에 없는(= 어디서도 검토되지 않은) 브랜치를 머지하면 그 내용은 범위에
# 남는다. 머지 특별처리 코드 없이 두 성질을 동시에 얻는다.

# base 를 origin/main 처럼 쓸 로컬 레포를 만든다 (원격 없이 브랜치로 흉내).
_repo_with_base() {
    local r; r=$(_repo "$1")
    echo base > "$r/base.txt"
    git -C "$r" add -A
    git -C "$r" -c user.email=t@t.com -c user.name=t commit -qm base >/dev/null
    git -C "$r" branch -q upstream
    echo "$r"
}

@test "impact range: A...B 로 브랜치 순변경만 점수화한다" {
    local r; r=$(_repo_with_base "rng-basic")
    cd "$r"
    printf 'const r = await axios.get("https://api.example.com/v1")\n' > client.js
    _mkcommit "$r" "work" >/dev/null
    run bash "$(IMPACT)" score 'upstream...HEAD'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"files":1'* ]]
    [[ "$output" == *'"ext":true'* ]]
}

@test "impact range: 이미 upstream 에 있는 브랜치를 머지하면 merge base 가 빼준다" {
    local r; r=$(_repo_with_base "rng-merged-upstream")
    cd "$r"
    # feat 를 만들고 upstream 에 먼저 반영한다 (= 이미 검토, 공유된 코드)
    git checkout -q -b feat
    printf 'const a = await axios.get("https://api.example.com/a")\n' > feat.js
    _mkcommit "$r" "feat" >/dev/null
    git checkout -q upstream
    git merge -q --no-ff -m "merge feat" feat
    git checkout -q -b mine feat
    git merge -q --no-ff -m "merge feat into mine" feat 2>/dev/null || true
    echo mine > mine.txt
    _mkcommit "$r" "mine" >/dev/null
    run bash "$(IMPACT)" score 'upstream...HEAD'
    [ "$status" -eq 0 ]
    # feat.js 는 upstream 에 이미 있으므로 범위 밖. 내 작업만 남는다.
    [[ "$output" == *'"files":1'* ]]
    [[ "$output" == *'"ext":false'* ]]
}

@test "impact range: upstream 에 없는 브랜치를 머지하면 그 내용이 범위에 남는다" {
    local r; r=$(_repo_with_base "rng-merged-rogue")
    cd "$r"
    git checkout -q -b rogue
    printf 'const r = await axios.post("https://api.example.com/x", {})\n' > rogue.js
    _mkcommit "$r" "rogue" >/dev/null
    git checkout -q upstream
    git checkout -q -b mine
    git merge -q --no-ff -m "merge rogue" rogue
    run bash "$(IMPACT)" score 'upstream...HEAD'
    [ "$status" -eq 0 ]
    # 미검토 코드는 머지로 숨지 못한다.
    [[ "$output" == *'"ext":true'* ]]
}

@test "impact range: 커밋을 잘게 쪼개도 범위 점수는 합쳐서 계산된다 (누적 우회 차단)" {
    # 이것이 push 경계로 옮기는 핵심 이유다. 커밋마다 판정하면 개별로는 전부 Trivial 이라
    # 전부 통과하지만, 범위로 보면 Medium 이다. 쪼개서 빠져나갈 구멍이 구조적으로 없다.
    local r; r=$(_repo_with_base "rng-salami")
    cd "$r"
    local i last
    for i in $(seq 1 11); do
        echo "export const V$i = $i" > "f$i.js"
        last=$(_mkcommit "$r" "c$i")
    done

    # 커밋 하나만 보면 Trivial: 커밋 경계 게이트가 전부 통과시켰을 변경이다.
    run bash "$(IMPACT)" score "$last"
    [[ "$output" == *'"files":1'* ]]
    [[ "$output" == *'"track_floor":"Trivial"'* ]]

    # 범위로 보면 파일 11개(file_pts 8) → Medium.
    run bash "$(IMPACT)" score 'upstream...HEAD'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"files":11'* ]]
    [[ "$output" == *'"track_floor":"Medium"'* ]]
}

@test "impact range: -- 로 경로를 제한하면 그 경로만 점수화한다" {
    local r; r=$(_repo_with_base "rng-paths")
    cd "$r"
    printf 'const r = await axios.get("https://api.example.com/v1")\n' > client.js
    echo plain > plain.txt
    _mkcommit "$r" "two files" >/dev/null
    run bash "$(IMPACT)" score 'upstream...HEAD' -- plain.txt
    [ "$status" -eq 0 ]
    [[ "$output" == *'"files":1'* ]]
    # 제한된 경로 밖의 외부 API 신호는 잡히지 않아야 한다 (잔여 점수화의 전제)
    [[ "$output" == *'"ext":false'* ]]
}

@test "impact range: 경로 제한은 기존 ref 형태에도 적용된다" {
    local r; r=$(_repo_with_base "rng-paths-staged")
    cd "$r"
    printf 'const r = await axios.get("https://api.example.com/v1")\n' > client.js
    echo plain > plain.txt
    git add -A
    run bash "$(IMPACT)" score --staged -- plain.txt
    [[ "$output" == *'"files":1'* ]]
    [[ "$output" == *'"ext":false'* ]]
}

@test "impact range: 존재하지 않는 끝점이 있으면 조용히 Trivial 로 흐르지 않는다" {
    local r; r=$(_repo_with_base "rng-badref")
    cd "$r"
    run bash "$(IMPACT)" score 'nosuchbranch...HEAD'
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown range"* ]]
}

@test "impact range: 범위에는 Change-Track trailer 판정을 적용하지 않는다" {
    local r; r=$(_repo_with_base "rng-trailer")
    cd "$r"
    echo x > a.txt
    _mkcommit "$r" "x" >/dev/null
    run bash "$(IMPACT)" declared-track 'upstream...HEAD'
    [ "$status" -eq 0 ]
    [ -z "$(echo "$output" | tr -d '[:space:]')" ]
}
