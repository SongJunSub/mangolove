#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove: Review gate: simplify 는 한 작업에서 한 번 본 파일을 다시 요구받지 않는다
# 게이트의 목적과 회귀 대상 행동은 tests/review-gate.bats 머리말에 있다.
#
# simplify 는 코드를 고치는 스킬이라 커버리지(호출 시점의 내용)로 재면 자기 수정 때문에 스스로 어긴다.
# 그래서 "이 작업에서 그 파일을 한 번이라도 봤는가"로 본다. 근거와 실측은 lib/review-gate.sh 의
# PRE_REVIEW_SKILL 위 주석에 있다.
# ─────────────────────────────────────────────

load test_helper
load review_gate_helper

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
    # 넘긴 사실은 효능 원장에 따로 남는다(차단이 아니라 건너뜀)
    grep -q '"type":"skip","phase":"review","kind":"simplify-once"' "$MANGOLOVE_DIR/efficacy/proj.jsonl"
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
    # 넘긴 사실은 부족 목록 밖에 따로 적는다. 목록 안에 있으면 simplify 가 남은 것으로 읽힌다.
    [[ "$output" == *"참고: simplify 는 이 작업에서 이미 본 파일 11개"* ]]
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
    local sha; sha="$(_delta_commit "$output" simplify)"
    [ -n "$sha" ]
    [ "$(_delta_files "$sha" | grep -c '^extra')" -eq 11 ]
    [ "$(_delta_files "$sha" | grep -c .)" -eq 11 ]

    # 알려 준 커밋만 다시 보면 통과한다
    _record simplify "$sha"
    _gate "git push"
    [ "$status" -eq 0 ]

    # 그렇게 본 파일도 이 작업에서 본 것이다. simplify 가 그 파일들을 고쳐도 또 요구하지 않는다.
    local f
    for f in "$REPO_DIR"/extra*.js; do echo "export const TIDIED = 1" >> "$f"; done
    _commit_all "simplify fixes on the new files"
    _record code-review
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
    local sha; sha="$(_delta_commit "$output" simplify)"
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


# ── 작업을 가르는 기준: 기준 커밋이 같고, 기록한 브랜치를 올리거나 기록한 커밋이 그 조상이어야 한다 ──

@test "같은 기준에서 갈라진 다른 브랜치에서 본 기록은 근거가 되지 않는다" {
    # 한 작업 트리에서 티켓 a 를 올리고, main 이 그대로인 채 티켓 b 를 시작하는 흔한 순서다.
    # 기준 커밋만 견주면 a 에서 simplify 가 본 파일을 b 가 고칠 때 simplify 없이 통과한다.
    git -C "$REPO_DIR" checkout -q -b a
    _medium_work
    _record simplify
    git -C "$REPO_DIR" checkout -q main
    git -C "$REPO_DIR" checkout -q -b b
    _eleven_files
    _edit_all "another ticket on the same files"
    _record code-review
    _gate "git push origin b"
    [ "$status" -eq 2 ]
    [[ "$output" == *"- /simplify:"* ]]
    [[ "$output" != *"이 작업에서 이미 본 파일"* ]]
}

@test "다른 브랜치의 변경분 커밋을 짚어 본 기록은 그 브랜치의 것이다" {
    git -C "$REPO_DIR" checkout -q -b other
    _medium_work
    _record simplify
    _eleven_files extra
    _commit_all "new files on other"
    _record code-review
    git -C "$REPO_DIR" checkout -q main
    _gate "git push origin other"
    [ "$status" -eq 2 ]
    local sha f; sha="$(_delta_commit "$output" simplify)"
    [ -n "$sha" ]
    _record simplify "$sha"                     # main 에 선 채로 other 의 변경분을 본다

    # main 의 다른 작업이 같은 이름의 파일을 만든다. other 에서 본 것으로 면제되면 안 된다.
    _eleven_files extra
    for f in "$REPO_DIR"/extra*.js; do echo "export const ON_MAIN = 1" >> "$f"; done
    _commit_all "unrelated work on main"
    _record code-review
    _gate "git push origin main"
    [ "$status" -eq 2 ]
    [[ "$output" == *"- /simplify:"* ]]
}

@test "simplify 뒤에 커밋을 고쳐 써도(amend) 같은 작업이다" {
    _medium_work
    _record simplify
    _edit_all
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -q --amend -m "work, with simplify fixes"
    _record code-review
    _gate "git push"
    [ "$status" -eq 0 ]
    [[ "$output" == *"이 작업에서 이미 본 파일 11개"* ]]
}

@test "원격을 merge 로 받아 와도 같은 작업이다" {
    # 경계가 둘이 되면 범위의 대표 기준이 원격 쪽 끝으로 바뀐다. 원래 기준도 여전히 경계다.
    _medium_work
    _record simplify
    _edit_all "simplify fixes"
    _record code-review
    git -C "$REPO_DIR" checkout -q -b upstream origin/main
    echo upstream > "$REPO_DIR/upstream.txt"
    _commit_all "upstream work"
    git -C "$REPO_DIR" update-ref refs/remotes/origin/main HEAD
    git -C "$REPO_DIR" checkout -q main
    git -C "$REPO_DIR" branch -q -D upstream
    git -C "$REPO_DIR" merge -q --no-edit origin/main
    _gate "git push"
    [ "$status" -eq 0 ]
    [[ "$output" == *"이 작업에서 이미 본 파일 11개"* ]]
}

@test "버린 브랜치에서 본 기록은 근거가 되지 않는다" {
    # 커밋하고 simplify 까지 돌린 시도를 버리고(브랜치 삭제) 같은 기준에서 다시 시작한 경우다.
    # 그 커밋은 어느 ref 에도 닿지 않지만 고쳐 쓴(amend) 것이 아니다.
    git -C "$REPO_DIR" checkout -q -b attempt1
    _medium_work
    _record simplify
    git -C "$REPO_DIR" checkout -q main
    git -C "$REPO_DIR" branch -q -D attempt1
    git -C "$REPO_DIR" checkout -q -b attempt2
    _eleven_files
    _edit_all "second attempt on the same files"
    _record code-review
    _gate "git push origin attempt2"
    [ "$status" -eq 2 ]
    [[ "$output" == *"- /simplify:"* ]]
    [[ "$output" != *"이 작업에서 이미 본 파일"* ]]
}

@test "첫 커밋 전에 본 기록도 다른 브랜치의 작업에는 근거가 되지 않는다" {
    # 방법론이 권하는 순서(커밋 전에 리뷰)에서는 기록할 때의 커밋이 곧 기준이라 조상 관계로는
    # 가를 수 없다. 기록한 브랜치로 가른다.
    git -C "$REPO_DIR" checkout -q -b ticket1
    _eleven_files
    _record simplify                            # 아직 커밋 전
    _commit_all "ticket 1"
    git -C "$REPO_DIR" checkout -q main
    git -C "$REPO_DIR" checkout -q -b ticket2
    _eleven_files
    _edit_all "ticket 2 on the same files"
    _record code-review
    _gate "git push origin ticket2"
    [ "$status" -eq 2 ]
    [[ "$output" == *"- /simplify:"* ]]
    [[ "$output" != *"이 작업에서 이미 본 파일"* ]]
}

@test "작업 브랜치를 지운 뒤 main 을 올려도, 커밋한 뒤 본 기록은 같은 작업이다" {
    git -C "$REPO_DIR" checkout -q -b feat
    _medium_work
    _record simplify
    _edit_all "simplify fixes"
    _record code-review
    git -C "$REPO_DIR" checkout -q main
    git -C "$REPO_DIR" merge -q --ff-only feat
    git -C "$REPO_DIR" branch -q -d feat
    _gate "git push origin main"
    [ "$status" -eq 0 ]
}

@test "변경분 커밋을 흉내 낸 커밋을 짚어도 이 작업에서 본 것으로 치지 않는다" {
    # 게이트가 만든 변경분 커밋만 자기 작업을 안다(게이트 상태에 적어 둔다). 제목과 본문을 흉내 낸
    # 커밋으로 모든 파일을 "본 것"으로 만들 수 있으면, 근거가 남지 않는 우회가 된다.
    _medium_work
    _record code-review
    local fake base
    base="$(git -C "$REPO_DIR" rev-parse origin/main)"
    fake="$(git -C "$REPO_DIR" commit-tree 'HEAD^{tree}' -p origin/main \
        -m "mangolove review gate: 리뷰 뒤 변경" -m "unit: $base"$'\n'"head: $(git -C "$REPO_DIR" rev-parse HEAD)")"
    _record simplify "$fake"
    _edit_all "more work"
    _record code-review
    _gate "git push"
    [ "$status" -eq 2 ]
    [[ "$output" == *"- /simplify:"* ]]
    [[ "$output" != *"이 작업에서 이미 본 파일"* ]]
}

@test "넘길 필요가 없던 사소한 수정은 넘긴 것으로 세지 않는다" {
    # 본 파일 하나를 한 줄 고친 것은 그것만으로 simplify 대상이 아니다. 효능 원장에 넘김으로 적으면
    # 이 규칙이 실제로 무엇을 넘겼는지 볼 수 없게 된다.
    _medium_work
    _record simplify
    _record code-review
    echo "export const ONE_LINE = 1" >> "$REPO_DIR/mod1.js"
    _commit_all "one-line fix"
    _gate "git push"
    [ "$status" -eq 0 ]
    [[ "$output" != *"이 작업에서 이미 본 파일"* ]]
    # 넘긴 것이 하나도 없으면 원장 파일 자체가 없을 수 있다
    local lg="$MANGOLOVE_DIR/efficacy/proj.jsonl"
    [ ! -f "$lg" ] || [ "$(grep -c '"kind":"simplify-once"' "$lg")" = "0" ]
}
