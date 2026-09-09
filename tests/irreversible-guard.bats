#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove: Irreversible/Destructive Command Guard (D3b)
# 비가역 명령을 실행 전에 차단(exit 2)하고, 양성 명령은 통과시키는지 검증한다.
# ─────────────────────────────────────────────

load test_helper

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

_guard() { echo "$MANGOLOVE_DIR/lib/irreversible-guard.sh"; }

# 명령 문자열을 Claude PreToolUse JSON 으로 감싼다 (내부 큰따옴표는 이스케이프).
_json() {
    local c="${1//\"/\\\"}"
    printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$c"
}

@test "guard: blocks git push --force" {
    run bash "$(_guard)" <<< "$(_json 'git push --force origin main')"
    [ "$status" -eq 2 ]
}

@test "guard: allows git push --force-with-lease" {
    run bash "$(_guard)" <<< "$(_json 'git push --force-with-lease origin feature')"
    [ "$status" -eq 0 ]
}

@test "guard: blocks git push -f" {
    run bash "$(_guard)" <<< "$(_json 'git push -f origin main')"
    [ "$status" -eq 2 ]
}

@test "guard: blocks git reset --hard" {
    run bash "$(_guard)" <<< "$(_json 'git reset --hard origin/main')"
    [ "$status" -eq 2 ]
}

@test "guard: blocks DROP TABLE" {
    run bash "$(_guard)" <<< "$(_json 'psql -c "DROP TABLE users"')"
    [ "$status" -eq 2 ]
}

@test "guard: blocks DELETE without WHERE" {
    run bash "$(_guard)" <<< "$(_json 'mysql -e "DELETE FROM orders"')"
    [ "$status" -eq 2 ]
}

@test "guard: allows DELETE with WHERE" {
    run bash "$(_guard)" <<< "$(_json 'mysql -e "DELETE FROM orders WHERE id = 1"')"
    [ "$status" -eq 0 ]
}

@test "guard: blocks kubectl delete" {
    run bash "$(_guard)" <<< "$(_json 'kubectl delete pod my-pod')"
    [ "$status" -eq 2 ]
}

@test "guard: blocks terraform destroy" {
    run bash "$(_guard)" <<< "$(_json 'terraform destroy -auto-approve')"
    [ "$status" -eq 2 ]
}

@test "guard: blocks rm -rf on dangerous root" {
    run bash "$(_guard)" <<< "$(_json 'rm -rf /')"
    [ "$status" -eq 2 ]
}

@test "guard: allows a benign command" {
    run bash "$(_guard)" <<< "$(_json 'git status')"
    [ "$status" -eq 0 ]
}

@test "guard: allows a normal commit" {
    run bash "$(_guard)" <<< "$(_json 'git commit -m fix')"
    [ "$status" -eq 0 ]
}

@test "guard: MANGOLOVE_ALLOW_DANGER=1 allows a blocked command (audited)" {
    export MANGOLOVE_ALLOW_DANGER=1
    run bash "$(_guard)" <<< "$(_json 'git push --force origin main')"
    [ "$status" -eq 0 ]
}

@test "guard: blocks --force even with --force-with-lease=ref present" {
    run bash "$(_guard)" <<< "$(_json 'git push --force-with-lease=main --force origin main')"
    [ "$status" -eq 2 ]
}

@test "guard: blocks rm -rf with a quoted root path" {
    run bash "$(_guard)" <<< "$(_json 'rm -rf "/"')"
    [ "$status" -eq 2 ]
}

@test "guard: blocks rm with separated flags" {
    run bash "$(_guard)" <<< "$(_json 'rm -r -f /')"
    [ "$status" -eq 2 ]
}

@test "guard: blocks rm with long flags" {
    run bash "$(_guard)" <<< "$(_json 'rm --recursive --force /')"
    [ "$status" -eq 2 ]
}

@test "guard: allows rm -rf on a relative project dir" {
    run bash "$(_guard)" <<< "$(_json 'rm -rf node_modules')"
    [ "$status" -eq 0 ]
}

@test "guard: blocks TRUNCATE without TABLE via a sql client" {
    run bash "$(_guard)" <<< "$(_json 'psql -c "TRUNCATE users"')"
    [ "$status" -eq 2 ]
}

@test "guard: blocks DELETE without WHERE when WHERE is in another statement" {
    run bash "$(_guard)" <<< "$(_json 'psql -c "DELETE FROM logs; SELECT 1 FROM t WHERE id=1"')"
    [ "$status" -eq 2 ]
}

@test "guard: allows echo containing SQL keywords" {
    run bash "$(_guard)" <<< "$(_json 'echo "next step: DROP TABLE staging"')"
    [ "$status" -eq 0 ]
}

@test "guard: allows a commit message mentioning DROP TABLE" {
    run bash "$(_guard)" <<< "$(_json 'git commit -m "fix: handle DROP TABLE in parser"')"
    [ "$status" -eq 0 ]
}

@test "guard: allows grep for a SQL keyword" {
    run bash "$(_guard)" <<< "$(_json 'grep -rn "DROP TABLE" migrations/')"
    [ "$status" -eq 0 ]
}

# ── Mongo 파괴 구문 + 동적 경로 rm (커버리지 갭 보강) ──

@test "guard: blocks Mongo deleteMany with empty filter" {
    run bash "$(_guard)" <<< "$(_json 'mongosh --eval "db.users.deleteMany({})"')"
    [ "$status" -eq 2 ]
}

@test "guard: blocks Mongo dropDatabase" {
    run bash "$(_guard)" <<< "$(_json 'mongosh mydb --eval "db.dropDatabase()"')"
    [ "$status" -eq 2 ]
}

@test "guard: blocks Mongo collection drop" {
    run bash "$(_guard)" <<< "$(_json 'mongosh --eval "db.sessions.drop()"')"
    [ "$status" -eq 2 ]
}

@test "guard: allows Mongo deleteMany with a filter (precision)" {
    run bash "$(_guard)" <<< "$(_json 'mongosh --eval "db.users.deleteMany({status:1})"')"
    [ "$status" -eq 0 ]
}

@test "guard: allows Mongo find read" {
    run bash "$(_guard)" <<< "$(_json 'mongosh --eval "db.users.find({})"')"
    [ "$status" -eq 0 ]
}

@test "guard: blocks rm -rf on PWD env var" {
    run bash "$(_guard)" <<< "$(_json 'rm -rf $PWD')"
    [ "$status" -eq 2 ]
}

@test "guard: blocks rm -rf on HOME brace var" {
    run bash "$(_guard)" <<< "$(_json 'rm -rf ${HOME}')"
    [ "$status" -eq 2 ]
}

@test "guard: blocks rm -rf on pwd command substitution" {
    run bash "$(_guard)" <<< "$(_json 'rm -rf $(pwd)')"
    [ "$status" -eq 2 ]
}

@test "guard: allows rm -rf on a TMPDIR subpath (precision)" {
    run bash "$(_guard)" <<< "$(_json 'rm -rf $TMPDIR/cache')"
    [ "$status" -eq 0 ]
}

@test "guard: blocks Mongo deleteMany with escaped-whitespace empty filter" {
    run bash "$(_guard)" <<< "$(_json 'mongosh --eval "db.users.deleteMany({\n})"')"
    [ "$status" -eq 2 ]
}

@test "guard: blocks Mongo drop with escaped-whitespace args" {
    run bash "$(_guard)" <<< "$(_json 'mongosh --eval "db.sessions.drop(\n)"')"
    [ "$status" -eq 2 ]
}

@test "guard: allows Mongo deleteMany with a nested filter (precision)" {
    run bash "$(_guard)" <<< "$(_json 'mongosh --eval "db.users.deleteMany({age:{gt:30}})"')"
    [ "$status" -eq 0 ]
}

# ── push --delete 가 force-push 로 오탐되던 회귀 (force 검출을 push 세그먼트에 앵커링) ──

@test "guard: allows remote branch delete (long form)" {
    run bash "$(_guard)" <<< "$(_json 'git push origin --delete BKO-2224')"
    [ "$status" -eq 0 ]
}

@test "guard: allows remote branch delete (flag-first form)" {
    run bash "$(_guard)" <<< "$(_json 'git push --delete origin feature/BKO-2224')"
    [ "$status" -eq 0 ]
}

@test "guard: allows remote branch delete (colon refspec)" {
    run bash "$(_guard)" <<< "$(_json 'git push origin :BKO-2224')"
    [ "$status" -eq 0 ]
}

@test "guard: allows push --delete chained with rm -f cleanup" {
    run bash "$(_guard)" <<< "$(_json 'git push origin --delete BKO-2224 && rm -f stale.log')"
    [ "$status" -eq 0 ]
}

@test "guard: allows push --delete chained with worktree remove --force" {
    run bash "$(_guard)" <<< "$(_json 'git push origin --delete BKO-2224 && git worktree remove --force ../wt')"
    [ "$status" -eq 0 ]
}

@test "guard: allows rm -f cleanup chained before push --delete" {
    run bash "$(_guard)" <<< "$(_json 'rm -f tmp.txt && git push origin --delete BKO-2224')"
    [ "$status" -eq 0 ]
}

@test "guard: still blocks real --force when chained after a safe command" {
    run bash "$(_guard)" <<< "$(_json 'git status && git push --force origin main')"
    [ "$status" -eq 2 ]
}

@test "guard: still blocks real -f when chained after a safe command" {
    run bash "$(_guard)" <<< "$(_json 'git fetch origin && git push -f origin main')"
    [ "$status" -eq 2 ]
}

# ── Jul-10 회수분: JSON 이스케이프(\n\r\t) 치환, push -f 대소문자 구분, rm 세그먼트 단위 검사 ──
# 아래는 모두 구버전에서 오탐 차단(또는 실제 위험을 오검 통과)하던 케이스다.

@test "guard: allows multi-line safe push, unrelated commit -F on next line (\\n = 경계)" {
    # 구버전: \n 이 글자 n 으로 붙어 push 세그먼트가 통째로 잡히고 -F 가 -f(대소문자무시)로 오탐 → 차단.
    run bash "$(_guard)" <<< "$(_json 'git push origin main\ngit commit -F -')"
    [ "$status" -eq 0 ]
}

@test "guard: allows rm -rf relative dir chained with a command touching root" {
    # 구버전: 명령 전체에서 -r/-f/'/' 를 모아 봐서 'rm -rf build' + 'ls /' 조합을 오탐 → 차단.
    run bash "$(_guard)" <<< "$(_json 'rm -rf build && ls /')"
    [ "$status" -eq 0 ]
}

@test "guard: allows safe rm then a root-path command across a newline (per-segment)" {
    run bash "$(_guard)" <<< "$(_json 'rm -rf build\ncat /etc/hosts')"
    [ "$status" -eq 0 ]
}

@test "guard: allows a commit message that merely mentions rm -rf /" {
    # rm 이 구분자(^;|&) 뒤가 아니라 문장 중간이라 실제 명령이 아님 → 세그먼트로 추출되지 않음.
    run bash "$(_guard)" <<< "$(_json 'git commit -m "chore: drop rm -rf / shim"')"
    [ "$status" -eq 0 ]
}

@test "guard: blocks a real rm -rf / that follows a newline (\\n = 경계, 오검 보완)" {
    # 구버전: \n→n 으로 'hinrm' 이 되어 rm 앵커를 놓치고 통과(false negative). 신버전은 차단.
    run bash "$(_guard)" <<< "$(_json 'echo hi\nrm -rf /')"
    [ "$status" -eq 2 ]
}

# ── 임시 스크래치 예외 (정밀도 개선) ────────────────────────────
# 가드가 임시 디렉토리 하위까지 막으면 MangoLove 자신이 지시한 스크래치 워크플로가 막힌다.
# 그러면 사용자는 MANGOLOVE_ALLOW_DANGER=1 을 습관적으로 붙이게 되고, 그게 진짜 위험이다.
# 예외는 '증명된 경우'에만 준다: 모든 피연산자가 임시 루트 아래의 리터럴 경로일 때만.

@test "guard: allows recursive delete of a subpath under /tmp (scratch cleanup)" {
    run bash "$(_guard)" <<< "$(_json 'rm -rf /tmp/mangolove-scratch')"
    [ "$status" -eq 0 ]
}

@test "guard: allows recursive delete under the harness scratchpad" {
    run bash "$(_guard)" <<< "$(_json 'rm -rf /private/tmp/claude-501/sess/scratchpad/e2e')"
    [ "$status" -eq 0 ]
}

@test "guard: allows recursive delete under macOS temp (/var/folders)" {
    run bash "$(_guard)" <<< "$(_json 'rm -rf /var/folders/xy/T/build')"
    [ "$status" -eq 0 ]
}

@test "guard: still blocks deleting the temp root itself" {
    run bash "$(_guard)" <<< "$(_json 'rm -rf /tmp')"
    [ "$status" -eq 2 ]
    run bash "$(_guard)" <<< "$(_json 'rm -rf /tmp/')"
    [ "$status" -eq 2 ]
}

@test "guard: still blocks a glob under temp (실제 대상을 알 수 없다)" {
    # 회귀 방지: 단어 분리는 경로 확장을 수행하므로, 분해한 뒤에 검사하면 글롭 문자가
    # 이미 실제 경로들로 바뀌어 사라진다. 반드시 분해 전 원문에서 봐야 한다.
    run bash "$(_guard)" <<< "$(_json 'rm -rf /tmp/[ab]')"
    [ "$status" -eq 2 ]
}

@test "guard: still blocks a variable expansion under temp" {
    run bash "$(_guard)" <<< "$(_json 'rm -rf /tmp/$SOMEVAR')"
    [ "$status" -eq 2 ]
}

@test "guard: still blocks parent traversal out of temp" {
    run bash "$(_guard)" <<< "$(_json 'rm -rf /tmp/x/../../etc')"
    [ "$status" -eq 2 ]
}

@test "guard: one non-temp operand voids the exception" {
    run bash "$(_guard)" <<< "$(_json 'rm -rf /tmp/a /etc')"
    [ "$status" -eq 2 ]
}



# ── heredoc 오탐 (실사용을 막고 있었다) ────────────────────────
#
# 가드는 셸을 파싱하지 않고 명령 문자열을 본다. 문서나 스크립트를 heredoc 으로 쓰면서
# 본문에 위험 명령을 적으면 그것을 실행으로 오인해 무관한 작업이 막혔다.
# 위험 문자열은 조각내어 만든다: 이 테스트 파일 자체가 가드에 걸리지 않게 한다.

@test "guard heredoc: 문서 본문에 적은 위험 명령을 실행으로 오인하지 않는다" {
    local danger="r""m -rf /"
    run bash "$(_guard)" <<< "$(_json "cat > doc.md <<MD\ncaution: ${danger} is forbidden\nMD")"
    [ "$status" -eq 0 ]
}

@test "guard heredoc: 파이썬 본문의 force push 문자열도 오인하지 않는다" {
    local pu="pu""sh" fo="--fo""rce"
    run bash "$(_guard)" <<< "$(_json "python3 - <<PY\nprint('git ${pu} ${fo}')\nPY")"
    [ "$status" -eq 0 ]
}

@test "guard heredoc: 셸이 소비하는 heredoc 의 위험 명령은 여전히 잡는다" {
    local danger="r""m -rf /"
    run bash "$(_guard)" <<< "$(_json "bash <<SH\n${danger}\nSH")"
    [ "$status" -eq 2 ]
}

@test "guard heredoc: 본문을 벗겨도 그 뒤의 진짜 위험 명령은 잡는다" {
    local danger="r""m -rf /"
    run bash "$(_guard)" <<< "$(_json "cat > d.md <<MD\ndoc\nMD\n${danger}")"
    [ "$status" -eq 2 ]
}
