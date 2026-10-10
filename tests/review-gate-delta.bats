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
        # 커밋 셋에 나눠 싣는다
        case "$i" in 4|8|11) _commit_all "small up to $i" ;; esac
    done
    _gate "git push"
    [ "$status" -eq 2 ]
    [ "$(_block_kinds)" = '"kind":"stale"' ]
}

@test "리뷰가 본 적 없는 파일은 범위 전체 변경으로 잰다" {
    _add_external_call "$REPO_DIR/other.js" v9
    _work
    _run_all_reviews "client.js"
    _review_fix
    _gate "git push"
    [ "$status" -eq 2 ]
    local sha; sha="$(_delta_commit "$output")"
    [ -n "$sha" ]
    run git -C "$REPO_DIR" show --format= --numstat "$sha"
    # client.js 는 고친 한 줄만, 본 적 없는 두 파일은 범위의 기준 쪽 판본과의 차이 전체다
    [ "$(printf '%s\n' "$output" | sort)" = "$(printf '1\t0\tclient.js\n1\t0\tother.js\n1\t1\tseed.txt\n')" ]
}

@test "리뷰 뒤에 새로 만든 파일만 있어도 그 변경만 담은 커밋을 알려 준다" {
    _reviewed_work
    _eleven_files added
    _commit_all "follow-up work"
    _gate "git push"
    [ "$status" -eq 2 ]
    [ "$(_block_kinds)" = '"kind":"stale"' ]
    local sha; sha="$(_delta_commit "$output")"
    [ -n "$sha" ]
    run git -C "$REPO_DIR" show --format= --name-only "$sha"
    [ "$(printf '%s\n' "$output" | grep -c '^added')" -eq 11 ]
    [ "$(printf '%s\n' "$output" | grep -c .)" -eq 11 ]
}

@test "리뷰 뒤에 이름만 바꾼 원격의 파일은 새 코드로 세지 않는다" {
    # 경로를 좁혀 재면 이름 바꾸기의 짝을 잃어 파일 전체가 새로 쓴 코드로 보인다.
    _add_external_call "$REPO_DIR/legacy.js" v0
    _commit_all "already on remote"
    git -C "$REPO_DIR" update-ref refs/remotes/origin/main HEAD
    _reviewed_work
    git -C "$REPO_DIR" mv legacy.js moved.js
    _commit_all "rename only"
    _gate "git push"
    [ "$status" -eq 0 ]
}

@test "리뷰 뒤에 지운 파일과 새로 만든 작은 파일이 섞여도 그 차이만 잰다" {
    _reviewed_work
    git -C "$REPO_DIR" rm -q seed.txt
    echo "export const NOTE = 1" > "$REPO_DIR/note.js"
    _review_fix
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
    _review_fix
    local sha base
    sha="$(git -C "$REPO_DIR" rev-parse HEAD)"; base="$(git -C "$REPO_DIR" rev-parse origin/main)"
    run bash -c "cd '$REPO_DIR' && printf 'refs/heads/main %s refs/heads/main %s\n' '$sha' '$base' | GIT_DIR='$REPO_DIR/.git' bash '$GATE' prepush origin /tmp/fake.git"
    [ "$status" -eq 0 ]
}

@test "리뷰가 전부 본 내용을 그대로 올릴 때는 차이 판정을 타지 않는다" {
    _reviewed_work
    _gate "git push"
    [ "$status" -eq 0 ]
    [ "$(_delta_skips)" = "0" ]
}
