#!/usr/bin/env bats
# ─────────────────────────────────────────────
# cost-tracker: 모델별 단가 적용 회귀 테스트
#
# 회귀 대상 버그: 전 세션에 Opus 단가($15/$75)를 평면 적용해
#   (a) 경량 모델(sonnet/haiku) 비용을 과대 계상하고
#   (b) 그 Opus 값마저 구형이라 현행 Opus($5/$25)의 3배로 계산했다.
# 이제 세션 레코드의 message.model 에 따라 레코드 단위로 단가를 적용한다.
# ─────────────────────────────────────────────

load test_helper

setup() {
    setup_test_env
    PROJ_DIR="$TEST_DIR/claude-projects/-Users-demo-Project-app"
    mkdir -p "$PROJ_DIR"
}

teardown() {
    teardown_test_env
}

# 단일 usage 레코드 세션 파일 생성 (output_tokens 만, 다른 버킷은 0)
_write_output_only_session() {
    local model="$1" out_tokens="$2" file="$3"
    printf '%s\n' \
      "{\"message\":{\"model\":\"$model\",\"usage\":{\"input_tokens\":0,\"output_tokens\":$out_tokens,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}}}" \
      > "$file"
}

_run_cost() {
    run env MANGOLOVE_COST_PROJECTS_DIR="$TEST_DIR/claude-projects" \
            MANGOLOVE_DIR="$MANGOLOVE_DIR" \
            bash "$MANGOLOVE_DIR/lib/cost-tracker.sh" all
}

@test "sonnet 1M output → sonnet 단가(\$15/M) = \$15.00 (구 Opus \$75 아님)" {
    _write_output_only_session "claude-sonnet-4-6" 1000000 "$PROJ_DIR/s.jsonl"
    _run_cost
    [ "$status" -eq 0 ]
    [[ "$output" == *'$15.00'* ]]
    # 구버그였다면 $75.00 이 나왔어야 한다 — 회귀 방지
    [[ "$output" != *'$75.00'* ]]
}

@test "opus 1M output → 현행 opus 단가(\$25/M) = \$25.00 (구형 \$75 아님)" {
    _write_output_only_session "claude-opus-4-8" 1000000 "$PROJ_DIR/o.jsonl"
    _run_cost
    [ "$status" -eq 0 ]
    [[ "$output" == *'$25.00'* ]]
    [[ "$output" != *'$75.00'* ]]
}

@test "haiku 1M output → haiku 단가(\$5/M) = \$5.00" {
    _write_output_only_session "claude-haiku-4-5" 1000000 "$PROJ_DIR/h.jsonl"
    _run_cost
    [ "$status" -eq 0 ]
    [[ "$output" == *'$5.00'* ]]
}

@test "미상 모델은 현행 Opus 단가로 폴백(\$25/M)" {
    _write_output_only_session "claude-unknown-9" 1000000 "$PROJ_DIR/u.jsonl"
    _run_cost
    [ "$status" -eq 0 ]
    [[ "$output" == *'$25.00'* ]]
}

@test "cache read 는 input×0.1 로 계산된다 (sonnet input \$3 → cache read \$0.3/M)" {
    # cache_read 1M, sonnet: 1e6 * (3.0 * 0.1) / 1e6 = 0.30
    printf '%s\n' \
      "{\"message\":{\"model\":\"claude-sonnet-4-6\",\"usage\":{\"input_tokens\":0,\"output_tokens\":0,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":1000000}}}" \
      > "$PROJ_DIR/c.jsonl"
    _run_cost
    [ "$status" -eq 0 ]
    [[ "$output" == *'$.30'* || "$output" == *'$0.30'* ]]
}
