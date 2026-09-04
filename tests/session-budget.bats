#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove: session context budget (Stop hook) 계약 테스트
#
# 계약 6분기 + 회귀 3건:
#   임계 미만 → allow / 최초 도달 → block(exit 2) + 원장 / 같은 버킷 재발화 → allow
#   다음 버킷 → 다시 block / stop_hook_active → allow / off → allow / 쓰기 실패 → allow
# 회귀: 따옴표 없는 boolean 파싱, 8진수 임계값, 동시 세션이 서로를 리셋하지 않음
# 기본 임계(400K)는 픽스처와 무관하게 별도 테스트가 고정한다(드리프트 방지)
# ─────────────────────────────────────────────

setup() {
    REPO="$BATS_TEST_DIRNAME/.."
    GATE="$REPO/lib/session-budget.sh"
    TMP="$(mktemp -d)"
    # 훅이 상태를 쓰는 곳과 효능 원장을 격리한다
    export MANGOLOVE_DIR="$TMP/home"
    mkdir -p "$MANGOLOVE_DIR/lib"
    cp "$REPO/lib/efficacy-recorder.sh" "$MANGOLOVE_DIR/lib/"
    PROJ="$TMP/proj"; mkdir -p "$PROJ"
    TRANSCRIPT="$TMP/session.jsonl"
    # 버킷 경계 계산이 읽기 쉬운 고정값 하나를 여기서 준다(기본값이 아니라 픽스처다).
    # 매 호출에 붙이면 임계값 자체를 검증하는 특이 케이스(=abc, =0500000)가 똑같이
    # 생긴 줄들 사이에 묻힌다. 실제 기본값은 아래 "기본 임계" 테스트가 따로 고정한다.
    export GATE TMP PROJ TRANSCRIPT
    export MANGOLOVE_SESSION_BUDGET_TOKENS=200000
}

teardown() {
    [ -n "${TMP:-}" ] && rm -rf "$TMP"
}

# usage 레코드 한 줄을 transcript 에 쓴다. $1 = 그 요청의 컨텍스트 토큰 수(cache_read 로 싣는다)
write_ctx() {
    printf '{"message":{"model":"claude-opus-5","usage":{"input_tokens":0,"output_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":%s}}}\n' \
        "$1" >> "$TRANSCRIPT"
}

# Stop payload. $1 = session_id, $2 = stop_hook_active (true/false)
run_budget() {
    printf '{"hook_event_name":"Stop","session_id":"%s","cwd":"%s","transcript_path":"%s","stop_hook_active":%s}' \
        "${1:-S-A}" "$PROJ" "$TRANSCRIPT" "${2:-false}" | bash "$GATE"
}

ledger() { cat "$MANGOLOVE_DIR"/efficacy/*.jsonl 2>/dev/null; }

@test "session-budget: 임계 미만이면 통과하고 상태 파일도 만들지 않는다" {
    write_ctx 100000
    run run_budget
    [ "$status" -eq 0 ]
    # 절대다수 턴이 지나는 경로다: 상태 읽기/쓰기가 없어야 한다
    [ ! -d "$MANGOLOVE_DIR/state/session-budget" ]
}

@test "session-budget: 임계 최초 도달 → block(exit 2) 하고 안내를 stderr 로 낸다" {
    write_ctx 520000
    run run_budget
    [ "$status" -eq 2 ]
    [[ "$output" == *"세션 예산"* ]]
    [[ "$output" == *"/clear"* ]]
    [[ "$output" == *"/compact"* ]]
    [[ "$output" == *"/rewind"* ]]
    # 끊는 비용을 낮추는 경로를 함께 줘야 안내가 실행된다
    [[ "$output" == *".progress.md"* ]]
    [[ "$output" == *"resume"* ]]
    # 차단이 아니라 안내임을 모델에게 밝힌다 (과잉 해석 방지)
    [[ "$output" == *"차단이 아니라 안내"* ]]
}

@test "session-budget: 통지는 원장에 block 으로 남는다 (skip 이 아니다)" {
    write_ctx 520000
    run run_budget
    [ "$status" -eq 2 ]
    run ledger
    [[ "$output" == *'"type":"block"'* ]]
    [[ "$output" == *'"phase":"budget"'* ]]
}

@test "session-budget: 같은 버킷에서는 다시 알리지 않는다" {
    write_ctx 520000
    run run_budget
    [ "$status" -eq 2 ]
    # 컨텍스트가 더 늘었지만 아직 같은 버킷(400K~800K)
    write_ctx 600000
    run run_budget
    [ "$status" -eq 0 ]
}

@test "session-budget: 다음 버킷에 도달하면 다시 알린다 (버킷은 배증한다)" {
    # 임계 200K 의 버킷은 200K, 400K, 800K ... 로 배증한다. 등차(임계/2)로 하면
    # 1M 세션에서 알림이 9회 나는데, 배증이면 3회다. 길어질수록 간격이 벌어지는 쪽이 옳다.
    write_ctx 520000     # 400K 버킷
    run run_budget
    [ "$status" -eq 2 ]
    write_ctx 600000     # 여전히 400K 버킷
    run run_budget
    [ "$status" -eq 0 ]
    write_ctx 900000     # 800K 버킷 진입
    run run_budget
    [ "$status" -eq 2 ]
}

@test "session-budget: stop_hook_active=true (따옴표 없는 boolean) 이면 관여하지 않는다" {
    # 회귀: _json_str 은 값 양쪽에 따옴표를 요구해서 boolean 에 항상 빈 값을 준다.
    # 그걸 그대로 쓰면 이 루프 가드가 조용히 죽는다. _json_bool 이 있어야 통과한다.
    write_ctx 900000
    run run_budget S-A true
    [ "$status" -eq 0 ]
    [ ! -d "$MANGOLOVE_DIR/state/session-budget" ]
}

@test "session-budget: MANGOLOVE_SESSION_BUDGET=off 면 통과한다 (런타임 이중 안전장치)" {
    write_ctx 900000
    MANGOLOVE_SESSION_BUDGET=off run run_budget
    [ "$status" -eq 0 ]
}

@test "session-budget: 상태를 못 쓰면 차단하지 않는다 (루프 불가 불변식)" {
    write_ctx 900000
    # 상태 루트를 파일로 만들어 mkdir/쓰기를 실패시킨다
    mkdir -p "$MANGOLOVE_DIR/state"
    printf 'x' > "$MANGOLOVE_DIR/state/session-budget"
    run run_budget
    [ "$status" -eq 0 ]
    run ledger
    [[ "$output" == *'"type":"skip"'* ]]
    [[ "$output" == *"write-fail"* ]]
}

@test "session-budget: transcript 가 없으면 통과한다 (fail-open)" {
    run bash -c \
        "printf '{\"hook_event_name\":\"Stop\",\"session_id\":\"S\",\"cwd\":\"$PROJ\",\"transcript_path\":\"$TMP/none.jsonl\",\"stop_hook_active\":false}' | bash '$GATE'"
    [ "$status" -eq 0 ]
}

@test "session-budget: usage 레코드가 없는 transcript 는 통과한다 (fail-open)" {
    printf '{"type":"summary","summary":"x"}\n' > "$TRANSCRIPT"
    run run_budget
    [ "$status" -eq 0 ]
}

@test "session-budget: 선행 0 이 붙은 임계값(0500000)에도 게이트가 살아 있다" {
    # 회귀: "0500000" 은 숫자 검사를 통과하고도 8진수로 읽혀 산술을 깨뜨린다.
    # dod-gate 가 MANGOLOVE_DOD_MAX_ATTEMPTS 에서 겪은 사고와 같은 클래스.
    write_ctx 520000
    MANGOLOVE_SESSION_BUDGET_TOKENS=0500000 run run_budget
    [ "$status" -eq 2 ]
}

@test "session-budget: 숫자가 아닌 임계값은 기본값으로 되돌아간다" {
    write_ctx 520000
    MANGOLOVE_SESSION_BUDGET_TOKENS=abc run run_budget
    [ "$status" -eq 2 ]
    write_ctx 100
    : > "$TRANSCRIPT"; write_ctx 100000
    MANGOLOVE_SESSION_BUDGET_TOKENS=abc run run_budget S-B
    [ "$status" -eq 0 ]
}

@test "session-budget: 같은 프로젝트의 두 세션이 서로의 예산을 리셋하지 않는다" {
    # 회귀: 턴 수를 프로젝트 단위 파일에 세던 설계는 두 세션이 번갈아 발화하면
    # 서로의 카운트를 1 로 되돌려 게이트가 조용히 죽었다(dod-gate 실측 사고의 변종).
    # 컨텍스트는 각 세션 자신의 transcript 에서 읽으므로 그 문제가 구조적으로 없다.
    local t_a="$TMP/a.jsonl" t_b="$TMP/b.jsonl"
    printf '{"message":{"usage":{"input_tokens":0,"output_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":900000}}}\n' > "$t_a"
    printf '{"message":{"usage":{"input_tokens":0,"output_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":100000}}}\n' > "$t_b"

    _fire() {
        printf '{"hook_event_name":"Stop","session_id":"%s","cwd":"%s","transcript_path":"%s","stop_hook_active":false}' \
            "$1" "$PROJ" "$2" | bash "$GATE"
    }
    # A 가 알림을 받는다
    run _fire S-A "$t_a"; [ "$status" -eq 2 ]
    # B 가 사이에 끼어들어도(작은 컨텍스트) A 의 통지 이력을 건드리지 않는다
    run _fire S-B "$t_b"; [ "$status" -eq 0 ]
    # A 는 여전히 같은 버킷이라 다시 알리지 않는다 (B 가 리셋했다면 여기서 2 가 난다)
    run _fire S-A "$t_a"; [ "$status" -eq 0 ]
}

@test "session-budget: 컨텍스트는 input+cache write+cache read 의 합이다" {
    # 어느 한 버킷만 보면 임계 미만이지만 합치면 넘는다
    printf '{"message":{"usage":{"input_tokens":200000,"output_tokens":1,"cache_creation_input_tokens":150000,"cache_read_input_tokens":200000}}}\n' > "$TRANSCRIPT"
    run run_budget
    [ "$status" -eq 2 ]
    [[ "$output" == *"550K"* ]]
}

@test "session-budget: 마지막 usage 레코드를 본다 (합계가 아니다)" {
    write_ctx 400000
    write_ctx 400000
    write_ctx 100000     # 현재 컨텍스트는 100K 다. 합(900K)이 아니다.
    run run_budget
    [ "$status" -eq 0 ]
}

@test "boundary: 인라인 정규식이 dod-gate 의 _json_str 과 같은 값을 낸다" {
    # 매 턴 도는 훅이라 $() 서브셸(=포크)을 없애려고 정규식을 호출부에 인라인했다.
    # 그래서 바이트 동일성 대신 **동작 동일성**을 고정한다: 까다로운 JSON 에서 두 구현이
    # 같은 값을 내야 한다. 어긋나면 이 훅만 조용히 다른 파싱을 하게 된다.
    # shellcheck disable=SC1090
    eval "$(sed -n '/^_json_str() {/,/^}/p' "$REPO/lib/dod-gate.sh")"
    # shellcheck disable=SC2016
    local re; re="$(sed -n 's/^_RE_TRANSCRIPT=.\(.*\).$/\1/p' "$REPO/lib/session-budget.sh")"
    [ -n "$re" ]

    _inline() { [[ "$1" =~ $re ]] && printf '%s' "${BASH_REMATCH[1]}"; return 0; }

    local j
    for j in '{"a":"x\"y","transcript_path":"/p"}' \
             '{"transcript_path":"","session_id":"s"}' \
             '{"a":"transcript_path","transcript_path":"/real"}' \
             '{"transcript_path"  :   "/sp"}' \
             '{"transcript_path":"/a\"b/c"}' \
             '{"a":"b"}' \
             '{"transcript_path":"/first","transcript_path":"/second"}'; do
        [ "$(_inline "$j")" = "$(_json_str "$j" transcript_path)" ]
    done
}

@test "boundary: 세 게이트의 GATE_DIR 확정 로직이 바이트 동일하다" {
    # 훅은 stdin 의 cwd 로 이동하므로 자기 위치를 cd 전에 확정해야 한다.
    # 세 사본이 갈라지면 한 게이트만 효능 기록을 조용히 잃는다(커밋 5b707ea 와 같은 실패).
    local a b c
    a="$(sed -n '/^case "${BASH_SOURCE\[0\]}" in/,/^esac/p' "$REPO/lib/dod-gate.sh")"
    b="$(sed -n '/^case "${BASH_SOURCE\[0\]}" in/,/^esac/p' "$REPO/lib/review-gate.sh")"
    c="$(sed -n '/^case "${BASH_SOURCE\[0\]}" in/,/^esac/p' "$REPO/lib/session-budget.sh")"
    [ -n "$a" ]
    [ "$a" = "$b" ]
    [ "$a" = "$c" ]
}

@test "boundary: _record_efficacy 가 dod-gate 와 바이트 동일하다" {
    local a c
    a="$(sed -n '/^_record_efficacy() {/,/^}/p' "$REPO/lib/dod-gate.sh")"
    c="$(sed -n '/^_record_efficacy() {/,/^}/p' "$REPO/lib/session-budget.sh")"
    [ -n "$a" ]
    [ "$a" = "$c" ]
}

@test "session-budget: 레포 안에 아무 파일도 만들지 않는다" {
    # 상태를 레포 밖에 두는 것이 설계다: .mangolove/.gitignore 시딩 사본을 만들지 않고,
    # "커밋되지 않은 변경 없음" 류의 DoD 를 게이트 자신이 깨뜨리지도 않는다.
    write_ctx 900000
    run run_budget
    [ "$status" -eq 2 ]
    [ ! -e "$PROJ/.mangolove" ]
    [ -z "$(ls -A "$PROJ" 2>/dev/null)" ]
}

@test "session-budget: 읽는 값은 직전 턴까지다 (usage 는 Stop 이후에 기록된다)" {
    # 실측: 훅 시점의 transcript 에는 현재 턴의 usage 가 아직 없다.
    # 그래서 이 훅이 보는 것은 "직전 턴까지의 컨텍스트"이고, 그것이 설계상 맞다.
    # 앞선 턴이 하나도 없는 세션(-p 일회성)은 0 을 읽고 통과해야 한다.
    : > "$TRANSCRIPT"
    MANGOLOVE_SESSION_BUDGET_TOKENS=5000 run run_budget
    [ "$status" -eq 0 ]
    # 직전 턴이 생기면 그때부터 잰다
    write_ctx 900000
    MANGOLOVE_SESSION_BUDGET_TOKENS=5000 run run_budget
    [ "$status" -eq 2 ]
}

@test "session-budget: tail 이 멀티바이트 문자 중간을 잘라도 컨텍스트를 읽는다" {
    # 회귀(CRITICAL): tail -c 는 바이트 경계에서 자른다. 그래서 첫 레코드가 UTF-8 문자
    # 중간에서 시작하는 일이 흔한데, macOS awk(20200816)는 그때 towc: multibyte
    # conversion failure 로 **죽는다**. END 에 닿지 못해 아무것도 출력하지 않고,
    # 그 에러는 2>/dev/null 에 삼켜져 CTX 가 빈 값이 되어 게이트가 조용히 꺼진다.
    # 실측: 이 머신의 256KB 초과 transcript 중 8.8% 가 그렇게 무음이었고, 하필
    # 한국어 위주의 긴 세션(= 타깃 코호트)에서 터졌다. LC_ALL=C 가 그 경로를 없앤다.
    #
    # 이 스위트의 나머지는 전부 ASCII 라 이 결함을 구조적으로 못 잡는다. 그래서
    # 3바이트 문자를 깔고, 자르는 지점을 1바이트씩 옮겨 문자 중간을 확실히 지나간다.
    local pad; pad="$(printf '가%.0s' $(seq 1 300))"
    printf '{"note":"%s"}\n' "$pad" > "$TRANSCRIPT"
    write_ctx 900000

    local rec_len; rec_len=$(tail -1 "$TRANSCRIPT" | wc -c | tr -d ' ')
    local off
    for off in 1 2 3 4; do
        # off=2,3 은 3바이트 문자 중간에서 자른다. 넷 다 같은 답을 내야 한다.
        MANGOLOVE_SESSION_BUDGET_TAIL=$((rec_len + off)) run run_budget "S-mb-$off"
        [ "$status" -eq 2 ] || { echo "tail=$((rec_len + off)) 에서 게이트가 무음이 됐다"; false; }
    done
}

@test "session-budget: 기본 임계는 400K 다 (env 없이)" {
    # 기본값을 코드가 고정한다. 200K 였을 때는 너무 일찍 발화했다: 실측 135세션에서
    # 알림을 받고도 컨텍스트가 중앙값 2.75배 더 늘었다(= 갈 길이 한참 남아 무시되는 안내).
    # 400K 는 1.66배이고 1M 윈도우의 40% 지점이다. 이 값이 조용히 되돌아가면 여기서 잡힌다.
    unset MANGOLOVE_SESSION_BUDGET_TOKENS
    : > "$TRANSCRIPT"; write_ctx 350000
    run run_budget S-DEF
    [ "$status" -eq 0 ]
    : > "$TRANSCRIPT"; write_ctx 450000
    run run_budget S-DEF
    [ "$status" -eq 2 ]
    [[ "$output" == *"400K"* ]]
    [[ "$output" == *"800K"* ]]      # 다음 알림 지점을 함께 알려 반복 잔소리가 아님을 드러낸다
}

@test "session-budget: 마지막 버킷에서 오지 않을 다음 안내를 예고하지 않는다" {
    # 회귀: 800K 버킷에서 "다음 1600K" 를 찍었다. 1M 창에서는 영영 오지 않는 안내다.
    unset MANGOLOVE_SESSION_BUDGET_TOKENS
    : > "$TRANSCRIPT"; write_ctx 812000
    run run_budget S-CEIL
    [ "$status" -eq 2 ]
    [[ "$output" != *"1600K"* ]]
    [[ "$output" == *"마지막"* ]]
}
