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

@test "guard: --strict installs irreversible-guard and wires it into PreToolUse" {
    local proj; proj=$(create_fake_project "guard-install")
    echo '{"name":"app","scripts":{"test":"jest","lint":"eslint ."}}' > "$proj/package.json"
    echo '{}' > "$proj/.eslintrc.json"
    cd "$proj"
    bash "$MANGOLOVE_DIR/lib/project-init.sh" init --strict
    [ -x "$proj/.mangolove/hooks/irreversible-guard.sh" ]
    grep -q "irreversible-guard.sh" "$proj/.claude/settings.json"
}
