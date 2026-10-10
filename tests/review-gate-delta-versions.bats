#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove: Review gate: 리뷰가 본 판본을 남기고 고르는 일
# 리뷰 뒤 변경만 따로 재는 판정(tests/review-gate-delta.bats)은 리뷰가 본 판본을 꺼낼 수 있어야 성립한다.
# 여기서는 판본을 어떻게 남기는지(스냅샷), 어느 판본과 비교하는지, 통과를 어떻게 기록하는지를 고정한다.
# ─────────────────────────────────────────────

load test_helper
load review_gate_helper

@test "커밋 전 내용을 리뷰했어도 그 판본과의 차이만 잰다" {
    _eleven_files
    _add_external_call "$REPO_DIR/client.js" v1
    _run_all_reviews
    echo "// 타임아웃은 호출부가 정한다" >> "$REPO_DIR/client.js"
    _commit_all "work with review fix"
    _gate "git push"
    [ "$status" -eq 0 ]
}

@test "리뷰가 본 판본이 객체로 남아 있지 않으면 예전처럼 막는다" {
    _reviewed_work
    local cov="$REPO_DIR/.git/mangolove/.review-covered"
    awk -F'\t' -v OFS='\t' '$3 == "client.js" { $2 = "1111111111111111111111111111111111111111" } { print }' "$cov" > "$cov.new"
    mv "$cov.new" "$cov"
    _review_fix
    _gate "git push"
    [ "$status" -eq 2 ]
}

@test "사라진 판본이 섞여 있어도 남아 있는 판본과 비교한다" {
    _reviewed_work
    local s
    for s in simplify code-review security-review; do
        printf '%s\t%s\t%s\n' "$s" 1111111111111111111111111111111111111111 client.js
    done >> "$REPO_DIR/.git/mangolove/.review-covered"
    _review_fix
    _gate "git push"
    [ "$status" -eq 0 ]
}

@test "본 판본은 스킬마다 따로다: 한 스킬이 본 것으로 다른 스킬을 통과시키지 않는다" {
    _work
    printf '%s' "$(_json_skill simplify)"        | bash "$GATE" record
    printf '%s' "$(_json_skill security-review)" | bash "$GATE" record
    _review_fix
    _gate "git push"
    [ "$status" -eq 2 ]
    [[ "$output" == *"/code-review:"* ]]
    [[ "$output" != *"/simplify:"* ]]
    [[ "$output" != *"/security-review:"* ]]
}

@test "본 판본이 여럿이면 지금 내용과 가장 가까운 것과 비교한다" {
    _reviewed_work
    # 두 번째 리뷰는 외부 호출이 하나 더 들어간 판본을 봤다
    _add_external_call "$REPO_DIR/client.js" v2
    _commit_all "second call"
    _run_all_reviews
    _review_fix
    _gate "git push"
    [ "$status" -eq 0 ]
}

@test "지우기만 했으면 더해진 줄이 없는 판본과 비교한다" {
    # 줄 수 합계로 고르면 첫 판본(차이 1줄)이 뽑혀, 두 번째 리뷰가 이미 본 호출이 미검토분으로 나온다.
    _reviewed_work
    _add_external_call "$REPO_DIR/client.js" v2
    local i
    for i in $(seq 1 19); do echo "// 임시 메모 $i" >> "$REPO_DIR/client.js"; done
    _commit_all "second call with notes"
    _run_all_reviews
    grep -v '임시 메모' "$REPO_DIR/client.js" > "$REPO_DIR/client.js.new"
    mv "$REPO_DIR/client.js.new" "$REPO_DIR/client.js"
    _commit_all "drop notes"
    _gate "git push"
    [ "$status" -eq 0 ]
}

@test "차이만으로 통과시킨 것은 효능 원장에 남긴다 (status 는 남기지 않는다)" {
    _reviewed_work
    _review_fix
    run bash -c "cd '$REPO_DIR' && bash '$GATE' status"
    [ "$status" -eq 0 ]
    [[ "$output" == *"판정: PASS"* ]]
    [[ "$output" == *"리뷰 뒤"* ]]
    [ "$(_delta_skips)" = "0" ]
    _gate "git push"
    [ "$status" -eq 0 ]
    [ "$(_delta_skips)" = "1" ]
}

@test "스냅샷은 큰 파일을 객체로 남기지 않는다 (해시는 기록한다)" {
    # 무시되지 않은 빌드 로그 같은 미추적 파일이 리뷰 스킬 호출마다 .git 에 복사되면 안 된다.
    _work
    head -c 1500000 /dev/zero > "$REPO_DIR/build.log"
    _run_all_reviews
    local h; h="$(git -C "$REPO_DIR" hash-object "$REPO_DIR/build.log")"
    run git -C "$REPO_DIR" cat-file -e "$h"
    [ "$status" -ne 0 ]
    grep -q "$h	build.log" "$REPO_DIR/.git/mangolove/.review-covered"
    # 작은 파일의 판본은 남는다
    git -C "$REPO_DIR" cat-file -e "$(git -C "$REPO_DIR" hash-object "$REPO_DIR/client.js")"
}

@test "스냅샷은 심볼릭 링크 너머의 내용을 객체로 쓰지 않는다" {
    # git hash-object 는 링크를 따라간다. 객체로 남기면 레포 밖 파일의 내용이 .git 에 복사된다.
    echo "outside secret" > "$TEST_DIR/outside.txt"
    ln -s "$TEST_DIR/outside.txt" "$REPO_DIR/link.txt"
    _reviewed_work
    local h; h="$(git -C "$REPO_DIR" hash-object "$TEST_DIR/outside.txt")"
    run git -C "$REPO_DIR" cat-file -e "$h"
    [ "$status" -ne 0 ]
}
