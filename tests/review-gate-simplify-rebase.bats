#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove: Review gate: simplify 뒤에 리베이스해도 같은 작업이다
# 게이트의 목적과 회귀 대상 행동은 tests/review-gate.bats 머리말에 있다.
#
# simplify 의 "이 작업에서 본 파일" 판정(review-gate-simplify-once.bats)은 기록할 때의 기준 커밋이
# 지금 push 경계와 같아야 했다. 그래서 아직 올리지 않은 작업을 앞으로 나아간 기준 위로 리베이스하면
# 같은 작업인데도 기록을 버렸다. 그 경우와, 올렸거나 합친 뒤 같은 브랜치 이름으로 시작한 새 작업을
# 브랜치의 reflog 로 가른다. 근거와 실측은 lib/review-gate.sh 의 PRE_REVIEW_SKILL 위 주석에 있다.
# ─────────────────────────────────────────────

load test_helper
load review_gate_helper

@test "올리기 전에 앞으로 나아간 기준 위로 리베이스해도 같은 작업이다" {
    # CRS 2026-10-16 CRS-1173 을 옮겼다: 커밋 전에 simplify, 그 수정을 커밋, 그사이 develop 에 남의
    # 커밋이 들어와 그 위로 리베이스. 게이트가 simplify 가 본 파일까지 미검토로 세어 다시 요구했다.
    git -C "$REPO_DIR" checkout -q -b feat
    _eleven_files
    _record simplify                            # 아직 커밋 전
    _edit_all
    _commit_all "work with simplify fixes"
    _record code-review
    _advance_upstream a
    git -C "$REPO_DIR" rebase -q origin/main
    _gate "git push origin feat"
    [ "$status" -eq 0 ]
    [[ "$output" == *"이 작업에서 이미 본 파일 11개"* ]]
}

@test "커밋한 뒤 돌린 simplify 도 리베이스 뒤에 같은 작업이다" {
    git -C "$REPO_DIR" checkout -q -b feat
    _eleven_files
    _commit_all "work"
    _record simplify
    _edit_all "simplify fixes"
    _record code-review
    _advance_upstream a
    git -C "$REPO_DIR" rebase -q origin/main
    _gate "git push origin feat"
    [ "$status" -eq 0 ]
    [[ "$output" == *"이 작업에서 이미 본 파일 11개"* ]]
}

@test "합쳐진 작업 뒤 같은 브랜치 이름을 기준으로 되돌려 시작한 새 작업은 다르다" {
    # CRS 2026-10-16 CRS-1088 을 옮겼다: 머지된 브랜치를 `git switch -C <브랜치> origin/develop` 으로
    # 되돌려 후속 작업을 했다. 기준이 앞으로 갔고 브랜치 이름도 같지만, 앞 작업은 이미 원격에 있다.
    git -C "$REPO_DIR" checkout -q -b feat
    _eleven_files
    _record simplify
    _commit_all "first work"
    git -C "$REPO_DIR" update-ref refs/remotes/origin/main HEAD      # 머지되어 올라갔다
    git -C "$REPO_DIR" checkout -q -B feat origin/main
    _edit_all "follow-up on the same files"
    _record code-review
    _gate "git push origin feat"
    [ "$status" -eq 2 ]
    [[ "$output" == *"- /simplify:"* ]]
    [[ "$output" != *"이 작업에서 이미 본 파일"* ]]
}

@test "한 번 올린 브랜치에 새 작업을 얹어 리베이스해도 새 작업이다" {
    git -C "$REPO_DIR" checkout -q -b feat
    _eleven_files
    _record simplify
    _commit_all "first work"
    git -C "$REPO_DIR" update-ref refs/remotes/origin/feat HEAD      # 이 브랜치를 올렸다
    _advance_upstream a
    _edit_all "second work on the same files"
    _record code-review
    git -C "$REPO_DIR" rebase -q origin/main
    _gate "git push -f origin feat"
    [ "$status" -eq 2 ]
    [[ "$output" == *"- /simplify:"* ]]
    [[ "$output" != *"이 작업에서 이미 본 파일"* ]]
}

@test "지우고 같은 이름으로 새 기준에서 다시 만든 브랜치는 앞 시도의 기록을 쓰지 않는다" {
    git -C "$REPO_DIR" checkout -q -b feat
    _eleven_files
    _record simplify
    _commit_all "abandoned attempt"
    git -C "$REPO_DIR" checkout -q main
    git -C "$REPO_DIR" branch -q -D feat
    _advance_upstream a
    git -C "$REPO_DIR" checkout -q -b feat origin/main
    _eleven_files
    _edit_all "second attempt on the same files"
    _record code-review
    _gate "git push origin feat"
    [ "$status" -eq 2 ]
    [[ "$output" == *"- /simplify:"* ]]
    [[ "$output" != *"이 작업에서 이미 본 파일"* ]]
}

@test "리베이스 뒤에 처음 손댄 파일은 그 파일들만 잰다" {
    git -C "$REPO_DIR" checkout -q -b feat
    _eleven_files
    _record simplify
    _commit_all "work"
    _advance_upstream a
    git -C "$REPO_DIR" rebase -q origin/main
    _eleven_files new
    _commit_all "eleven new files after rebase"
    _record code-review
    _gate "git push origin feat"
    [ "$status" -eq 2 ]
    [[ "$output" == *"- /simplify: 이 스킬이 보지 않은 변경이 파일 11개"* ]]
}

@test "다른 줄기 위로 옮긴 작업은 같은 작업으로 보지 않는다" {
    # 기준이 앞으로 간 것이 아니라 옆으로 옮겨진 경우다(예: develop 에서 딴 작업을 release 위로).
    # 올리는 범위의 바탕이 달라지므로 앞서 본 기록을 넘기지 않는다.
    _advance_upstream a
    _remote_foreign_work release origin/main~1
    git -C "$REPO_DIR" checkout -q -b feat origin/main
    _eleven_files
    _record simplify
    _edit_all
    _commit_all "work with simplify fixes"
    _record code-review
    git -C "$REPO_DIR" rebase -q --onto origin/release origin/main feat
    _gate "git push origin feat"
    [ "$status" -eq 2 ]
    [[ "$output" == *"- /simplify:"* ]]
    [[ "$output" != *"이 작업에서 이미 본 파일"* ]]
}

@test "커밋한 뒤 돌린 기록도, 그 커밋을 올린 뒤 리베이스한 새 작업의 근거가 되지 않는다" {
    # 기록할 때의 커밋이 곧 작업의 일부다. 그 커밋이 원격에 있으면 작업은 이미 이 머신을 떠났다.
    git -C "$REPO_DIR" checkout -q -b feat
    _eleven_files
    _commit_all "first work"
    _record simplify
    git -C "$REPO_DIR" update-ref refs/remotes/origin/feat HEAD      # 이 브랜치를 올렸다
    _advance_upstream a
    _edit_all "second work on the same files"
    _record code-review
    git -C "$REPO_DIR" rebase -q origin/main
    _gate "git push -f origin feat"
    [ "$status" -eq 2 ]
    [[ "$output" == *"- /simplify:"* ]]
    [[ "$output" != *"이 작업에서 이미 본 파일"* ]]
}

@test "-u 로 올린 브랜치가 squash 머지되고 원격 브랜치가 사라진 뒤의 새 작업은 다르다" {
    # squash 머지는 이 브랜치의 커밋을 원격에 남기지 않고, prune 은 원격 추적 ref 를 지운다.
    # 원격에 남은 커밋이 없어도, upstream 설정이 남아 있는데 그 ref 가 없으면 이미 올린 작업이다.
    git -C "$REPO_DIR" checkout -q -b feat
    _eleven_files
    _commit_all "first work"
    _record simplify
    git -C "$REPO_DIR" update-ref refs/remotes/origin/feat HEAD      # git push -u origin feat
    git -C "$REPO_DIR" config branch.feat.remote origin
    git -C "$REPO_DIR" config branch.feat.merge refs/heads/feat
    git -C "$REPO_DIR" checkout -q -B squash-tmp origin/main         # PR 을 squash 로 머지
    git -C "$REPO_DIR" merge -q --squash feat
    _commit_all "squashed first work"
    git -C "$REPO_DIR" update-ref refs/remotes/origin/main HEAD
    git -C "$REPO_DIR" checkout -q feat
    git -C "$REPO_DIR" branch -q -D squash-tmp
    git -C "$REPO_DIR" update-ref -d refs/remotes/origin/feat         # fetch --prune
    _edit_all "second work on the same files"
    _record code-review
    git -C "$REPO_DIR" rebase -q origin/main
    _gate "git push origin feat"
    [ "$status" -eq 2 ]
    [[ "$output" == *"- /simplify:"* ]]
    [[ "$output" != *"이 작업에서 이미 본 파일"* ]]
}
