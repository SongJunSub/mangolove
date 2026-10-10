#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove: Review gate: 판정 범위와 push 가 도는 레포
# 게이트의 목적과 회귀 대상 행동은 tests/review-gate.bats 머리말에 있다.
# ─────────────────────────────────────────────

load test_helper
load review_gate_helper

# ── 판정 범위의 기준 (2026-09-10 실사례: 리뷰를 다 돌렸는데 막혔다) ─────────
#
# 기준을 origin/main 으로 추정하면 develop, 통합 브랜치에서 딴 작업에 남의 커밋이 섞인다.
# 그 파일들은 어떤 리뷰로도 덮을 수 없어 차단이 영영 풀리지 않았다.

@test "기준: develop 에서 딴 브랜치는 main 에 없는 develop 커밋을 범위에 넣지 않는다 (CRS-1031)" {
    _remote_foreign_work develop
    git -C "$REPO_DIR" checkout -q -b CRS-1031 refs/remotes/origin/develop
    echo fix > "$REPO_DIR/fix.txt"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm fix
    # 명시 refspec(첫 push)과 인자 없는 push 둘 다
    _gate "git push -u origin CRS-1031"
    [ "$status" -eq 0 ]
    _gate "git push"
    [ "$status" -eq 0 ]
}

@test "기준: develop 에서 딴 브랜치라도 자기 변경은 여전히 리뷰를 요구한다 (안전 유지)" {
    _remote_foreign_work develop
    git -C "$REPO_DIR" checkout -q -b CRS-1 refs/remotes/origin/develop
    _commit_external_api
    _gate "git push -u origin CRS-1"
    [ "$status" -eq 2 ]
    [[ "$output" == *"보지 않은 파일 1개"* ]]      # 남의 커밋 11개가 섞이지 않았다
    _run_all_reviews
    _gate "git push -u origin CRS-1"
    [ "$status" -eq 0 ]
}

@test "기준: 통합 브랜치에서 딴 하위 티켓은 통합 브랜치의 다른 티켓 커밋을 넣지 않는다 (HUB2-390)" {
    _remote_foreign_work HUB2-312
    git -C "$REPO_DIR" checkout -q -b HUB2-390 refs/remotes/origin/HUB2-312
    echo small > "$REPO_DIR/small.txt"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm small
    _gate "git push -u origin HUB2-390"
    [ "$status" -eq 0 ]
}

@test "기준: rebase 뒤 force push 에 그사이 develop 에 들어온 남의 커밋이 딸려 오지 않는다" {
    git -C "$REPO_DIR" update-ref refs/remotes/origin/develop main
    git -C "$REPO_DIR" checkout -q -b feat refs/remotes/origin/develop
    echo mine > "$REPO_DIR/mine.txt"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm mine
    git -C "$REPO_DIR" update-ref refs/remotes/origin/feat HEAD          # 한 번 올렸다
    git -C "$REPO_DIR" checkout -q main
    _remote_foreign_work develop refs/remotes/origin/develop              # develop 이 앞서 나갔다
    git -C "$REPO_DIR" checkout -q feat
    git -C "$REPO_DIR" rebase -q refs/remotes/origin/develop
    _gate "git push --force-with-lease origin feat"
    [ "$status" -eq 0 ]
}

@test "기준: 원격 브랜치를 머지해 온 파일은 빠지고, 머지 뒤 새로 쓴 코드는 남는다" {
    _remote_foreign_work other
    git -C "$REPO_DIR" checkout -q -b feat
    echo mine > "$REPO_DIR/mine.txt"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm mine
    git -C "$REPO_DIR" merge -q --no-ff -m "merge other" refs/remotes/origin/other
    _gate "git push -u origin feat"
    [ "$status" -eq 0 ]
    # 머지 뒤에 검토되지 않은 Medium 코드를 얹으면 여전히 막힌다
    _commit_external_api
    _gate "git push -u origin feat"
    [ "$status" -eq 2 ]
}

@test "기준: -u 로 upstream 이 자기 브랜치로 바뀌어도 딴 지점 이름은 비교 기준으로 본다" {
    _remote_foreign_work develop
    git -C "$REPO_DIR" checkout -q -b feat refs/remotes/origin/develop
    git -C "$REPO_DIR" config branch.feat.remote origin
    git -C "$REPO_DIR" config branch.feat.merge refs/heads/feat
    git -C "$REPO_DIR" update-ref refs/remotes/origin/feat HEAD
    git -C "$REPO_DIR" checkout -q main
    _remote_foreign_work develop refs/remotes/origin/develop              # develop 이 앞서 나갔다
    git -C "$REPO_DIR" checkout -q feat
    _commit_external_api
    _run_all_reviews "origin/develop 대비 변경"
    _gate "git push"
    [ "$status" -eq 0 ]
}

# ── push 가 도는 레포 (cwd 가 아니라 명령이 가리키는 곳) ─────────────

@test "대상 레포: git -C 로 다른 레포를 올리면 cwd 가 아니라 그 레포를 판정한다" {
    _other_repo
    _commit_external_api                           # cwd 레포: 미검토 Medium (이번에 안 올린다)
    _commit_external_api_in "$OTHER"
    CWD="$OTHER" _run_all_reviews
    _gate "git -C $OTHER push -u origin main"
    [ "$status" -eq 0 ]                            # 옛 동작: cwd 레포를 보고 막았다
}

@test "대상 레포: cwd 가 깨끗해도 git -C 로 올리는 레포가 미검토면 막는다" {
    _other_repo
    _commit_external_api_in "$OTHER"
    _gate "git -C $OTHER push -u origin main"
    [ "$status" -eq 2 ]                            # 옛 동작: 깨끗한 cwd 를 보고 통과시켰다
}

@test "대상 레포: 변수에 담은 경로로 cd 해서 올려도 그 레포를 판정한다" {
    _other_repo
    _commit_external_api_in "$OTHER"
    _gate "W=$OTHER; cd \"\$W\" && git push -u origin main 2>&1 | tail -8"
    [ "$status" -eq 2 ]
}

@test "대상 레포: 따옴표로 묶은 변수 경로를 여러 줄 명령에서도 푼다" {
    _other_repo
    _commit_external_api_in "$OTHER"
    _gate "W=$OTHER\ngit -C \"\$W\" push -u origin main"
    [ "$status" -eq 2 ]
}

@test "대상 레포: for 루프로 두 레포를 올리면 둘 다 판정한다" {
    _other_repo
    _commit_external_api_in "$OTHER"               # other 만 미검토
    _gate "for R in $REPO_DIR $OTHER; do git -C \"\$R\" push; done"
    [ "$status" -eq 2 ]
}

@test "대상 레포: 한 명령의 push 가 여럿이면 두 번째 것도 판정한다" {
    _other_repo
    _commit_external_api_in "$OTHER"
    _gate "git push origin main && git -C $OTHER push origin main"
    [ "$status" -eq 2 ]
}

@test "대상 레포: 명령치환으로 준 디렉토리는 바뀌지 않은 것으로 보고 세션 레포에서 판정한다" {
    # 판정 불가로 통과시키면 `git -C "$(git rev-parse --show-toplevel)" push` 같은 흔한 형태의 미검토 push 가 샌다.
    _commit_external_api
    _gate 'git -C "$(git rev-parse --show-toplevel)" push'
    [ "$status" -eq 2 ]
}

@test "대상 레포: 따옴표 없는 명령치환 경로도 서브커맨드를 잘못 읽지 않는다" {
    _commit_external_api
    _gate 'git -C $(git rev-parse --show-toplevel) push'
    [ "$status" -eq 2 ]
}

@test "refspec: 리다이렉션(2>&1)을 refspec 으로 오인해 통과시키지 않는다" {
    _commit_external_api
    _gate "git push -u origin main 2>&1 | tail -8"
    [ "$status" -eq 2 ]
}

@test "gate: 커밋 메시지 속 git push 글자를 push 로 오인하지 않는다" {
    _commit_external_api
    _gate 'git commit -m "fix git push flow"'
    [ "$status" -eq 0 ]
}

# ── 두 트리를 한 번에 리뷰한 호출 (2026-09-10 CRS-1031 실제 인자 모양) ──────

@test "두 트리: 한 리뷰 호출이 두 작업 트리를 짚으면 두 레포 push 가 모두 통과한다" {
    _other_repo
    _commit_external_api
    _commit_external_api_in "$OTHER"
    # 실제 호출 모양: 기준 ref, 괄호 설명, 조사가 붙은 경로가 섞인 산문
    _run_all_reviews "medium 두 워크트리의 origin/main 대비 변경(미추적 파일 포함): (1) $REPO_DIR (crs) 및 (2) ${OTHER}의 변경"
    _gate "git push -u origin main"
    [ "$status" -eq 0 ]
    _gate "W=$OTHER; git -C \"\$W\" push -u origin main"
    [ "$status" -eq 0 ]
}

@test "두 트리: 다른 트리만 짚은 호출은 cwd 트리를 커버하지 않는다" {
    _other_repo
    _commit_external_api
    _commit_external_api_in "$OTHER"
    _run_all_reviews "medium ${OTHER} 의 변경만"
    _gate "git push -u origin main"
    [ "$status" -eq 2 ]
    _gate "git -C $OTHER push -u origin main"
    [ "$status" -eq 0 ]
}

@test "범위: 산문에 섞인 --cached) 같은 낱말은 대상 신호가 아니다 (CRS-968)" {
    printf 'const a = await axios.get("https://api.example.com/a")\n' > "$REPO_DIR/a.js"
    _run_all_reviews "두 레포의 스테이징된 변경: $REPO_DIR (git diff --cached) 확인"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm staged
    _gate "git push"
    [ "$status" -eq 0 ]
}

@test "범위: 레포 밖이라도 코드가 아닌 경로(스크래치 파일)는 다른 대상이 아니다" {
    _commit_external_api
    local note="$TEST_DIR/scratch-note.md"; echo memo > "$note"
    _run_all_reviews "high 결과는 $note 에 적는다"
    _gate "git push"
    [ "$status" -eq 0 ]
}

@test "범위: '이 워크트리' 지시어와 함께 다른 트리를 맥락으로 적은 호출은 이 트리를 본 것이다 (HUB2-390)" {
    _other_repo
    _commit_external_api
    _commit_external_api_in "$OTHER"
    _run_all_reviews "이 워크트리(main)의 origin/main...HEAD 전체. 프론트는 ${OTHER} 에 있음."
    _gate "git push"
    [ "$status" -eq 0 ]
    # 맥락으로 적은 다른 트리는 리뷰된 것으로 기록하지 않는다(한 번도 안 본 레포가 통과하면 안 된다)
    _gate "git -C $OTHER push -u origin main"
    [ "$status" -eq 2 ]
}

@test "범위: 한글 낱말의 빈 정리형이 ref 목록의 빈 줄과 맞지 않는다" {
    local fresh="$TEST_DIR/fresh"; mkdir -p "$fresh"
    git -C "$fresh" init -q -b main
    run bash -c "cd '$fresh' && source '$GATE' && _coverage_scope '변경 전체 검토' && echo \"\$COVERAGE_MODE\""
    [ "$output" = "all" ]
}
