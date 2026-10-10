#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove: 테스트 실행기(tests/run.sh) 계약
#
# 실행기가 실패를 삼키거나 건너뛴 테스트를 숨기면 스위트 전체가 초록으로 보인다.
# ─────────────────────────────────────────────

setup() {
    RUN="$BATS_TEST_DIRNAME/run.sh"
    FIX="$(mktemp -d)"
    printf '@test "passes" { true; }\n@test "passes too" { true; }\n' > "$FIX/good.bats"
    printf '@test "fails loudly" { echo "the reason"; false; }\n' > "$FIX/bad.bats"
}

teardown() {
    [ -n "${FIX:-}" ] && rm -rf "$FIX"
    return 0
}

@test "runner: 전부 통과하면 0 으로 끝나고 돌린 테스트 수를 알린다" {
    run "$RUN" "$FIX/good.bats"
    [ "$status" -eq 0 ]
    [[ "$output" == *"통과: 테스트 2개 (건너뜀 0개), 파일 1개"* ]]
}

@test "runner: 하나라도 실패하면 1 로 끝나고 그 파일의 출력을 보여준다" {
    run "$RUN" "$FIX/good.bats" "$FIX/bad.bats"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not ok 1 fails loudly"* ]]
    [[ "$output" == *"the reason"* ]]
    [[ "$output" == *"실패: 파일 1개"* ]]
}

@test "runner: 돌지 못한 파일을 통과로 세지 않는다" {
    run "$RUN" "$FIX/good.bats" "$FIX/missing.bats"
    [ "$status" -eq 1 ]
    [[ "$output" == *"실패: 파일 1개"* ]]
}

# 테스트가 하나도 없는 파일은 bats 가 0 으로 끝낸다. 그대로 통과로 치면 내용이 통째로 사라진
# 파일이 초록으로 남는다.
@test "runner: 테스트가 하나도 없는 파일을 통과로 세지 않는다" {
    printf '# no tests here\n' > "$FIX/empty.bats"
    run "$RUN" "$FIX/good.bats" "$FIX/empty.bats"
    [ "$status" -eq 1 ]
    [[ "$output" == *"실패: 파일 1개"* ]]
}

# bats tests/ 는 건너뛴 테스트를 한 줄씩 보여줬다. 요약만 찍는 실행기에서는 그 수와 이름이
# 보여야 조용히 건너뛴 테스트를 알아챌 수 있다.
@test "runner: 건너뛴 테스트의 수와 이름을 요약에 보여준다" {
    printf '@test "skipped" { skip "not here"; }\n@test "runs" { true; }\n' > "$FIX/skip.bats"
    run "$RUN" "$FIX/skip.bats"
    [ "$status" -eq 0 ]
    [[ "$output" == *"통과: 테스트 2개 (건너뜀 1개)"* ]]
    [[ "$output" == *"ok 1 skipped # skip not here"* ]]
}

# 경로를 이름으로 펴면 같아지는 두 인자(a/b.bats 와 a_b.bats)도 결과를 따로 가진다. 한쪽의
# 통과가 다른 쪽의 실패를 가리면 안 된다.
@test "runner: 이름이 겹치는 두 파일의 결과를 섞지 않는다" {
    mkdir -p "$FIX/a"
    cp "$FIX/good.bats" "$FIX/a/b.bats"
    cp "$FIX/bad.bats" "$FIX/a_b.bats"
    run "$RUN" "$FIX/a/b.bats" "$FIX/a_b.bats"
    [ "$status" -eq 1 ]
    [[ "$output" == *"실패: 파일 1개"* ]]
    [[ "$output" == *"── $FIX/a_b.bats"* ]]
    [[ "$output" != *"── $FIX/a/b.bats"* ]]
}

@test "runner: 빈 인자는 돌리지 않고 거부한다" {
    run "$RUN" "" "$FIX/good.bats"
    [ "$status" -eq 2 ]
    [[ "$output" == *"빈 인자"* ]]
}

# bats 가 테스트를 조용히 빼먹고 0 으로 끝난 적이 있다(bash 3.2 에서 한국어 테스트명이 빠졌다).
# 파일에 적힌 테스트 수보다 적게 돌았으면 통과로 치지 않는다. 덜 도는 bats 를 가짜로 세운다.
@test "runner: 정의된 테스트보다 적게 돈 파일을 통과로 세지 않는다" {
    mkdir -p "$FIX/fakebin"
    printf '#!/bin/bash\necho "1..1"\necho "ok 1 passes"\n' > "$FIX/fakebin/bats"
    chmod +x "$FIX/fakebin/bats"
    run env PATH="$FIX/fakebin:$PATH" "$RUN" "$FIX/good.bats"
    [ "$status" -eq 1 ]
    [[ "$output" == *"적힌 테스트 2개 중 1개만 돌았습니다"* ]]
}

# 통과한 파일이 낸 경고도 삼키지 않는다. bats 는 run 으로 부른 명령이 없으면(127) 테스트가
# 통과해도 경고를 낸다. 그 경고가 사라지면 아무것도 검사하지 않는 테스트가 초록으로 남는다.
@test "runner: 통과한 파일이 낸 경고를 보여준다" {
    printf '@test "calls nothing" { run no_such_command_xyz; true; }\n' > "$FIX/warn.bats"
    run "$RUN" "$FIX/warn.bats"
    [ "$status" -eq 0 ]
    [[ "$output" == *"── 경고 $FIX/warn.bats"* ]]
    [[ "$output" == *"BW01"* ]]
}

@test "runner: 실패한 실행에서도 건너뛴 테스트를 보여준다" {
    printf '@test "skipped" { skip "not here"; }\n' > "$FIX/skip.bats"
    run "$RUN" "$FIX/bad.bats" "$FIX/skip.bats"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ok 1 skipped # skip not here"* ]]
}

@test "runner: 같은 파일을 두 번 줘도 각각 센다" {
    run "$RUN" "$FIX/good.bats" "$FIX/good.bats"
    [ "$status" -eq 0 ]
    [[ "$output" == *"통과: 테스트 4개 (건너뜀 0개), 파일 2개"* ]]
}

@test "runner: 다른 폴더에서 상대 경로로 불러도 그 경로 그대로 돌린다" {
    cd "$FIX"
    run "$RUN" good.bats
    [ "$status" -eq 0 ]
    [[ "$output" == *"통과: 테스트 2개"* ]]
}

@test "runner: MANGOLOVE_TEST_JOBS 로 동시 실행 수를 바꾼다" {
    run env MANGOLOVE_TEST_JOBS=1 "$RUN" "$FIX/good.bats"
    [ "$status" -eq 0 ]
    [[ "$output" == *"(동시 1)"* ]]
}

# bats tests/ 에 익숙한 손이 폴더를 넘겨도 그 안의 파일을 낱개로 풀어 엉뚱한 실패를 쏟지 않는다.
@test "runner: 폴더를 인자로 주면 그 폴더를 bats 에 그대로 넘긴다" {
    run "$RUN" "$FIX"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not ok"*"fails loudly"* ]]
    [[ "$output" == *"실패: 파일 1개"* ]]
}
