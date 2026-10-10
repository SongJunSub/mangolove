#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove: Review gate: heredoc 판정
# 게이트의 목적과 회귀 대상 행동은 tests/review-gate.bats 머리말에 있다.
# ─────────────────────────────────────────────

load test_helper
load review_gate_helper

# ── heredoc 오탐 (실사용을 막고 있었다) ────────────────────────
#
# 게이트는 셸을 파싱하지 않고 명령 문자열을 본다. 스크립트를 heredoc 으로 넘기는
# 흔한 패턴에서 본문의 글자가 명령으로 오인돼 무관한 작업이 막혔다.

@test "heredoc: python3 로 넘긴 본문 속 문자열을 명령으로 오인하지 않는다" {
    _commit_external_api
    _gate 'python3 - <<PYEOF\nprint("run git push later")\nPYEOF'
    [ "$status" -eq 0 ]
}

@test "heredoc: cat 으로 파일을 쓰는 본문도 오인하지 않는다" {
    _commit_external_api
    _gate 'cat > doc.md <<MD\n배포는 git push 로 합니다\nMD'
    [ "$status" -eq 0 ]
}

@test "heredoc: 셸이 소비하는 heredoc 의 push 는 여전히 잡는다" {
    # 본문이 데이터가 아니라 실행되는 코드다. 벗기면 진짜 push 가 새어 나간다.
    _commit_external_api
    _gate 'bash <<SH\ngit push origin main\nSH'
    [ "$status" -eq 2 ]
}

@test "heredoc: 본문을 벗겨도 그 뒤의 진짜 push 는 잡는다" {
    _commit_external_api
    _gate 'cat > doc.md <<MD\n배포는 git push 로 합니다\nMD\ngit push origin main'
    [ "$status" -eq 2 ]
}

@test "우회: mangolove review skip 이 근거와 함께 마커를 남긴다" {
    # 안내문이 시키는 우회를 에이전트가 실행하지 못하면 차단이 전부 사용자 호출이 된다.
    run bash -c "cd '$REPO_DIR' && bash '$GATE' skip '리뷰 3종 실행, 델타는 테스트 파일뿐'"
    [ "$status" -eq 0 ]
    grep -q '델타는 테스트' "$REPO_DIR/.mangolove/.review-skip"
    # 그 우회가 실제로 다음 1회를 통과시킨다
    _commit_external_api
    _gate "git push"
    [ "$status" -eq 0 ]
}

@test "우회: 근거 없이 부르면 거부한다 (왜 우회했는지가 기록의 전부다)" {
    run bash -c "cd '$REPO_DIR' && bash '$GATE' skip"
    [ "$status" -eq 2 ]
}

@test "차단 안내: 스킬 미실행이면 묻지 말고 실행하라고 한다" {
    _commit_external_api
    _gate "git push"
    [ "$status" -eq 2 ]
    [[ "$output" == *"묻지 마세요"* ]]
}

@test "차단 안내: 리뷰 뒤 델타면 스스로 우회하는 길을 알려준다" {
    printf 'const a = await axios.get("https://api.example.com/a")\n' > "$REPO_DIR/a.js"
    _run_all_reviews
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm reviewed
    local i
    for i in $(seq 1 11); do echo "export const V$i = $i" > "$REPO_DIR/n$i.js"; done
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm more
    _gate "git push"
    [ "$status" -eq 2 ]
    [[ "$output" == *"review skip"* ]]
}


# ── heredoc 판정의 두 결함 (내가 오늘 만든 것) ─────────────────

@test "보안: 따옴표 안의 가짜 <<EOF 로 뒤 명령을 숨길 수 없다" {
    # 텍스트만 보면 echo "see <<EOF" 의 <<EOF 를 진짜 리다이렉션으로 오인하고, 닫는 마커가
    # 영영 안 나오므로 그 뒤 명령이 통째로 사라진다. 무해한 한 줄로 게이트 전체가 침묵했다.
    # 공격은 **데이터 싱크 명령**으로 해야 성립한다. echo 는 싱크 목록에 없어 allowlist 가
    # 먼저 막아주므로, 그걸로 시험하면 따옴표 추적이 없어도 통과한다(이빨 없는 테스트였다).
    # 파서를 직접 부른다: 페이로드에 따옴표를 넣으면 bats 헬퍼의 인용이 먼저 깨진다.
    run bash -c 'source "'"$GATE"'"
        printf "%s" "$(_push_targets "python3 -c \"s = 12 <<EOF\"
git push origin main" "$PWD")"'
    [[ "$output" == *"	main"* ]]
    run bash -c 'source "'"$GATE"'"
        printf "%s" "$(_push_targets "cat report.txt   # see '"'"'<<EOF'"'"' below
git push origin main" "$PWD")"'
    [[ "$output" == *"	main"* ]]
}

@test "heredoc: 진짜 데이터 싱크의 본문은 여전히 벗긴다 (원래 오탐)" {
    run bash -c 'source "'"$GATE"'"
        printf "%s" "$(_push_targets "cat > d.md <<MD
배포는 git push 로 한다
MD" "$PWD")"'
    [ -z "$output" ]
}

@test "heredoc: 본문을 실행하는 소비자는 벗기지 않는다 (데이터 싱크만 벗긴다)" {
    _commit_external_api
    _gate 'psql db <<SQL\nselect 1;\nSQL\ngit push origin main'
    [ "$status" -eq 2 ]
}

@test "하위 디렉토리에서 세션이 돌아도 커버리지가 맞는다" {
    # git 이 주는 경로는 레포 루트 기준인데 [ -f ] 와 hash-object 는 cwd 기준이라,
    # 하위에서 돌면 전부 _absent 로 기록돼 해소 불가능한 차단 루프가 됐다.
    mkdir -p "$REPO_DIR/sub"
    printf 'const a = await axios.get("https://api.example.com/a")\n' > "$REPO_DIR/sub/api.js"
    CWD="$REPO_DIR/sub" _run_all_reviews
    grep -q "	sub/api.js\$" "$REPO_DIR/.git/mangolove/.review-covered"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm sub
    run bash -c "cd '$REPO_DIR/sub' && printf '%s' '$(_json_cmd "git push")' | bash '$GATE' pretooluse"
    [ "$status" -eq 0 ]
}

@test "record: 비-git 디렉토리에서도 조용히 통과한다 (항상 exit 0 계약)" {
    local nogit="$TEST_DIR/nogit2"; mkdir -p "$nogit"
    run bash -c "cd '$nogit' && printf '{\"tool_name\":\"Skill\",\"cwd\":\"$nogit\",\"tool_input\":{\"skill\":\"simplify\"}}' | bash '$GATE' record"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "보안: skip 이 심볼릭 링크를 따라 레포 밖에 쓰지 않는다" {
    # 워킹트리에 남는 유일한 상태 파일이고, 이 명령은 권한까지 자동 허용돼 있다.
    local victim="$TEST_DIR/victim.txt"
    echo ORIGINAL > "$victim"
    mkdir -p "$REPO_DIR/.mangolove"
    ln -s "$victim" "$REPO_DIR/.mangolove/.review-skip"
    run bash -c "cd '$REPO_DIR' && bash '$GATE' skip 'hostile'"
    [ "$(cat "$victim")" = "ORIGINAL" ]
}

@test "pre-push: 버전 스큐 검사가 훅을 통째로 무력화하지 않는다" {
    # set -o pipefail 아래서 파이프라인 종료코드가 게이트의 usage exit 2 가 되어
    # grep 결과와 무관하게 항상 우회됐다. 즉 훅 전체가 no-op 이었다.
    grep -q '_probe=' "$BATS_TEST_DIRNAME/../.githooks/pre-push"
    ! grep -q "grep -q 'prepush' || exit 0" "$BATS_TEST_DIRNAME/../.githooks/pre-push"
}

@test "우회: 앞선 게이트가 승인한 push 를 pre-push 가 이어받는다" {
    # 게이트 둘이 직렬로 걸린다. 앞쪽이 마커를 소비하면 뒤쪽이 근거 없이 다시 막아,
    # 한 번 공유하는 데 우회가 두 번 든다.
    _commit_external_api
    mkdir -p "$REPO_DIR/.mangolove"
    printf '근거\n' > "$REPO_DIR/.mangolove/.review-skip"
    _gate "git push"
    [ "$status" -eq 0 ]
    local sha base
    sha=$(git -C "$REPO_DIR" rev-parse HEAD); base=$(git -C "$REPO_DIR" rev-parse origin/main)
    run bash -c "cd '$REPO_DIR' && printf 'refs/heads/main %s refs/heads/main %s\n' '$sha' '$base' | bash '$GATE' prepush origin /tmp/f.git"
    [ "$status" -eq 0 ]
    run bash -c "cd '$REPO_DIR' && printf 'refs/heads/main %s refs/heads/main %s\n' '$sha' '$base' | bash '$GATE' prepush origin /tmp/f.git"
    [ "$status" -eq 1 ]
}

@test "우회: 커밋을 끼워 sha 가 바뀌어도 이어받는다" {
    # PreToolUse 는 **명령 실행 전에** 발화한다. `git add && git commit && git push` 한 줄에서
    # 그때의 HEAD 는 실제 push 되는 sha 와 다르다. sha 를 식별자로 쓰면 여기서 깨진다.
    _commit_external_api
    mkdir -p "$REPO_DIR/.mangolove"
    printf '근거\n' > "$REPO_DIR/.mangolove/.review-skip"
    _gate "git push"
    [ "$status" -eq 0 ]
    echo more > "$REPO_DIR/other.txt"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm other
    local sha base
    sha=$(git -C "$REPO_DIR" rev-parse HEAD); base=$(git -C "$REPO_DIR" rev-parse origin/main)
    run bash -c "cd '$REPO_DIR' && printf 'refs/heads/main %s refs/heads/main %s\n' '$sha' '$base' | bash '$GATE' prepush origin /tmp/f.git"
    [ "$status" -eq 0 ]
}

@test "우회: 오래된 이어받기 표시는 다음 push 를 통과시키지 않는다" {
    # 표시가 남으면 1회용이 무제한 무료 통과가 된다. 창은 두 훅이 이어 도는 간격만 덮는다.
    _commit_external_api
    mkdir -p "$REPO_DIR/.mangolove"
    printf '근거\n' > "$REPO_DIR/.mangolove/.review-skip"
    _gate "git push"
    [ "$status" -eq 0 ]
    echo "$(( $(date +%s) - 300 ))" > "$REPO_DIR/.git/mangolove/.review-skip.used"
    local sha base
    sha=$(git -C "$REPO_DIR" rev-parse HEAD); base=$(git -C "$REPO_DIR" rev-parse origin/main)
    run bash -c "cd '$REPO_DIR' && printf 'refs/heads/main %s refs/heads/main %s\n' '$sha' '$base' | bash '$GATE' prepush origin /tmp/f.git"
    [ "$status" -eq 1 ]
}

@test "우회: 터미널 경로의 우회는 이어받기 표시를 남기지 않는다" {
    # 남기면 그 다음 push 까지 무료로 통과한다. 소비할 하위 게이트가 없다.
    _commit_external_api
    mkdir -p "$REPO_DIR/.mangolove"
    printf '근거\n' > "$REPO_DIR/.mangolove/.review-skip"
    local sha base
    sha=$(git -C "$REPO_DIR" rev-parse HEAD); base=$(git -C "$REPO_DIR" rev-parse origin/main)
    run bash -c "cd '$REPO_DIR' && printf 'refs/heads/main %s refs/heads/main %s\n' '$sha' '$base' | bash '$GATE' prepush origin /tmp/f.git"
    [ "$status" -eq 0 ]
    [ ! -f "$REPO_DIR/.git/mangolove/.review-skip.used" ]
}

@test "보안: 무력화된 pre-push 훅이 있어도 우회는 1회로 끝난다" {
    # "하위 게이트가 있으니 그쪽이 소비하겠지"로 두면, 훅 파일이 있기만 하고 게이트를
    # 부르지 않는 경우(no-op 훅, husky 등 남의 훅) 마커가 영영 안 지워져 상시 우회가 된다.
    _commit_external_api
    mkdir -p "$REPO_DIR/.githooks"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$REPO_DIR/.githooks/pre-push"
    chmod +x "$REPO_DIR/.githooks/pre-push"
    git -C "$REPO_DIR" config core.hooksPath .githooks
    mkdir -p "$REPO_DIR/.mangolove"
    printf '근거\n' > "$REPO_DIR/.mangolove/.review-skip"
    _gate "git push"
    [ "$status" -eq 0 ]
    [ ! -f "$REPO_DIR/.mangolove/.review-skip" ]
}

@test "보안: pre-push 자리가 디렉토리여도 우회는 1회로 끝난다" {
    # 디렉토리는 기본 권한에 실행 비트가 있어 [ -x ] 가 참이 된다.
    _commit_external_api
    mkdir -p "$REPO_DIR/.githooks/pre-push"
    git -C "$REPO_DIR" config core.hooksPath .githooks
    mkdir -p "$REPO_DIR/.mangolove"
    printf '근거\n' > "$REPO_DIR/.mangolove/.review-skip"
    _gate "git push"
    [ "$status" -eq 0 ]
    [ ! -f "$REPO_DIR/.mangolove/.review-skip" ]
}

@test "우회: gh pr create 는 1회 우회 마커를 소비하지 않는다 (다음 push 가 소비한다)" {
    _commit_external_api
    mkdir -p "$REPO_DIR/.mangolove"
    printf '근거\n' > "$REPO_DIR/.mangolove/.review-skip"
    _gate "gh pr create --fill"
    [ "$status" -eq 0 ]
    [ -f "$REPO_DIR/.mangolove/.review-skip" ]
    _gate "git push"
    [ "$status" -eq 0 ]
    [ ! -f "$REPO_DIR/.mangolove/.review-skip" ]
}
