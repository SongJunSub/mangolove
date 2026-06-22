#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove — Irreversible/Destructive Command Guard (D3b)
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
