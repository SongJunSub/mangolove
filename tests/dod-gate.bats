#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove — DoD gate (Stop hook) 계약 테스트
# dod.sh 없음→allow / PASS→allow+제거 / FAIL→block(exit2) / MAX→backstop / 우회 / cwd 파싱
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

@test "dod-gate: no dod.sh → allow stop (exit 0)" {
    run run_gate
    [ "$status" -eq 0 ]
}

@test "dod-gate: passing dod.sh → allow (exit 0) and dod.sh consumed" {
    printf '#!/usr/bin/env bash\nexit 0\n' > "$PROJ/.mangolove/dod.sh"
    run run_gate
    [ "$status" -eq 0 ]
    [ ! -f "$PROJ/.mangolove/dod.sh" ]
}

@test "dod-gate: failing dod.sh → block (exit 2), attempt recorded, failure shown" {
    printf '#!/usr/bin/env bash\necho "빌드 실패: X"; exit 1\n' > "$PROJ/.mangolove/dod.sh"
    run run_gate
    [ "$status" -eq 2 ]
    [ "$(cat "$PROJ/.mangolove/.dod-gate-attempts")" = "1" ]
    [[ "$output" == *"빌드 실패: X"* ]]
    [[ "$output" == *"1/3"* ]]
    [ -f "$PROJ/.mangolove/dod.sh" ]   # 실패 시 dod.sh 유지(재검증)
}

@test "dod-gate: backstop — after MAX attempts, release gate (exit 0)" {
    printf '#!/usr/bin/env bash\nexit 1\n' > "$PROJ/.mangolove/dod.sh"
    echo 3 > "$PROJ/.mangolove/.dod-gate-attempts"
    run run_gate
    [ "$status" -eq 0 ]
    [[ "$output" == *"게이트 해제"* ]]
    [ ! -f "$PROJ/.mangolove/.dod-gate-attempts" ]
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
