#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove: DoD gate (Stop hook) 계약 테스트
# dod.sh 없음→allow / PASS→allow+제거 / FAIL→block(exit2) / 상한→backstop / 우회 / cwd 파싱
# + 소유권: 남의 세션이 남긴 dod.sh 로는 차단되지 않는다 (실측 사고 회귀)
# ─────────────────────────────────────────────

setup() {
    REPO="$BATS_TEST_DIRNAME/.."
    GATE="$REPO/lib/dod-gate.sh"
    PROJ="$(mktemp -d)"
    mkdir -p "$PROJ/.mangolove"
    JSON="{\"hook_event_name\":\"Stop\",\"cwd\":\"$PROJ\"}"
    export GATE JSON
}

teardown() {
    [ -n "${PROJ:-}" ] && rm -rf "$PROJ"
}

run_gate() { printf '%s' "$JSON" | "$GATE"; }

# session_id 를 실은 Stop payload: 소유권 판정의 입력이다.
run_gate_as() {
    printf '{"hook_event_name":"Stop","session_id":"%s","cwd":"%s"}' "$1" "$PROJ" | "$GATE"
}

# 실패하는 DoD. 실행되면 마커를 남겨 "돌았는지"를 증거로 확인할 수 있게 한다.
# 인자로 준 메시지가 내용을 바꾸므로, 서로 다른 DoD 가 필요할 때도 이 헬퍼를 쓴다.
write_failing_dod() {
    printf '#!/usr/bin/env bash\ntouch "%s/ran"\necho "%s"\nexit 1\n' \
        "$PROJ" "${1:-빌드 실패: X}" > "$PROJ/.mangolove/dod.sh"
}

write_passing_dod() {
    printf '#!/usr/bin/env bash\ntouch "%s/ran"\nexit 0\n' "$PROJ" > "$PROJ/.mangolove/dod.sh"
}

# -s: 구분자가 없는 줄(옛 포맷)에서 2번째 필드를 물으면 전체 줄이 아니라 빈 값이어야 한다.
state_field() { cut -s -f"$1" "$PROJ/.mangolove/.dod-gate-attempts"; }

@test "dod-gate: no dod.sh → allow stop (exit 0)" {
    run run_gate
    [ "$status" -eq 0 ]
}

@test "dod-gate: passing dod.sh → allow (exit 0) and dod.sh consumed" {
    write_passing_dod
    run run_gate
    [ "$status" -eq 0 ]
    [ ! -f "$PROJ/.mangolove/dod.sh" ]
}

@test "dod-gate: failing dod.sh → block (exit 2), attempt recorded, failure shown" {
    write_failing_dod
    run run_gate
    [ "$status" -eq 2 ]
    [ "$(state_field 1)" = "1" ]
    [[ "$output" == *"빌드 실패: X"* ]]
    [[ "$output" == *"1/3"* ]]
    [ -f "$PROJ/.mangolove/dod.sh" ]   # 실패 시 dod.sh 유지(재검증)
}

@test "dod-gate: backstop: after MAX attempts, release gate (exit 0) and mark released" {
    write_failing_dod
    echo 3 > "$PROJ/.mangolove/.dod-gate-attempts"   # 옛 포맷: 해시가 없으므로 카운터를 이어받는다
    run run_gate
    [ "$status" -eq 0 ]
    [[ "$output" == *"게이트 해제"* ]]
    # 해제 후에도 dod.sh 는 근거로 남고, 상태는 released 로 표시된다.
    # (옛 동작처럼 카운터만 지우면 다음 턴에 0 으로 되돌아가 또 상한만큼 차단한다.)
    [ -f "$PROJ/.mangolove/dod.sh" ]
    [ "$(state_field 1)" = "released" ]
}

@test "dod-gate: MANGOLOVE_SKIP_DOD=1 bypasses a failing gate (audited)" {
    printf '#!/usr/bin/env bash\nexit 1\n' > "$PROJ/.mangolove/dod.sh"
    run bash -c 'printf "%s" "$JSON" | MANGOLOVE_SKIP_DOD=1 "$GATE"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"MANGOLOVE_SKIP_DOD=1"* ]]
}

@test "dod-gate: locates dod.sh via stdin cwd, not the process pwd" {
    printf '#!/usr/bin/env bash\nexit 0\n' > "$PROJ/.mangolove/dod.sh"
    # 다른 디렉토리에서 실행하되 stdin cwd 는 PROJ → gate 가 PROJ 로 이동해 dod.sh 를 찾아 소비해야 한다.
    run bash -c 'cd / && printf "%s" "$JSON" | "$GATE"'
    [ "$status" -eq 0 ]
    [ ! -f "$PROJ/.mangolove/dod.sh" ]
}

# ── 소유권 ────────────────────────────────────────────────────
# 실측 사고 회귀: 조사만 한 세션이 다른 세션의 DoD 를 물려받아 차단됐고, 그 DoD 의 미충족
# 사유(남의 미커밋 변경)는 그 세션이 해결할 수 있는 것도 아니었다.

@test "dod-gate: 세션 A 가 남긴 dod.sh 로 세션 B 가 차단되지 않는다" {
    write_failing_dod "FAIL: 커밋되지 않은 변경 있음"

    run run_gate_as SESSION-A
    [ "$status" -eq 2 ]
    [ "$(state_field 3)" = "SESSION-A" ]

    run run_gate_as SESSION-B
    [ "$status" -eq 0 ]
    [[ "$output" == *"다른 세션(SESSION-A)"* ]]
}

@test "dod-gate: 비소유 세션은 남의 dod.sh 를 실행하지도 지우지도 않는다" {
    write_failing_dod
    run_gate_as SESSION-A || true
    rm -f "$PROJ/ran"
    local before; before="$(cat "$PROJ/.mangolove/.dod-gate-attempts")"

    run run_gate_as SESSION-B
    [ "$status" -eq 0 ]
    [ ! -f "$PROJ/ran" ]                       # 실행하지 않았다
    [ -f "$PROJ/.mangolove/dod.sh" ]           # 지우지 않았다 (소유자가 통과시킬 여지)
    [ "$(cat "$PROJ/.mangolove/.dod-gate-attempts")" = "$before" ]   # 카운터도 건드리지 않았다
}

@test "dod-gate: 소유자 세션은 계속 차단된다 (건너뛰기가 소유자에게 새지 않는다)" {
    write_failing_dod
    run_gate_as SESSION-A || true
    run_gate_as SESSION-B || true

    run run_gate_as SESSION-A
    [ "$status" -eq 2 ]
    [ "$(state_field 1)" = "2" ]
}

@test "dod-gate: dod.sh 내용이 바뀌면 새 소유자로 재기록된다" {
    write_failing_dod
    run_gate_as SESSION-A || true

    # 세션 B 가 자기 DoD 를 쓰면 그것은 B 의 DoD 다: 평가받아야 한다.
    write_failing_dod "B 의 실패"
    run run_gate_as SESSION-B
    [ "$status" -eq 2 ]
    [[ "$output" == *"B 의 실패"* ]]
    [ "$(state_field 3)" = "SESSION-B" ]
}

@test "dod-gate: 같은 세션이 DoD 를 갱신하는 정상 흐름은 막히지 않는다" {
    write_failing_dod
    run_gate_as SESSION-A || true

    write_passing_dod
    run run_gate_as SESSION-A
    [ "$status" -eq 0 ]
    [ ! -f "$PROJ/.mangolove/dod.sh" ]
    [ ! -f "$PROJ/.mangolove/.dod-gate-attempts" ]
}

@test "dod-gate: session_id 가 없는 payload 는 예전처럼 평가한다 (소유권 판정 불가)" {
    write_failing_dod
    run run_gate
    [ "$status" -eq 2 ]
    [ -f "$PROJ/ran" ]
    [ "$(state_field 3)" = "" ]
}

@test "dod-gate: 옛 포맷(정수만) 상태 파일과 호환된다" {
    write_failing_dod
    echo 1 > "$PROJ/.mangolove/.dod-gate-attempts"
    run run_gate_as SESSION-A
    [ "$status" -eq 2 ]
    [[ "$output" == *"2/3"* ]]      # 카운터를 이어받는다
    [ "$(state_field 3)" = "SESSION-A" ]
}

# ── 해제와 재무장 ─────────────────────────────────────────────
# released 상태는 손으로 만들지 않고 게이트를 실제로 돌려서 만든다: 상태 파일의 해시를
# 테스트가 직접 계산하면 게이트의 해시 구현(sha256sum/shasum/cksum)에 결합된다.
# MAX 를 낮추는 것은 호출자의 결정이라 헬퍼가 몰래 export 하지 않는다(그 값이 이후 단언에 샌다).
release_gate_as() {
    run_gate_as "$1" >/dev/null 2>&1 || true   # 1회 실패 → 시도 1/1
    run_gate_as "$1" >/dev/null 2>&1 || true   # 다음 턴 → 해제
}

@test "dod-gate: 해제된 DoD 는 같은 내용인 한 다시 차단하지 않고 실행되지도 않는다" {
    export MANGOLOVE_DOD_MAX_ATTEMPTS=1
    write_failing_dod
    release_gate_as SESSION-A
    [ "$(state_field 1)" = "released" ]
    rm -f "$PROJ/ran"

    run run_gate_as SESSION-A
    [ "$status" -eq 0 ]
    [ ! -f "$PROJ/ran" ]                       # 해제 뒤에는 재실행하지 않는다(빌드 재수행 방지)
    [ -f "$PROJ/.mangolove/dod.sh" ]           # 근거로 남는다
    [ "$(state_field 1)" = "released" ]
}

@test "dod-gate: 해제 후 새 DoD 를 쓰면 게이트가 재무장한다" {
    export MANGOLOVE_DOD_MAX_ATTEMPTS=1
    write_failing_dod
    release_gate_as SESSION-A

    write_failing_dod "새 DoD 실패"
    run run_gate_as SESSION-A
    [ "$status" -eq 2 ]
    [[ "$output" == *"1/1"* ]]
    [ "$(state_field 1)" = "1" ]
}

@test "dod-gate: 새 DoD 는 자기 몫의 시도 예산을 받는다 (앞선 DoD 의 실패를 물려받지 않는다)" {
    # 회귀: 카운터가 DoD 를 가리지 않던 때는, 2회 실패 뒤 접근을 바꿔 쓴 DoD 가 단 1회만
    # 평가받고 "3회 시도에도 미통과"로 해제됐다. 시도한 적 없는 DoD 에 대한 거짓 보고였다.
    write_failing_dod "DoD-1"
    run_gate_as SESSION-A || true
    run_gate_as SESSION-A || true
    [ "$(state_field 1)" = "2" ]

    write_failing_dod "DoD-2"
    run run_gate_as SESSION-A
    [ "$status" -eq 2 ]
    [[ "$output" == *"시도 1/3"* ]]
    [[ "$output" == *"누적 3/9"* ]]
}

@test "dod-gate: DoD 를 매 턴 새로 써도 누적 상한에서 반드시 끝난다" {
    # 시도 예산이 DoD 별이므로, 매 턴 내용을 바꾸면 개별 카운터는 영원히 1 이다.
    # 누적 상한이 없으면 backstop 이 영영 발화하지 않는다.
    export MANGOLOVE_DOD_MAX_ATTEMPTS=1     # 누적 상한 = 3
    local i out
    for i in 1 2 3; do
        write_failing_dod "DoD-$i"
        run run_gate_as SESSION-A
        [ "$status" -eq 2 ]
    done

    write_failing_dod "DoD-4"
    run run_gate_as SESSION-A
    [ "$status" -eq 0 ]
    [[ "$output" == *"게이트 해제"* ]]
    [[ "$output" == *"누적 3회"* ]]
}

# ── 경계: 두 게이트가 심는 무시 목록이 갈라지지 않는다 ────────────
@test "boundary: dod-gate 와 review-gate 가 심는 .mangolove/.gitignore 가 일치한다" {
    # 훅은 서로를 source 하지 않으므로 같은 함수가 두 벌 있다. 목록이 갈라지면 먼저 심은
    # 쪽이 이기고, 진 쪽의 일시 파일이 untracked 로 떠서 "커밋되지 않은 변경 없음" 류의
    # DoD 를 게이트 자신이 깨뜨린다(실제로 .review-skip 이 그랬다).
    local B; B="$(mktemp -d)"; mkdir -p "$B/.mangolove"

    write_failing_dod
    run_gate_as SESSION-A >/dev/null 2>&1 || true
    printf '{"hook_event_name":"PostToolUse","session_id":"S","cwd":"%s","tool_input":{"skill":"simplify"}}' "$B" \
        | bash "$REPO/lib/review-gate.sh" record >/dev/null 2>&1 || true

    run diff "$PROJ/.mangolove/.gitignore" "$B/.mangolove/.gitignore"
    rm -rf "$B"
    [ "$status" -eq 0 ]
}

@test "boundary: 이미 심어진 옛 .gitignore 에도 빠진 패턴이 채워진다" {
    # "없을 때만 생성"이던 옛 동작 탓에 기존 레포에는 .review-skip 이 빠져 있다.
    printf '.gitignore\ndod.sh\n.dod-gate-attempts\n' > "$PROJ/.mangolove/.gitignore"
    write_failing_dod
    run_gate_as SESSION-A >/dev/null 2>&1 || true

    grep -qx '.review-skip' "$PROJ/.mangolove/.gitignore"
    grep -qx '.review-ledger' "$PROJ/.mangolove/.gitignore"
    [ "$(grep -cx 'dod.sh' "$PROJ/.mangolove/.gitignore")" = "1" ]   # 중복 append 하지 않는다
}

@test "dod-gate: 누적 상한에 닿아도 새 DoD 를 쓰면 게이트가 되살아난다 (영구 사망 회귀)" {
    # 회귀: 누적치는 통과 경로에서만 지워지는데 해제 경로는 dod.sh 를 실행하지 않는다.
    # 되돌리는 규칙이 없으면 상한에 한 번 닿은 프로젝트에서 게이트가 영구히 죽어,
    # 이후 어떤 세션이 어떤 DoD 를 써도 검증 없이 통과한다.
    export MANGOLOVE_DOD_MAX_ATTEMPTS=1     # 누적 상한 = 3
    local i
    for i in 1 2 3; do
        write_failing_dod "DoD-$i"
        run_gate_as SESSION-A >/dev/null 2>&1 || true
    done
    write_failing_dod "DoD-4"
    run run_gate_as SESSION-A               # 누적 상한 → 해제
    [ "$status" -eq 0 ]
    rm -f "$PROJ/ran"

    write_failing_dod "DoD-5"               # 해제 뒤의 새 DoD 는 새 에피소드다
    run run_gate_as SESSION-B
    [ "$status" -eq 2 ]
    [ -f "$PROJ/ran" ]                      # 실제로 실행했다
    [[ "$output" == *"1/1"* ]]
}

@test "dod-gate: 소유권은 첫 실패가 아니라 첫 평가에 찍힌다" {
    # 실제 DoD 는 빌드/테스트라 몇 분씩 걸린다. 실행이 끝난 뒤에 찍으면 그 사이 발화한
    # 다른 세션이 같은 빌드를 한 번 더 돌리고 소유권까지 가져가, 정작 DoD 를 쓴 세션이
    # 자기 DoD 를 남의 것으로 보고 영영 건너뛴다.
    printf '#!/usr/bin/env bash\ncp "%s/.mangolove/.dod-gate-attempts" "%s/seen" 2>/dev/null\nexit 1\n' \
        "$PROJ" "$PROJ" > "$PROJ/.mangolove/dod.sh"
    run run_gate_as SESSION-A
    [ "$status" -eq 2 ]
    [ -f "$PROJ/seen" ]                                  # 실행 중에 상태가 이미 있었다
    [ "$(cut -s -f3 "$PROJ/seen")" = "SESSION-A" ]       # 그 상태의 소유자가 실행 세션이다
}

@test "dod-gate: 선행 0 이 붙은 MAX 값(08, 00)에도 게이트가 살아 있다" {
    # "08" 은 숫자 검사를 통과하고도 8진수로 읽혀 산술을 깨뜨렸다. 그러면 set -u 가 훅을
    # 죽여 게이트가 조용히 꺼진다. "00" 은 0 가드를 통과해 첫 턴부터 해제시켰다.
    write_failing_dod
    MANGOLOVE_DOD_MAX_ATTEMPTS=08 run run_gate_as SESSION-A
    [ "$status" -eq 2 ]
    [[ "$output" == *"1/8"* ]]

    rm -f "$PROJ/.mangolove/.dod-gate-attempts"
    MANGOLOVE_DOD_MAX_ATTEMPTS=00 run run_gate_as SESSION-A
    [ "$status" -eq 2 ]
    [[ "$output" == *"1/3"* ]]      # 기본값으로 되돌린다
}

@test "boundary: 개행으로 끝나지 않는 .gitignore 에 덧붙여도 마지막 줄이 깨지지 않는다" {
    printf '.gitignore\ndod.sh' > "$PROJ/.mangolove/.gitignore"   # 마지막 개행 없음
    write_failing_dod
    run_gate_as SESSION-A >/dev/null 2>&1 || true

    grep -qx 'dod.sh' "$PROJ/.mangolove/.gitignore"
    grep -qx '.dod-gate-attempts' "$PROJ/.mangolove/.gitignore"
    ! grep -q 'dod.sh.dod-gate-attempts' "$PROJ/.mangolove/.gitignore"
}
