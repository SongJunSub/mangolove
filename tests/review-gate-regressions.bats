#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove: Review gate: 명령 해석과 리뷰가 재현한 결함
# 게이트의 목적과 회귀 대상 행동은 tests/review-gate.bats 머리말에 있다.
# ─────────────────────────────────────────────

load test_helper
load review_gate_helper

# ── 명령 해석과 경로 판정 (simplify 리뷰가 재현한 결함) ─────────────

@test "해석: 커밋 메시지 안의 ; 뒤 git push 글자를 push 로 오인하지 않는다" {
    _commit_external_api
    _gate 'git commit -m "wip; git push origin main"'
    [ "$status" -eq 0 ]
}

@test "해석: 서브셸, sh -c, 명령치환, eval 안의 push 도 그 레포에서 판정한다" {
    _other_repo
    _commit_external_api_in "$OTHER"
    _gate "(cd $OTHER && git push)"
    [ "$status" -eq 2 ]
    _gate "bash -c \"cd $OTHER && git push origin main\""
    [ "$status" -eq 2 ]
    _gate "cd $OTHER; out=\$(git push 2>&1)"
    [ "$status" -eq 2 ]
    _gate "cd $OTHER; eval git push"
    [ "$status" -eq 2 ]
}

@test "해석: 변수에 담은 브랜치 이름도 풀어 판정한다 (감사로 새지 않는다)" {
    _commit_external_api
    _gate 'B=main; git push origin "$B"'
    [ "$status" -eq 2 ]
}

@test "해석: 줄 이음으로 나눈 push 의 refspec 을 잇는다" {
    git -C "$REPO_DIR" checkout -q -b topic
    _commit_external_api
    git -C "$REPO_DIR" checkout -q main
    _gate 'git push \\\n  origin topic'
    [ "$status" -eq 2 ]
}

@test "범위: 한글 경로에 붙은 조사를 떼도 부모 디렉토리로 넓히지 않는다" {
    mkdir -p "$REPO_DIR/docs/회의록"
    printf 'const a = await axios.get("https://api.example.com/a")\n' > "$REPO_DIR/docs/회의록/a.js"
    printf 'const o = await axios.get("https://api.example.com/o")\n' > "$REPO_DIR/docs/other.js"
    _run_all_reviews "high docs/회의록을 봐줘"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm docs
    _gate "git push"
    [ "$status" -eq 2 ]
    grep -q "	docs/회의록/a.js\$" "$REPO_DIR/.git/mangolove/.review-covered"
    ! grep -q "	docs/other.js\$" "$REPO_DIR/.git/mangolove/.review-covered"
}

@test "record: 리뷰 정책에 없는 스킬은 기록하지 않는다 (매 호출의 범위 계산과 해시를 아낀다)" {
    echo changed > "$REPO_DIR/seed.txt"
    printf '%s' "$(_json_skill linear-ticket)" | bash "$GATE" record
    [ ! -f "$REPO_DIR/.git/mangolove/.review-ledger" ]
    [ ! -f "$REPO_DIR/.git/mangolove/.review-covered" ]
}

# ── code-review 가 재현한 결함 ─────────────────────────────────────

@test "해석: 서브셸, 파이프 안의 cd 는 뒤따르는 push 의 디렉토리를 바꾸지 않는다" {
    _commit_external_api
    _gate "(cd $TEST_DIR && ls); git push"
    [ "$status" -eq 2 ]
    _gate "cd $TEST_DIR | cat; git push"
    [ "$status" -eq 2 ]
    _gate "cd $TEST_DIR 2>&1; cd $REPO_DIR; git push"
    [ "$status" -eq 2 ]
}

@test "해석: 명령치환으로 준 브랜치 이름은 현재 브랜치로 보고 판정한다 (감사로 새지 않는다)" {
    _commit_external_api
    _gate 'git push -u origin "$(git branch --show-current)"'
    [ "$status" -eq 2 ]
}

@test "해석: bash -lc, bash -e -o pipefail -c 로 감싼 push 도 판정한다" {
    _commit_external_api
    _gate 'bash -lc "git push origin main"'
    [ "$status" -eq 2 ]
    _gate 'bash -e -o pipefail -c "git push origin main"'
    [ "$status" -eq 2 ]
}

@test "두 트리: ../ 로 짚은 옆 레포도 그 레포에 기록되고 이 트리 기록이 깨지지 않는다" {
    _other_repo
    _commit_external_api
    _commit_external_api_in "$OTHER"
    _run_all_reviews "high $REPO_DIR 와 ../other 의 변경"
    _gate "git push -u origin main"
    [ "$status" -eq 0 ]
    _gate "git -C $OTHER push -u origin main"
    [ "$status" -eq 0 ]
}

@test "두 트리: 루트 아래 중첩된 작업 트리를 짚으면 그 작업 트리에 기록한다 (.claude/worktrees/<ID>)" {
    local wt="$REPO_DIR/.claude/worktrees/WT"
    mkdir -p "$REPO_DIR/.claude/worktrees"
    git -C "$REPO_DIR" worktree add -q -b WT "$wt" main
    _commit_external_api_in "$wt"
    _run_all_reviews "high $wt 의 변경"
    _gate "git -C $wt push -u origin WT"
    [ "$status" -eq 0 ]
}

@test "범위: 한글로만 된 디렉토리 이름을 짚으면 그 디렉토리만 커버한다" {
    mkdir -p "$REPO_DIR/회의록"
    printf 'const a = await axios.get("https://api.example.com/a")\n' > "$REPO_DIR/회의록/a.js"
    printf 'const o = await axios.get("https://api.example.com/o")\n' > "$REPO_DIR/other.js"
    _run_all_reviews "high 회의록"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm meeting
    _gate "git push"
    [ "$status" -eq 2 ]
    grep -q "	회의록/a.js\$" "$REPO_DIR/.git/mangolove/.review-covered"
    ! grep -q "	other.js\$" "$REPO_DIR/.git/mangolove/.review-covered"
}

@test "해석: 입력 끝 표시까지 읽었을 때만 완료 표시를 낸다 (앞 단계가 죽으면 감사로 간다)" {
    run bash -c "source '$GATE'; _push_targets 'git status' /cwd"
    [ -z "$output" ]
    run bash -c "source '$GATE'; _push_targets \"git status
\$PARSER_END\" /cwd"
    [ "$output" = $'!\tEND' ]
}

# ── simplify 재리뷰가 재현한 결함 ─────────────────────────────────

@test "대상 레포: 하위 디렉토리로 cd 해서 올려도 레포 루트 기준으로 판정한다" {
    mkdir -p "$REPO_DIR/sub"
    echo keep > "$REPO_DIR/sub/keep.txt"
    printf 'const a = await axios.get("https://api.example.com/a")\n' > "$REPO_DIR/a.js"
    _run_all_reviews
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm reviewed
    local i
    for i in $(seq 1 11); do echo "export const V$i = $i" > "$REPO_DIR/n$i.js"; done
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm more
    _gate "cd sub && git push"
    [ "$status" -eq 2 ]
}

@test "해석: 파이프라인으로 묶인 복합 명령 안의 cd 는 뒤따르는 push 의 디렉토리를 바꾸지 않는다" {
    _commit_external_api
    _gate "{ cd $TEST_DIR && ls; } 2>&1 | tail -3; git push origin main"
    [ "$status" -eq 2 ]
    _gate "for d in a b; do cd $TEST_DIR && ls; done 2>&1 | tail -3; git push origin main"
    [ "$status" -eq 2 ]
}

@test "해석: 옵션이나 래퍼가 붙은 셸 안의 push 도 판정한다" {
    _commit_external_api
    _gate 'bash --login -c "git push origin main"'
    [ "$status" -eq 2 ]
    _gate 'bash --noprofile --norc -c "git push origin main"'
    [ "$status" -eq 2 ]
    _gate "timeout 60 bash -c \"git push origin \$(git branch --show-current)\""
    [ "$status" -eq 2 ]
}

@test "해석: 명령치환 속 heredoc 으로 넘긴 커밋 메시지의 git push 글자는 명령이 아니다" {
    _commit_external_api
    _gate 'git commit -m "$(cat <<EOF\nfix: 게이트 수정\n\n배포는 git push origin main 으로 한다\nEOF\n)"'
    [ "$status" -eq 0 ]
    ! grep -q '"kind":"fail-open"' "$MANGOLOVE_DIR/efficacy/proj.jsonl" 2>/dev/null
}

# ── 최종 리뷰가 재현한 결함 ───────────────────────────────────────

@test "해석: 한 조각 안에 겹친 복합 명령(do if, then {)의 cd 도 파이프라인이 끝나면 되돌린다" {
    _other_repo
    _commit_external_api
    _gate "for r in a; do if true; then cd $OTHER && git status; fi; done 2>&1 | tail -3; git push origin main"
    [ "$status" -eq 2 ]
    _gate "if true; then { cd $OTHER && git status; }>/dev/null | cat; git push origin main; fi"
    [ "$status" -eq 2 ]
}

@test "대상 레포: 명령 밖에서 정해진 환경변수 경로를 따라간다 (CLAUDE_PROJECT_DIR)" {
    _other_repo
    _commit_external_api_in "$OTHER"
    export CLAUDE_PROJECT_DIR="$OTHER"
    _gate 'cd "$CLAUDE_PROJECT_DIR" && git push origin main'
    [ "$status" -eq 2 ]
}

@test "해석: 명령치환 속 heredoc 본문의 짝 안 맞는 따옴표와 괄호가 커밋을 push 로 만들지 않는다" {
    local cmdf="$TEST_DIR/cmd.txt"
    printf '%s\n' 'git commit -m "$(cat <<EOF' 'fix: 따옴표 하나 " 와 괄호 (x)' 'git push origin main' 'EOF' ')"' '#MANGOLOVE_PARSER_END' > "$cmdf"
    run bash -c "source '$GATE'; _push_targets \"\$(cat '$cmdf')\" /cwd"
    [ "$output" = $'!\tEND' ]
}

@test "범위: 경로 끝을 떼다 . 이나 .. 가 되면 경로로 인정하지 않는다 (다른 브랜치 리뷰가 트리 전체로 바뀌지 않게)" {
    _make_sibling other-x
    mkdir -p "$REPO_DIR/sub"
    printf 'const o = await axios.get("https://api.example.com/o")\n' > "$REPO_DIR/sub/o.js"
    CWD="$REPO_DIR/sub" _run_all_reviews "other-x ..."
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm sub
    _gate "git push"
    [ "$status" -eq 2 ]
}

@test "우회: 하위 디렉토리에서 남긴 1회 우회도 레포 루트에서 판정하는 게이트가 찾는다" {
    mkdir -p "$REPO_DIR/sub"
    _commit_external_api
    run bash -c "cd '$REPO_DIR/sub' && bash '$GATE' skip '근거: 테스트'"
    [ "$status" -eq 0 ]
    [ -f "$REPO_DIR/.mangolove/.review-skip" ]
    run bash -c "printf '%s' '$(CWD="$REPO_DIR/sub" _json_cmd "git push")' | bash '$GATE' pretooluse"
    [ "$status" -eq 0 ]
}
