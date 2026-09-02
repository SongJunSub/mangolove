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

# 위와 같되 usage.speed 를 실어 fast mode 프리미엄 단가 적용을 검증한다.
_write_output_only_session_speed() {
    local model="$1" out_tokens="$2" speed="$3" file="$4"
    printf '%s\n' \
      "{\"message\":{\"model\":\"$model\",\"usage\":{\"input_tokens\":0,\"output_tokens\":$out_tokens,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0,\"speed\":\"$speed\"}}}" \
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
    # 구버그였다면 $75.00 이 나왔어야 한다: 회귀 방지
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

# ── Claude 5 계열 회귀 (Opus 5 / Sonnet 5 / Fable 5 / fast mode) ──
# Sonnet 5 는 Sonnet 4.6($3/$15)보다 싸다($2/$10). 4.6 단가를 재사용하면 50% 과대 계상된다.

@test "opus 5 1M output → \$25.00 (현행 Opus 단가)" {
    _write_output_only_session "claude-opus-5" 1000000 "$PROJ_DIR/o5.jsonl"
    _run_cost
    [ "$status" -eq 0 ]
    [[ "$output" == *"25.00"* ]]
}

@test "sonnet 5 1M output → \$10.00 (sonnet 4.6 의 \$15 아님)" {
    _write_output_only_session "claude-sonnet-5" 1000000 "$PROJ_DIR/s5.jsonl"
    _run_cost
    [ "$status" -eq 0 ]
    [[ "$output" == *"10.00"* ]]
    [[ "$output" != *"15.00"* ]]
}

@test "fable 5 1M output → \$50.00" {
    _write_output_only_session "claude-fable-5" 1000000 "$PROJ_DIR/f5.jsonl"
    _run_cost
    [ "$status" -eq 0 ]
    [[ "$output" == *"50.00"* ]]
}

@test "opus 5 fast mode 1M output → \$50.00 (표준 \$25 의 프리미엄 단가)" {
    _write_output_only_session_speed "claude-opus-5" 1000000 "fast" "$PROJ_DIR/o5f.jsonl"
    _run_cost
    [ "$status" -eq 0 ]
    [[ "$output" == *"50.00"* ]]
}

@test "speed=standard 는 표준 단가 그대로 (\$25.00)" {
    _write_output_only_session_speed "claude-opus-5" 1000000 "standard" "$PROJ_DIR/o5s.jsonl"
    _run_cost
    [ "$status" -eq 0 ]
    [[ "$output" == *"25.00"* ]]
}

# ── 모델 id 변형 접미사 (실측: 'claude-opus-5[1m]' 이 실제 세션 레코드에 존재한다) ──
# 정규화가 없으면 [1m] 이 붙은 순간 정확 일치 표를 빗나가 접두사 폴백으로 새고,
# 교정한 Sonnet 5 단가와 fast 프리미엄 과금이 조용히 무효가 된다.

@test "sonnet 5 [1m] 변형도 sonnet 5 단가(\$10/M), 접두사 폴백(\$15) 아님" {
    _write_output_only_session "claude-sonnet-5[1m]" 1000000 "$PROJ_DIR/s5m.jsonl"
    _run_cost
    [ "$status" -eq 0 ]
    [[ "$output" == *"10.00"* ]]
    [[ "$output" != *"15.00"* ]]
}

@test "opus 5 [1m] fast 도 fast 단가(\$50/M), 정확 일치 실패로 표준 단가 되지 않는다" {
    _write_output_only_session_speed "claude-opus-5[1m]" 1000000 "fast" "$PROJ_DIR/o5mf.jsonl"
    _run_cost
    [ "$status" -eq 0 ]
    [[ "$output" == *"50.00"* ]]
}

@test "날짜 스냅샷 접미사(-20251001)도 기본 모델 단가로 정규화된다" {
    _write_output_only_session "claude-haiku-4-5-20251001" 1000000 "$PROJ_DIR/h5d.jsonl"
    _run_cost
    [ "$status" -eq 0 ]
    [[ "$output" == *"5.00"* ]]
}

# ─────────────────────────────────────────────
# cost sessions: 세션별 집중도 뷰
#
# 왜 별도 뷰가 필요한가: show_cost 는 프로젝트별로 합산해서 "세션 하나가 얼마나
# 컸는가"가 구조적으로 안 보인다. 실측에서 비용은 세션 크기에 극단적으로 쏠렸다.
# 아래 테스트는 전부 고정 픽스처로 돈다 (~/.claude 라이브 데이터에 의존하지 않는다:
# CI 머신엔 그 데이터가 아예 없고, 있어도 실행 시점마다 값이 달라진다).
# ─────────────────────────────────────────────

# usage 레코드 한 줄. $1=model $2=input $3=output $4=cache_write $5=cache_read
_usage_line() {
    printf '{"message":{"model":"%s","usage":{"input_tokens":%s,"output_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s}}}\n' \
        "$1" "$2" "$3" "$4" "$5"
}

_run_sessions() {
    run env MANGOLOVE_COST_PROJECTS_DIR="$TEST_DIR/claude-projects" \
            MANGOLOVE_DIR="$MANGOLOVE_DIR" \
            ${ML_LONG_TURNS:+ML_LONG_TURNS="$ML_LONG_TURNS"} \
            ${ML_TOP_N:+ML_TOP_N="$ML_TOP_N"} \
            bash "$MANGOLOVE_DIR/lib/cost-tracker.sh" sessions all
}

@test "cost sessions: 세션 단위로 집계한다 (프로젝트 합산이 아니다)" {
    # 같은 프로젝트에 세션 2개. 프로젝트 뷰라면 한 줄로 합쳐진다.
    _usage_line "claude-opus-5" 0 1000000 0 0 > "$PROJ_DIR/aaaaaaaa-1.jsonl"
    _usage_line "claude-opus-5" 0  200000 0 0 > "$PROJ_DIR/bbbbbbbb-2.jsonl"
    _run_sessions
    [ "$status" -eq 0 ]
    [[ "$output" == *"aaaaaaaa"* ]]
    [[ "$output" == *"bbbbbbbb"* ]]
    [[ "$output" == *"세션 2개"* ]]
    # opus output $25/M → 각각 $25.00, $5.00
    [[ "$output" == *'$25.00'* ]]
    [[ "$output" == *'$5.00'* ]]
}

@test "cost sessions: peak ctx 는 러닝 max 다 (턴별 합산이 아니다)" {
    # 세 턴: context 가 100K → 500K → 200K. peak 는 500K 여야 하고, 합(800K)이면 안 된다.
    {
        _usage_line "claude-opus-5" 100000 1 0 0
        _usage_line "claude-opus-5" 0      1 0 500000
        _usage_line "claude-opus-5" 0      1 0 200000
    } > "$PROJ_DIR/cccccccc-3.jsonl"
    _run_sessions
    [ "$status" -eq 0 ]
    [[ "$output" == *"500.0K"* ]]
    [[ "$output" != *"800.0K"* ]]
}

@test "cost sessions: peak ctx 는 한 요청의 input+cache write+cache read 합이다" {
    # 한 턴 안에서 세 버킷이 함께 온다: 40K+10K+50K = 100K 가 그 요청의 컨텍스트다.
    _usage_line "claude-opus-5" 40000 1 10000 50000 > "$PROJ_DIR/dddddddd-4.jsonl"
    _run_sessions
    [ "$status" -eq 0 ]
    [[ "$output" == *"100.0K"* ]]
}

@test "cost sessions: 집중도 비율이 산술적으로 맞다" {
    # 두 세션: $75.00 과 $25.00 → 총 $100.00, 상위 1세션이 75.0%
    ML_TOP_N=1
    _usage_line "claude-opus-5" 0 3000000 0 0 > "$PROJ_DIR/eeeeeeee-5.jsonl"
    _usage_line "claude-opus-5" 0 1000000 0 0 > "$PROJ_DIR/ffffffff-6.jsonl"
    _run_sessions
    [ "$status" -eq 0 ]
    [[ "$output" == *"총비용 \$100.00"* ]]
    [[ "$output" == *"상위 1세션이 총비용의 75.0%"* ]]
}

@test "cost sessions: 턴 임계는 재정의 가능하고 그 코호트 비용을 낸다" {
    ML_LONG_TURNS=3
    # 턴 3개짜리 비싼 세션 + 턴 1개짜리 싼 세션
    {
        _usage_line "claude-opus-5" 0 1000000 0 0
        _usage_line "claude-opus-5" 0 1000000 0 0
        _usage_line "claude-opus-5" 0 1000000 0 0
    } > "$PROJ_DIR/99999999-7.jsonl"
    _usage_line "claude-opus-5" 0 1000000 0 0 > "$PROJ_DIR/88888888-8.jsonl"
    _run_sessions
    [ "$status" -eq 0 ]
    # 턴 3+ 세션은 1개, $75 / $100 = 75.0%
    [[ "$output" == *"턴 3+ 세션 1개가 총비용의 75.0%"* ]]
}

@test "cost sessions: 데이터가 없으면 조용히 안내한다 (오류 아님)" {
    _run_sessions
    [ "$status" -eq 0 ]
    [[ "$output" == *"No session data found"* ]]
}

@test "cost sessions: usage 레코드가 없는 세션 파일은 세지 않는다" {
    printf '{"type":"summary","summary":"x"}\n' > "$PROJ_DIR/77777777-9.jsonl"
    _usage_line "claude-opus-5" 0 1000000 0 0 > "$PROJ_DIR/66666666-a.jsonl"
    _run_sessions
    [ "$status" -eq 0 ]
    [[ "$output" == *"세션 1개"* ]]
    [[ "$output" != *"77777777"* ]]
}
