#!/usr/bin/env bats
# ─────────────────────────────────────────────
# resume-notice: SessionStart(resume|fork) 훅 계약 테스트
#
# claude v2.1.251 부터 재개 시 SessionStart 훅이 경과 시간, 재전송 토큰 수, 캐시 만료 여부,
# 재캐시 예상 비용을 받는다(v2.1.293 에서 프로브 훅으로 필드와 타입을 확인했다).
# 이 훅은 그 값을 사용자에게 한 줄로 보여줄 뿐이다. 모델에 닿으면 안 되고(닿으면 모델이
# "이어갈까요"를 묻기 시작한다), 무엇을 하라고 권하지도 않는다.
# ─────────────────────────────────────────────

load test_helper

setup() {
    setup_test_env
    HOOK="$MANGOLOVE_DIR/lib/resume-notice.sh"
}

teardown() {
    teardown_test_env
}

# $1=source $2=seconds $3=tokens $4=expired(true|false) $5=usd
_payload() {
    printf '{"session_id":"s1","hook_event_name":"SessionStart","source":"%s","seconds_since_last_response":%s,"context_tokens":%s,"prompt_cache_likely_expired":%s,"estimated_cache_write_usd":%s}' \
        "$1" "$2" "$3" "$4" "$5"
}

# 훅 출력(JSON)에서 사용자에게 보일 문장만 꺼낸다. 출력이 비면 빈 문자열.
_message() {
    [ -n "$output" ] || return 0
    python3 -c 'import json, sys; print(json.loads(sys.argv[1])["systemMessage"])' "$output"
}

@test "resume-notice: 캐시가 만료된 큰 대화를 재개하면 비용을 한 줄로 알린다" {
    command -v python3 >/dev/null 2>&1 || skip "needs python3"
    run bash -c "printf '%s' '$(_payload resume 5400 182340 true 1.1396)' | bash '$HOOK'"
    [ "$status" -eq 0 ]
    # 출력은 systemMessage 하나만 든 JSON 이어야 한다. 일반 텍스트 stdout 은 모델 컨텍스트로 들어간다.
    python3 -c 'import json, sys; assert list(json.loads(sys.argv[1])) == ["systemMessage"]' "$output"
    local m; m="$(_message)"
    [[ "$m" == *"1.14"* ]]
    [[ "$m" == *"182K"* ]]
    [[ "$m" == *"1시간 30분"* ]]
}

@test "resume-notice: 안내는 질문도 권유도 아니다 (끊을 시점은 사용자가 판단한다)" {
    command -v python3 >/dev/null 2>&1 || skip "needs python3"
    run bash -c "printf '%s' '$(_payload resume 86400 800000 true 6.40)' | bash '$HOOK'"
    [ "$status" -eq 0 ]
    local m; m="$(_message)"
    [ -n "$m" ]
    [[ "$m" != *"?"* ]]
    [[ "$m" != *"/clear"* ]]
    [[ "$m" != *"/compact"* ]]
    [[ "$m" != *"권장"* ]]
}

@test "resume-notice: 출력은 ASCII 뿐이다 (UTF-8 이 아닌 로케일에서도 사라지지 않는다)" {
    command -v python3 >/dev/null 2>&1 || skip "needs python3"
    run bash -c "printf '%s' '$(_payload resume 5400 182340 true 1.1396)' | LC_ALL=en_US.ISO8859-1 bash '$HOOK'"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    ! printf '%s' "$output" | LC_ALL=C grep -q '[^ -~]'
    [[ "$(_message)" == *"1시간 30분"* ]]
}

@test "resume-notice: 단위는 반올림한 뒤에 고른다 (999,600 토큰은 1.0M)" {
    command -v python3 >/dev/null 2>&1 || skip "needs python3"
    run bash -c "printf '%s' '$(_payload resume 7200 999600 true 8.00)' | bash '$HOOK'"
    [ "$status" -eq 0 ]
    local m; m="$(_message)"
    [[ "$m" == *"1.0M"* ]]
    [[ "$m" != *"1000K"* ]]
}

@test "resume-notice: 임계 값이 숫자가 아니어도 안내가 꺼지지 않는다" {
    command -v python3 >/dev/null 2>&1 || skip "needs python3"
    run bash -c "printf '%s' '$(_payload resume 5400 182340 true 1.1396)' | MANGOLOVE_RESUME_NOTICE_MIN_USD=abc bash '$HOOK'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"systemMessage"* ]]
}

@test "resume-notice: 캐시가 살아 있으면 조용하다" {
    run bash -c "printf '%s' '$(_payload resume 600 500000 false 4.00)' | bash '$HOOK'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "resume-notice: 재캐시 비용이 작으면 조용하다" {
    run bash -c "printf '%s' '$(_payload resume 7200 46937 true 0.0094)' | bash '$HOOK'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "resume-notice: fork 도 같은 필드를 받으므로 같이 다룬다" {
    command -v python3 >/dev/null 2>&1 || skip "needs python3"
    run bash -c "printf '%s' '$(_payload fork 7200 300000 true 2.40)' | bash '$HOOK'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"systemMessage"* ]]
    [[ "$output" == *"2.40"* ]]
}

@test "resume-notice: 재개 필드가 없는 payload(새 세션 등)는 조용히 통과한다" {
    run bash -c "printf '%s' '{\"session_id\":\"s1\",\"hook_event_name\":\"SessionStart\",\"source\":\"startup\"}' | bash '$HOOK'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "resume-notice: 깨진 입력에도 세션 시작을 막지 않는다 (fail-open, 출력 없음)" {
    run bash -c "printf '%s' 'not json {' | bash '$HOOK'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    run bash -c "printf '' | bash '$HOOK'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "resume-notice: 타입이 어긋난 필드는 추정하지 않고 넘긴다" {
    # 문자열 "true" 는 boolean true 가 아니다. 비용이 숫자가 아니면 계산하지 않는다.
    run bash -c "printf '%s' '{\"source\":\"resume\",\"seconds_since_last_response\":5400,\"context_tokens\":182340,\"prompt_cache_likely_expired\":\"true\",\"estimated_cache_write_usd\":\"1.1396\"}' | bash '$HOOK'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
