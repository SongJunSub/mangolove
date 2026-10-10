#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove: Review gate: 게이트 상태 위조
# 게이트의 목적과 회귀 대상 행동은 tests/review-gate.bats 머리말에 있다.
# ─────────────────────────────────────────────

load test_helper
load review_gate_helper

# ── 게이트 상태 위조 (Critical) ────────────────────────────────
#
# .gitignore 는 git add -f 를 막지 못한다. 상태가 워킹트리에 있으면 적대적 브랜치가
# 위조본을 커밋해 두고, 그 브랜치를 checkout 한 사람에게 그대로 배달할 수 있다.
# 터미널 경로는 세션 ID 가 없어 디스크의 원장을 그대로 믿으므로 리뷰 0회로 통과했다.

@test "위조: 브랜치가 실어 온 원장은 터미널 push 를 통과시키지 못한다" {
    _commit_external_api
    local sha base
    # 위조본을 추적되게 커밋한다
    mkdir -p "$REPO_DIR/.mangolove"
    printf 'simplify\ncode-review\nsecurity-review\n' > "$REPO_DIR/.mangolove/.review-ledger"
    : > "$REPO_DIR/.mangolove/.review-covered"
    local f h s
    for f in client.js; do
        h=$(git -C "$REPO_DIR" hash-object "$REPO_DIR/$f")
        for s in simplify code-review security-review; do
            printf '%s\t%s\t%s\n' "$s" "$h" "$f" >> "$REPO_DIR/.mangolove/.review-covered"
        done
    done
    git -C "$REPO_DIR" add -f .mangolove/.review-ledger .mangolove/.review-covered
    git -C "$REPO_DIR" commit -qm forged
    sha=$(git -C "$REPO_DIR" rev-parse HEAD)
    base=$(git -C "$REPO_DIR" rev-parse origin/main)
    run bash -c "cd '$REPO_DIR' && printf 'refs/heads/main %s refs/heads/main %s\n' '$sha' '$base' | bash '$GATE' prepush origin /tmp/fake.git"
    [ "$status" -eq 1 ]
}

@test "위조: 게이트 상태는 워킹트리가 아니라 git-dir 아래에 쓴다" {
    printf '%s' "$(_json_skill simplify)" | bash "$GATE" record
    [ -f "$REPO_DIR/.git/mangolove/.review-ledger" ]
    [ ! -f "$REPO_DIR/.mangolove/.review-ledger" ]
}

@test "위조: 추적된 .review-skip 은 우회로 인정하지 않는다" {
    _commit_external_api
    mkdir -p "$REPO_DIR/.mangolove"
    touch "$REPO_DIR/.mangolove/.review-skip"
    git -C "$REPO_DIR" add -f .mangolove/.review-skip
    git -C "$REPO_DIR" commit -qm "forged skip"
    _gate "git push"
    [ "$status" -eq 2 ]
    [[ "$output" == *"추적되고 있습니다"* ]]
    # 소비되지 않아야 한다(추적 파일을 지우면 워킹트리가 더러워진다)
    [ -f "$REPO_DIR/.mangolove/.review-skip" ]
}

# 안내대로 했을 때 실어 온 내용이 우회 근거로 쓰이면 안 된다. 예전 안내(git rm --cached 후 touch)는
# 파일을 비우지 않아, 브랜치가 적어 온 근거가 그대로 감사 기록에 남는 우회가 됐다(재현됨).
@test "위조: 안내대로 지우고 다시 남기면 실어 온 근거가 아니라 새 근거로 우회한다" {
    _commit_external_api
    mkdir -p "$REPO_DIR/.mangolove"
    echo "FORGED-REASON" > "$REPO_DIR/.mangolove/.review-skip"
    git -C "$REPO_DIR" add -f .mangolove/.review-skip
    git -C "$REPO_DIR" commit -qm "forged skip"
    _gate "git push"
    [ "$status" -eq 2 ]
    [[ "$output" == *"git rm -f .mangolove/.review-skip"* ]]
    [[ "$output" != *"touch"* ]]
    git -C "$REPO_DIR" rm -qf .mangolove/.review-skip
    run bash -c "cd '$REPO_DIR' && bash '$GATE' skip '직접 남긴 근거'"
    [ "$status" -eq 0 ]
    _gate "git push"
    [ "$status" -eq 0 ]
    [[ "$output" == *"직접 남긴 근거"* ]]
    [[ "$output" != *"FORGED-REASON"* ]]
}

# 재현된 구멍: 우회 파일이 든 폴더를 가리키는 심볼릭 링크로 .mangolove 를 실어 오면, 추적 여부를
# 링크 너머에서 묻지 않아 위조 마커가 우회로 받아들여졌다.
@test "위조: 브랜치가 실어 온 폴더 링크 너머의 .review-skip 도 우회로 인정하지 않는다" {
    _commit_external_api
    rm -rf "$REPO_DIR/.mangolove"
    mkdir -p "$REPO_DIR/x"
    touch "$REPO_DIR/x/.review-skip"
    ln -s x "$REPO_DIR/.mangolove"
    git -C "$REPO_DIR" add -f x/.review-skip .mangolove
    git -C "$REPO_DIR" commit -qm "forged skip behind a link"
    _gate "git push"
    [ "$status" -eq 2 ]
    [[ "$output" == *"심볼릭 링크"* ]]
    [ -f "$REPO_DIR/x/.review-skip" ]
}

@test "위조: 사용자가 만든 링크라도 그 너머의 .review-skip 이 추적 파일이면 인정하지 않는다" {
    _commit_external_api
    rm -rf "$REPO_DIR/.mangolove"
    mkdir -p "$REPO_DIR/x"
    touch "$REPO_DIR/x/.review-skip"
    git -C "$REPO_DIR" add -f x/.review-skip
    git -C "$REPO_DIR" commit -qm "tracked marker elsewhere"
    ln -s x "$REPO_DIR/.mangolove"
    _gate "git push"
    [ "$status" -eq 2 ]
    [[ "$output" == *"추적되고 있습니다"* ]]
    [ -f "$REPO_DIR/x/.review-skip" ]
}

# 재현된 구멍: git 은 훅을 부를 때 GIT_DIR 을 내보낸다(링크드 worktree 의 pre-push 등). 그 값이 남은
# 채 폴더를 옮겨 물으면 추적 파일을 모른다고 답해, 실어 온 우회 파일로 push 가 통과했다.
@test "위조: GIT_DIR 이 내보내진 pre-push 에서도 추적된 .review-skip 을 알아본다" {
    _commit_external_api
    mkdir -p "$REPO_DIR/.mangolove"
    touch "$REPO_DIR/.mangolove/.review-skip"
    git -C "$REPO_DIR" add -f .mangolove/.review-skip
    git -C "$REPO_DIR" commit -qm "forged skip"
    run bash -c "cd '$REPO_DIR' && GIT_DIR='$REPO_DIR/.git' bash '$GATE' prepush </dev/null"
    [ "$status" -eq 1 ]
    [[ "$output" == *"추적되고 있습니다"* ]]
    [ -f "$REPO_DIR/.mangolove/.review-skip" ]
}

# macOS 기본 파일 시스템은 이름의 대소문자를 가리지 않고 몇몇 유니코드 문자도 같은 글자로 접는다
# (켈빈 기호는 k 로). 그렇게 실어 온 파일은 .review-skip 으로 열린다. 대소문자를 가리는 파일
# 시스템에서는 애초에 열리지 않으므로 "우회되지 않는다"는 어디서나 성립한다.
@test "위조: 이름만 달리 적어 실어 온 .review-skip 도 우회로 인정하지 않는다" {
    _commit_external_api
    local name
    for name in ".REVIEW-SKIP" ".review-s$(printf '\xe2\x84\xaa')ip"; do
        mkdir -p "$REPO_DIR/.mangolove"
        touch "$REPO_DIR/.mangolove/$name"
        git -C "$REPO_DIR" add -f ".mangolove/$name"
        git -C "$REPO_DIR" commit -qm "forged skip under another spelling"
        _gate "git push"
        [ "$status" -eq 2 ] || { echo "bypassed: $name"; false; }
        git -C "$REPO_DIR" rm -qf ".mangolove/$name"
        git -C "$REPO_DIR" commit -qm "drop it"
    done
}

@test "review skip: 이름만 달리 적어 실어 온 폴더 링크(.Mangolove) 너머에도 쓰지 않는다" {
    rm -rf "$REPO_DIR/.mangolove"
    mkdir -p "$TEST_DIR/victim"
    ln -s ../victim "$REPO_DIR/.Mangolove"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm "renamed link out of the repo"
    run bash -c "cd '$REPO_DIR' && bash '$GATE' skip '근거'"
    [ -z "$(ls -A "$TEST_DIR/victim")" ]
}

@test "review skip: 브랜치가 실어 온 폴더 링크 너머에는 마커를 쓰지 않는다" {
    rm -rf "$REPO_DIR/.mangolove"
    mkdir -p "$TEST_DIR/victim"
    ln -s ../victim "$REPO_DIR/.mangolove"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm "link out of the repo"
    run bash -c "cd '$REPO_DIR' && bash '$GATE' skip '근거'"
    [ "$status" -eq 1 ]
    [[ "$output" == *"심볼릭 링크"* ]]
    [ -z "$(ls -A "$TEST_DIR/victim")" ]
}
