#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove: Review gate: simplify 는 한 작업에서 한 번 본 파일을 다시 요구받지 않는다
# 게이트의 목적과 회귀 대상 행동은 tests/review-gate.bats 머리말에 있다.
#
# simplify 는 코드를 고치는 스킬인데 커버리지는 호출 시점의 내용이다. 그래서 simplify 가 지적을
# 반영해 고친 파일이 simplify 자신에게 "보지 않은 변경"이 되고, 그 변경이 Medium 이상이면 push 가
# simplify 부족으로 막혔다. 실측: CRS 2026-10-13 차단 36개 파일 가운데 25개가 simplify 자신이 고친
# 파일이었고, 2026-10-10 과 이 레포의 2026-10-13 작업도 같은 사유로 우회했다.
#
# 그래서 simplify 는 "이 작업에서 그 파일을 한 번이라도 봤는가"로 본다. 작업은 push 범위의 기준
# 커밋으로 가른다: 커버리지 기록은 push 뒤에도 남으므로, 기준을 가리지 않으면 지난 작업의 기록이
# 새 작업을 면제한다. 본 파일의 이후 변경은 code-review 자신의 판정이 그대로 본다.
# ─────────────────────────────────────────────

load test_helper
load review_gate_helper

_record() { printf '%s' "$(_json_skill "$1" "${2:-}")" | bash "$GATE" record; }

# 위험 신호 없이 파일 수만으로 Medium 인 작업(필수 리뷰: simplify, code-review)을 커밋한다.
_medium_work() { _eleven_files; _commit_all "work"; }

# 이미 있는 mod*.js 를 전부 고친다(그 변경만으로 Medium). $1 이 있으면 그 제목으로 커밋한다.
_edit_all() {
    local f
    for f in "$REPO_DIR"/mod*.js; do echo "export const EDITED = '${1:-edit}'" >> "$f"; done
    [ -z "${1:-}" ] || _commit_all "$1"
}

_delta_files() { git -C "$REPO_DIR" show --format= --name-only "$1"; }

@test "simplify 가 고친 내용 때문에 simplify 를 다시 요구하지 않는다" {
    _medium_work
    _record simplify
    _edit_all "simplify fixes"
    _record code-review
    _gate "git push"
    [ "$status" -eq 0 ]
    [[ "$output" == *"이 작업에서 이미 본 파일 11개"* ]]
}

@test "리뷰 지적을 반영한 변경은 code-review 만 요구한다" {
    _medium_work
    _record simplify
    _record code-review
    _edit_all "review fixes"
    _gate "git push"
    [ "$status" -eq 2 ]
    [[ "$output" == *"- /code-review:"* ]]
    [[ "$output" != *"- /simplify:"* ]]
    local sha; sha="$(_delta_commit "$output")"
    [ -n "$sha" ]

    _record code-review "$sha"
    _gate "git push"
    [ "$status" -eq 0 ]
}

@test "이 작업에서 simplify 를 돌린 적이 없으면 그대로 막는다" {
    _medium_work
    _record code-review
    _gate "git push"
    [ "$status" -eq 2 ]
    [[ "$output" == *"- /simplify:"* ]]
    [ "$(_block_kinds)" = '"kind":"missing"' ]
}

@test "지난 작업에서 본 기록은 새 작업의 근거가 되지 않는다" {
    # 커버리지와 작업 기록은 push 뒤에도 지워지지 않는다. 기준 커밋을 가리지 않으면, 지난 작업에서
    # simplify 가 본 파일을 다시 고치는 새 작업이 simplify 를 한 번도 돌리지 않고 통과한다.
    _medium_work
    _record simplify
    _record code-review
    git -C "$REPO_DIR" update-ref refs/remotes/origin/main HEAD      # 지난 작업은 올라갔다

    _edit_all "next work on the same files"
    _record code-review
    _gate "git push"
    [ "$status" -eq 2 ]
    [[ "$output" == *"- /simplify:"* ]]
    [[ "$output" != *"이 작업에서 이미 본 파일"* ]]
}

@test "simplify 뒤에 새로 생긴 파일은 그 파일들만 잰다 (Medium 이상이면 요구한다)" {
    _medium_work
    _record simplify
    _edit_all                                   # 본 파일의 이후 변경은 세지 않는다
    _eleven_files extra                         # 본 적 없는 새 파일 11개
    _commit_all "follow-up with new files"
    _record code-review
    _gate "git push"
    [ "$status" -eq 2 ]
    [[ "$output" == *"- /simplify:"* ]]
    local sha; sha="$(_delta_commit "$(printf '%s\n' "$output" | grep -- '- /simplify:')")"
    [ -n "$sha" ]
    [ "$(_delta_files "$sha" | grep -c '^extra')" -eq 11 ]
    [ "$(_delta_files "$sha" | grep -c .)" -eq 11 ]

    # 알려 준 커밋만 다시 보면 통과한다
    _record simplify "$sha"
    _gate "git push"
    [ "$status" -eq 0 ]
}

@test "simplify 뒤에 생긴 새 파일이 적으면 다시 요구하지 않는다" {
    _medium_work
    _record simplify
    _edit_all
    echo "export const HELPER = 1" > "$REPO_DIR/helper.js"
    _commit_all "fixes with one small new file"
    _record code-review
    _gate "git push"
    [ "$status" -eq 0 ]
    [[ "$output" == *"이 작업에서 이미 본 파일 11개"* ]]
}

@test "경로를 짚어 돌린 simplify 는 그 경로만 본 것으로 친다" {
    _eleven_files
    echo "export const F12 = 12" > "$REPO_DIR/mod12.js"
    _commit_all "work"
    _record simplify "mod1.js"
    _edit_all "edits everywhere"
    _record code-review
    _gate "git push"
    [ "$status" -eq 2 ]
    local sha; sha="$(_delta_commit "$(printf '%s\n' "$output" | grep -- '- /simplify:')")"
    [ -n "$sha" ]
    [ "$(_delta_files "$sha" | grep -c .)" -eq 11 ]
    run _delta_files "$sha"
    [[ "$output" != *"mod1.js"* ]]
}

@test "작업 브랜치에서 리뷰하고 main 에 fast-forward 로 합쳐 올려도 같은 작업이다" {
    git -C "$REPO_DIR" checkout -q -b feat
    _medium_work
    _record simplify
    _edit_all "simplify fixes"
    _record code-review
    git -C "$REPO_DIR" checkout -q main
    git -C "$REPO_DIR" merge -q --ff-only feat
    _gate "git push origin main"
    [ "$status" -eq 0 ]
}

@test "커밋하기 전에 돌린 simplify 도 이 작업의 것으로 친다" {
    _eleven_files
    _record simplify
    _edit_all
    _commit_all "work with simplify fixes"
    _record code-review
    _gate "git push"
    [ "$status" -eq 0 ]
}

@test "code-review 와 security-review 는 대상이 아니다: 본 파일이 바뀌면 그대로 요구한다" {
    _reviewed_work
    _add_external_call "$REPO_DIR/client.js" v2
    _commit_all "new call after review"
    _gate "git push"
    [ "$status" -eq 2 ]
    [[ "$output" == *"- /code-review:"* ]]
    [[ "$output" == *"- /security-review:"* ]]
    [[ "$output" != *"- /simplify:"* ]]
}

@test "넘긴 사실이 효능 원장에 따로 남는다 (차단이 아니라 건너뜀)" {
    _medium_work
    _record simplify
    _edit_all "simplify fixes"
    _record code-review
    _gate "git push"
    [ "$status" -eq 0 ]
    grep -q '"type":"skip","phase":"review","kind":"simplify-once"' "$MANGOLOVE_DIR/efficacy/proj.jsonl"
}

@test "status 와 터미널 push(pre-push 훅)도 같은 판정을 쓴다" {
    _medium_work
    _record simplify
    _edit_all "simplify fixes"
    _record code-review

    local sha base
    sha="$(git -C "$REPO_DIR" rev-parse HEAD)"; base="$(git -C "$REPO_DIR" rev-parse origin/main)"
    run bash -c "cd '$REPO_DIR' && printf 'refs/heads/main %s refs/heads/main %s\n' '$sha' '$base' | GIT_DIR='$REPO_DIR/.git' bash '$GATE' prepush origin /tmp/fake.git"
    [ "$status" -eq 0 ]

    cd "$REPO_DIR"
    run bash "$GATE" status
    [[ "$output" == *"PASS"* ]]
    [[ "$output" == *"이 작업에서 이미 본 파일 11개"* ]]
}
