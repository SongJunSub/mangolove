#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove: A/B Harness (Phase 4 v2 skeleton)
# 환경 수준 게이트 보호(실측), 결과 채점 엔진(자체검증), 정직 라벨, teeth 를 검증한다.
# ─────────────────────────────────────────────

load test_helper

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

AB() { echo "$MANGOLOVE_DIR/lib/ab-harness.sh"; }

@test "ab: gate protection blocks all dangerous steps in treatment, none in control" {
    run bash "$(AB)" gate
    [ "$status" -eq 0 ]
    # 처치군은 위험 스텝을 전부 차단(5/5), 대조군은 0
    [[ "$output" == *"처치군 5/5"* ]]
    [[ "$output" == *"대조군 0/5"* ]]
}

@test "ab: scoring engine distinguishes good vs bad results (self-test)" {
    run bash "$(AB)" engine
    [ "$status" -eq 0 ]
    [[ "$output" == *"good[build:1 track:1]"* ]]
    [[ "$output" == *"bad[build:0 track:0]"* ]]
}

@test "ab: report shows the gate-protection delta with honest (non-overclaiming) framing" {
    run bash "$(AB)" report
    [ "$status" -eq 0 ]
    [[ "$output" == *"환경 차이, 안전망"* ]]
    [[ "$output" == *"대표 위험 카테고리 5/5 차단"* ]]
    # 과장 금지: '새 측정 아님' + demo arm 명시
    [[ "$output" == *"새 측정 아님"* ]]
    [[ "$output" == *"실제 모델 출력 아님"* ]]
}

@test "ab: report 는 실모델 수치가 없음을 밝히고 내는 방법을 가리킨다" {
    run bash "$(AB)" report
    [[ "$output" == *"실모델 A/B 수치 없음"* ]]
    [[ "$output" == *"mangolove ab live"* ]]
}

# ── live arm: claude plugin eval (실세션 = 과금, opt-in) ──
# 직접 짠 실행기 대신 Claude Code 의 플러그인 eval 을 쓴다: 플러그인이 있는 arm 과 없는 arm 을
# 같은 프롬프트로 돌려 점수 차를 낸다. 여기서는 실세션을 띄우지 않고 배선과 케이스 무결성만 본다.

PLUGIN() { echo "$BATS_TEST_DIRNAME/../cc-plugin"; }

# PATH 앞에 가짜 claude 를 두고 받은 인자를 기록한다. `plugin eval --help` 에는 eval 이 있는
# CLI 처럼 --ablation 이 든 도움말을 낸다($1=old 면 eval 이 없는 CLI 처럼 plugin 도움말만 낸다).
_fake_claude_for_eval() {
    local help_line="  --ablation <mode>"
    [ "${1:-}" = "old" ] && help_line="Usage: claude plugin [options] [command]"
    install_fake_claude <<FAKE
if [ "\${3:-}" = "--help" ]; then echo "$help_line"; exit 0; fi
printf '%s\n' "\$@" > "$TEST_DIR/eval-args"
exit 0
FAKE
}

@test "ab live: 게시하지 않고 대조군과 함께 돌리며 비용 상한을 건다" {
    _fake_claude_for_eval
    run env PATH="$TEST_DIR/fakebin:$PATH" MANGOLOVE_AB_PLUGIN_DIR="$(PLUGIN)" bash "$(AB)" live --runs 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"과금"* ]]
    local a; a="$(tr '\n' ' ' < "$TEST_DIR/eval-args")"
    [[ "$a" == "plugin eval $(PLUGIN) "* ]]
    # 리포트는 기본이 claude.ai 게시다. 요청 없이 외부로 내보내지 않는다.
    [[ "$a" == *"--no-publish"* ]]
    [[ "$a" == *"--ablation with-without"* ]]
    [[ "$a" == *"--max-cost-usd 3"* ]]
    # 사용자가 준 인자는 그대로 뒤에 붙는다
    [[ "$a" == *"--runs 1 " ]]
}

@test "ab live: 비용 상한은 환경변수로 바꿀 수 있다" {
    _fake_claude_for_eval
    run env PATH="$TEST_DIR/fakebin:$PATH" MANGOLOVE_AB_PLUGIN_DIR="$(PLUGIN)" AB_LIVE_MAX_COST_USD=0.5 bash "$(AB)" live
    [ "$status" -eq 0 ]
    grep -qx -- '0.5' "$TEST_DIR/eval-args"
}

@test "ab live: eval 케이스가 없으면 실세션을 띄우지 않는다" {
    _fake_claude_for_eval
    mkdir -p "$TEST_DIR/empty-plugin"
    run env PATH="$TEST_DIR/fakebin:$PATH" MANGOLOVE_AB_PLUGIN_DIR="$TEST_DIR/empty-plugin" bash "$(AB)" live
    [ "$status" -eq 2 ]
    [ ! -e "$TEST_DIR/eval-args" ]
}

@test "ab live: eval 이 없는 낮은 claude 에서는 과금 안내 전에 멈춘다" {
    # 종료코드로는 못 가린다: 없는 서브커맨드에 --help 를 붙여도 claude 는 0 을 낸다.
    _fake_claude_for_eval old
    run env PATH="$TEST_DIR/fakebin:$PATH" MANGOLOVE_AB_PLUGIN_DIR="$(PLUGIN)" bash "$(AB)" live
    [ "$status" -eq 2 ]
    [[ "$output" == *"2.1.269"* ]]
    [[ "$output" != *"과금"* ]]
    [ ! -e "$TEST_DIR/eval-args" ]
}

# $1=evals 디렉토리. 케이스마다 프롬프트와 타입이 있는 grader 가 있는지 보고, 케이스 수를 낸다.
# 케이스가 아닌 것으로 건너뛰는 디렉토리는 이름으로 정해 둔 둘(results, mocks)뿐이다. 그 밖의
# 디렉토리에 prompt.md 도 case.yaml 도 없으면 프롬프트를 빠뜨린 케이스이므로 실패다.
_check_eval_cases() {
    local d g n=0
    for d in "$1"/*/; do
        case "$(basename "$d")" in results|mocks) continue ;; esac
        [ -f "${d}prompt.md" ] || [ -f "${d}case.yaml" ] || { echo "no prompt: $d"; return 1; }
        ls "${d}graders/"*.md >/dev/null 2>&1 || { echo "no graders: $d"; return 1; }
        for g in "${d}graders/"*.md; do
            grep -qE '^type: (regex|tool_used|tool_order|file_exists|llm|baseline)$' "$g" || { echo "bad type: $g"; return 1; }
        done
        n=$((n + 1))
    done
    echo "$n"
}

@test "evals: 모든 케이스가 타입이 있는 grader 를 갖는다" {
    run _check_eval_cases "$(PLUGIN)/evals"
    [ "$status" -eq 0 ]
    [ "$output" -ge 3 ]
}

@test "evals: 프롬프트를 빠뜨린 케이스는 건너뛰지 않고 잡는다" {
    cp -R "$(PLUGIN)/evals" "$TEST_DIR/evals-broken"
    mkdir -p "$TEST_DIR/evals-broken/half-written/graders"
    printf -- '---\ntype: regex\npattern: x\n---\n' > "$TEST_DIR/evals-broken/half-written/graders/g.md"
    run _check_eval_cases "$TEST_DIR/evals-broken"
    [ "$status" -eq 1 ]
    [[ "$output" == *"half-written"* ]]
}

@test "evals: ab live 가 남긴 results/ 는 케이스로 세지 않는다" {
    # 결과 디렉토리는 gitignore 대상이라 눈에 안 띈다. 케이스로 세면 한 번 돌린 뒤 이 테스트가 깨진다.
    cp -R "$(PLUGIN)/evals" "$TEST_DIR/evals"
    mkdir -p "$TEST_DIR/evals/results/2026-10-08T00-00-00"
    echo '{}' > "$TEST_DIR/evals/results/2026-10-08T00-00-00/aggregate-result.json"
    local before
    before="$(_check_eval_cases "$(PLUGIN)/evals")"
    run _check_eval_cases "$TEST_DIR/evals"
    [ "$status" -eq 0 ]
    [ "$output" = "$before" ]
}

@test "evals: 실행 결과 디렉토리는 git 이 무시한다" {
    # 무시 규칙은 루트 .gitignore 가 아니라 cc-plugin/evals/.gitignore 에 있다(루트 파일을 바꾸면
    # 옛 게이트가 줄을 덧붙여 둔 설치본의 업데이트가 막힌다).
    run git -C "$BATS_TEST_DIRNAME/.." check-ignore -q cc-plugin/evals/results/2026-01-01/aggregate-result.json
    [ "$status" -eq 0 ]
}

@test "evals: Skill grader 가 가리키는 스킬이 실제로 플러그인에 있다" {
    # 스킬 이름을 바꾸면 eval 은 조용히 0 점이 된다(스킬이 안 불린 것처럼 보인다).
    local g name n=0
    for g in "$(PLUGIN)"/evals/*/graders/*.md; do
        grep -q '^tool: Skill$' "$g" || continue
        name="$(grep -oE 'mangolove-[a-z-]+' "$g" | head -1)"
        [ -n "$name" ] || { echo "no skill name: $g"; false; }
        [ -f "$(PLUGIN)/skills/$name/SKILL.md" ] || { echo "missing skill $name: $g"; false; }
        n=$((n + 1))
    done
    [ "$n" -ge 1 ]
}

# ── teeth: 안전망이 무너지면 하니스가 잡는가 ──

@test "ab: a broken guard collapses the protection delta and is caught (exit 1)" {
    # 가드를 항상-통과 스텁으로 → 처치군이 위험 스텝을 못 막음 → 안전망 붕괴 감지
    printf '#!/usr/bin/env bash\nexit 0\n' > "$MANGOLOVE_DIR/lib/irreversible-guard.sh"
    run bash "$(AB)" gate
    [ "$status" -eq 1 ]
    [[ "$output" == *"처치군 미차단"* ]]
}

@test "ab: mangolove ab dispatches to the harness" {
    cp "$BATS_TEST_DIRNAME/../bin/mangolove" "$MANGOLOVE_DIR/bin/mangolove"
    chmod +x "$MANGOLOVE_DIR/bin/mangolove"
    run bash "$MANGOLOVE_DIR/bin/mangolove" ab
    [ "$status" -eq 0 ]
    [[ "$output" == *"A/B 하니스"* ]]
}
