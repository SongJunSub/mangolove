#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove: Review gate: 리뷰 뒤 변경만 따로 재는 판정
# 게이트의 목적과 회귀 대상 행동은 tests/review-gate.bats 머리말에 있다.
#
# 미검토 파일을 "범위 전체 변경"으로만 재면, 리뷰가 이미 본 파일을 한 줄 고쳐도 그 파일이 원래
# 실었던 변경 전체가 다시 미검토분이 된다. 큰 작업에서는 리뷰 지적을 반영할 때마다 원래 트랙으로
# 다시 막혀 재리뷰가 끝나지 않았다. 리뷰가 본 판본이 남아 있는 파일은 그 판본과의 차이만 잰다.
# ─────────────────────────────────────────────

load test_helper
load review_gate_helper

# 외부 호출이 든 작업(Medium: client.js 와 seed.txt)을 커밋한다. 리뷰 뒤 client.js 를 한 줄만 고쳐도
# 그 파일의 범위 전체 변경에는 외부 호출이 있어, 차이를 따로 재지 않으면 다시 막힌다.
_work() {
    echo "seed v2" > "$REPO_DIR/seed.txt"
    _commit_external_api
}
_reviewed_work() { _work; _run_all_reviews; }

# 같은 작업에 파일 11개를 더한 Large 작업.
_reviewed_large_work() {
    local i
    for i in $(seq 1 11); do echo "export const F$i = $i" > "$REPO_DIR/mod$i.js"; done
    _reviewed_work
}

_commit_all() {
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm "$1"
}

_delta_skips() {
    local f="$MANGOLOVE_DIR/efficacy/proj.jsonl"
    [ -f "$f" ] || { echo 0; return 0; }
    grep -c '"type":"skip","phase":"review","kind":"delta"' "$f" || true
}

# 차단 안내가 알려 준 "리뷰 뒤 변경" 커밋.
_delta_commit() { printf '%s\n' "$1" | sed -n 's/.*git show \([0-9a-f]\{40\}\).*/\1/p' | head -1; }

@test "리뷰가 본 파일을 한 줄 고친 것은 그 한 줄만 미검토분이다" {
    _reviewed_large_work
    echo "export const TIMEOUT_MS = 3000" >> "$REPO_DIR/client.js"
    _commit_all "review fix"
    _gate "git push"
    [ "$status" -eq 0 ]
}

@test "리뷰 뒤 변경이 그것만으로 리뷰 대상이면 막고, 그 변경만 담은 커밋을 알려 준다" {
    _reviewed_work
    _add_external_call "$REPO_DIR/client.js" v2
    _commit_all "new call after review"
    _gate "git push"
    [ "$status" -eq 2 ]
    [ "$(_block_kinds)" = '"kind":"stale"' ]
    local sha; sha="$(_delta_commit "$output")"
    [ -n "$sha" ]
    run git -C "$REPO_DIR" show --format= --numstat "$sha"
    [ "$output" = "1	0	client.js" ]
    # 그 커밋을 짚어 다시 리뷰하면 통과한다
    _run_all_reviews "$sha"
    _gate "git push"
    [ "$status" -eq 0 ]
}

@test "작은 수정을 여러 커밋으로 쌓아도 리뷰가 본 판본 기준으로 합쳐 잰다" {
    _reviewed_large_work
    local i
    for i in $(seq 1 11); do
        echo "export const G$i = $i" >> "$REPO_DIR/mod$i.js"
        _commit_all "small $i"
    done
    _gate "git push"
    [ "$status" -eq 2 ]
    [ "$(_block_kinds)" = '"kind":"stale"' ]
}

@test "리뷰가 본 적 없는 파일은 범위 전체 변경으로 잰다" {
    _add_external_call "$REPO_DIR/other.js" v9
    _work
    _run_all_reviews "client.js"
    echo "// 타임아웃은 호출부가 정한다" >> "$REPO_DIR/client.js"
    _commit_all "review fix"
    _gate "git push"
    [ "$status" -eq 2 ]
    local sha; sha="$(_delta_commit "$output")"
    [ -n "$sha" ]
    run git -C "$REPO_DIR" show --format= --numstat "$sha"
    # client.js 는 고친 한 줄만, 본 적 없는 두 파일은 범위의 기준 쪽 판본과의 차이 전체다
    [ "$(printf '%s\n' "$output" | sort)" = "$(printf '1\t0\tclient.js\n1\t0\tother.js\n1\t1\tseed.txt\n')" ]
}

@test "커밋 전 내용을 리뷰했어도 그 판본과의 차이만 잰다" {
    local i
    for i in $(seq 1 11); do echo "export const F$i = $i" > "$REPO_DIR/mod$i.js"; done
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
    echo "// 타임아웃은 호출부가 정한다" >> "$REPO_DIR/client.js"
    _commit_all "review fix"
    _gate "git push"
    [ "$status" -eq 2 ]
}

@test "사라진 판본이 섞여 있어도 남아 있는 판본과 비교한다" {
    _reviewed_work
    local s
    for s in simplify code-review security-review; do
        printf '%s\t%s\t%s\n' "$s" 1111111111111111111111111111111111111111 client.js
    done >> "$REPO_DIR/.git/mangolove/.review-covered"
    echo "// 타임아웃은 호출부가 정한다" >> "$REPO_DIR/client.js"
    _commit_all "review fix"
    _gate "git push"
    [ "$status" -eq 0 ]
}

@test "본 판본은 스킬마다 따로다: 한 스킬이 본 것으로 다른 스킬을 통과시키지 않는다" {
    _work
    printf '%s' "$(_json_skill simplify)"        | bash "$GATE" record
    printf '%s' "$(_json_skill security-review)" | bash "$GATE" record
    echo "// 타임아웃은 호출부가 정한다" >> "$REPO_DIR/client.js"
    _commit_all "review fix"
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
    echo "// 타임아웃은 호출부가 정한다" >> "$REPO_DIR/client.js"
    _commit_all "review fix"
    _gate "git push"
    [ "$status" -eq 0 ]
}

@test "리뷰 뒤에 지운 파일과 새로 만든 작은 파일이 섞여도 그 차이만 잰다" {
    _reviewed_work
    git -C "$REPO_DIR" rm -q seed.txt
    echo "export const NOTE = 1" > "$REPO_DIR/note.js"
    echo "// 타임아웃은 호출부가 정한다" >> "$REPO_DIR/client.js"
    _commit_all "review fix"
    _gate "git push"
    [ "$status" -eq 0 ]
}

@test "하위 폴더의 한글 이름 파일도 본 판본과 비교한다" {
    mkdir -p "$REPO_DIR/문서"
    _add_external_call "$REPO_DIR/문서/안내 화면.js" v1
    _reviewed_work
    echo "// 문구만 고친다" >> "$REPO_DIR/문서/안내 화면.js"
    _commit_all "review fix"
    _gate "git push"
    [ "$status" -eq 0 ]
}

@test "터미널 push(pre-push 훅)도 같은 판정을 쓴다" {
    _reviewed_work
    echo "// 타임아웃은 호출부가 정한다" >> "$REPO_DIR/client.js"
    _commit_all "review fix"
    local sha base
    sha="$(git -C "$REPO_DIR" rev-parse HEAD)"; base="$(git -C "$REPO_DIR" rev-parse origin/main)"
    run bash -c "cd '$REPO_DIR' && printf 'refs/heads/main %s refs/heads/main %s\n' '$sha' '$base' | GIT_DIR='$REPO_DIR/.git' bash '$GATE' prepush origin /tmp/fake.git"
    [ "$status" -eq 0 ]
}

@test "차이만으로 통과시킨 것은 효능 원장에 남긴다 (status 는 남기지 않는다)" {
    _reviewed_work
    echo "// 타임아웃은 호출부가 정한다" >> "$REPO_DIR/client.js"
    _commit_all "review fix"
    run bash -c "cd '$REPO_DIR' && bash '$GATE' status"
    [ "$status" -eq 0 ]
    [[ "$output" == *"판정: PASS"* ]]
    [[ "$output" == *"리뷰 뒤"* ]]
    [ "$(_delta_skips)" = "0" ]
    _gate "git push"
    [ "$status" -eq 0 ]
    [ "$(_delta_skips)" = "1" ]
}

@test "리뷰가 전부 본 내용을 그대로 올릴 때는 차이 판정을 타지 않는다" {
    _reviewed_work
    _gate "git push"
    [ "$status" -eq 0 ]
    [ "$(_delta_skips)" = "0" ]
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
