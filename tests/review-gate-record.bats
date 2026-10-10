#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove: Review gate: 우회, pre-push 훅, record, status
# 게이트의 목적과 회귀 대상 행동은 tests/review-gate.bats 머리말에 있다.
# ─────────────────────────────────────────────

load test_helper
load review_gate_helper

# ── fail-open: 게이트가 작업을 인질로 잡지 않는다 ──────────────

@test "gate: 비-git 디렉토리에서는 fail-open" {
    local nogit="$TEST_DIR/nogit"; mkdir -p "$nogit"
    run bash -c "printf '{\"tool_name\":\"Bash\",\"cwd\":\"$nogit\",\"tool_input\":{\"command\":\"git push\"}}' | bash '$GATE' pretooluse"
    [ "$status" -eq 0 ]
}

@test "gate: upstream 도 origin 도 없으면 범위를 못 정하므로 fail-open" {
    local solo="$TEST_DIR/solo"; mkdir -p "$solo"
    git -C "$solo" init -q -b main
    git -C "$solo" config user.email t@example.com
    git -C "$solo" config user.name t
    printf 'const r = await axios.get("https://api.example.com/v1")\n' > "$solo/client.js"
    git -C "$solo" add -A
    git -C "$solo" -c user.email=t@t -c user.name=t commit -qm x
    run bash -c "printf '{\"tool_name\":\"Bash\",\"cwd\":\"$solo\",\"tool_input\":{\"command\":\"git push\"}}' | bash '$GATE' pretooluse"
    [ "$status" -eq 0 ]
}

# ── 우회 (감사됨) ───────────────────────────────────────────────

@test "gate: MANGOLOVE_SKIP_REVIEW=1 은 통과하되 감사 문구를 남긴다" {
    _commit_external_api
    run bash -c "printf '%s' '$(_json_cmd "git push")' | MANGOLOVE_SKIP_REVIEW=1 bash '$GATE' pretooluse"
    [ "$status" -eq 0 ]
    [[ "$output" == *"감사 대상"* ]]
}

@test "gate: .mangolove/.review-skip 은 1회용 우회이고 소비된다" {
    _commit_external_api
    mkdir -p "$REPO_DIR/.mangolove"
    touch "$REPO_DIR/.mangolove/.review-skip"
    _gate "git push"
    [ "$status" -eq 0 ]
    [ ! -f "$REPO_DIR/.mangolove/.review-skip" ]
    _gate "git push"
    [ "$status" -eq 2 ]
}

# ── pre-push 훅 경로 (터미널 직접 push) ─────────────────────────

@test "prepush: 터미널 push 도 같은 규칙으로 막는다 (exit 1)" {
    _commit_external_api
    run bash -c "cd '$REPO_DIR' && bash '$GATE' prepush </dev/null"
    [ "$status" -eq 1 ]
    [[ "$output" == *"push 차단"* ]]
}

@test "prepush: 리뷰가 끝나 있으면 통과한다 (세션 인자 없이도 원장을 인정)" {
    _commit_external_api
    _run_all_reviews
    run bash -c "cd '$REPO_DIR' && bash '$GATE' prepush </dev/null"
    [ "$status" -eq 0 ]
}

@test "prepush: .githooks/pre-push 는 게이트가 없는 머신에서 push 를 막지 않는다" {
    run bash -c "MANGOLOVE_DIR='$TEST_DIR/nonexistent' bash '$BATS_TEST_DIRNAME/../.githooks/pre-push' origin url </dev/null"
    [ "$status" -eq 0 ]
}

@test "prepush: MANGOLOVE_REVIEW_GATE=off 면 훅이 즉시 통과한다" {
    run bash -c "MANGOLOVE_REVIEW_GATE=off bash '$BATS_TEST_DIRNAME/../.githooks/pre-push' origin url </dev/null"
    [ "$status" -eq 0 ]
}

# ── record: 원장과 커버리지 기록 ────────────────────────────────

@test "record: skill_name 이 없는 페이로드는 조용히 통과 (훅이 세션을 깨지 않는다)" {
    run bash -c "printf '{\"tool_name\":\"Skill\",\"cwd\":\"$REPO_DIR\",\"tool_input\":{}}' | bash '$GATE' record"
    [ "$status" -eq 0 ]
}

@test "record: 같은 스킬을 여러 번 호출해도 원장에 한 줄만 남는다" {
    printf '%s' "$(_json_skill simplify)" | bash "$GATE" record
    printf '%s' "$(_json_skill simplify)" | bash "$GATE" record
    printf '%s' "$(_json_skill "code-review:simplify")" | bash "$GATE" record
    [ "$(grep -cx simplify "$REPO_DIR/.git/mangolove/.review-ledger")" -eq 1 ]
}

@test "record: tool_input 의 skill 과 skill_name 을 모두 받는다 (문서와 런타임이 다르다)" {
    # 경계면 교차검증 회귀: 한쪽 이름만 받으면 원장이 영영 비어 Medium 이상 push 가
    # 전부 막힌다. 실측한 런타임 필드는 skill, 훅 문서가 적은 것은 skill_name 이다.
    printf '%s' "$(_json_skill simplify)"        | bash "$GATE" record
    printf '%s' "$(_json_skill_alt code-review)" | bash "$GATE" record
    grep -qx simplify    "$REPO_DIR/.git/mangolove/.review-ledger"
    grep -qx code-review "$REPO_DIR/.git/mangolove/.review-ledger"
}

@test "record: 리뷰가 본 내용을 커버리지 파일에 blob 해시로 남긴다" {
    echo changed > "$REPO_DIR/seed.txt"
    printf '%s' "$(_json_skill simplify)" | bash "$GATE" record
    [ -f "$REPO_DIR/.git/mangolove/.review-covered" ]
    local h; h=$(git -C "$REPO_DIR" hash-object "$REPO_DIR/seed.txt")
    grep -qF "$h" "$REPO_DIR/.git/mangolove/.review-covered"
}

@test "record: 커버리지는 중복 없이 집합으로 유지된다" {
    echo changed > "$REPO_DIR/seed.txt"
    printf '%s' "$(_json_skill simplify)"    | bash "$GATE" record
    printf '%s' "$(_json_skill code-review)" | bash "$GATE" record
    local cov="$REPO_DIR/.git/mangolove/.review-covered"
    [ "$(sort -u "$cov" | wc -l | tr -d ' ')" -eq "$(wc -l < "$cov" | tr -d ' ')" ]
}

@test "record: 원장 디렉토리를 만들 때 .mangolove/.gitignore 를 심는다 (레포 오염 방지)" {
    # 게이트를 켠 모든 레포에서 사용자가 손으로 .gitignore 를 고치게 만들지 않는다.
    # 단, .mangolove/ 를 통째로 무시하면 안 된다: .mangolove/hooks/ 는 버전관리 감사 대상이다.
    printf '%s' "$(_json_skill simplify)" | bash "$GATE" record
    [ -f "$REPO_DIR/.mangolove/.gitignore" ]
    grep -qx '.review-skip' "$REPO_DIR/.mangolove/.gitignore"
    grep -qx 'dod.sh' "$REPO_DIR/.mangolove/.gitignore"
    # 원장과 커버리지는 이제 .git/ 아래라 무시 목록에 없어야 한다(브랜치가 실어 올 수 없다).
    run grep -qx '.review-ledger' "$REPO_DIR/.mangolove/.gitignore"
    [ "$status" -eq 1 ]
    # 자기 자신도 무시해야 사용자 레포에 요청하지 않은 파일이 생기지 않는다.
    grep -qx '.gitignore' "$REPO_DIR/.mangolove/.gitignore"
    # 통째 무시(*)는 안 된다: .mangolove/hooks/ 는 버전관리 감사 대상이다.
    run grep -qx '\*' "$REPO_DIR/.mangolove/.gitignore"
    [ "$status" -eq 1 ]
    [ -z "$(git -C "$REPO_DIR" status --porcelain -- .mangolove)" ]
}

# ── status ─────────────────────────────────────────────────────

@test "status: 계산된 트랙과 부족분을 사람이 읽을 수 있게 보고한다" {
    _commit_external_api
    run bash -c "cd '$REPO_DIR' && bash '$GATE' status"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Medium"* ]]
    [[ "$output" == *"BLOCK"* ]]
}

@test "status: 리뷰가 끝나 있으면 PASS 로 보고한다" {
    _commit_external_api
    _run_all_reviews
    run bash -c "cd '$REPO_DIR' && bash '$GATE' status"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

# ── 리뷰 지적 반영 (fork 축소 + fail-open 감사) ───────────────

@test "fail-open: 판정 범위를 못 정하면 통과시키되 효능 원장에 기록한다" {
    # 의도적 우회만 감사하고 이쪽을 침묵시키면, 가장 감사가 필요한 경우
    # ("게이트가 조용히 아무 일도 하지 않았다")가 "리뷰가 필요 없었다"와 구별되지 않는다.
    local solo="$TEST_DIR/solo"; mkdir -p "$solo"
    git -C "$solo" init -q -b main
    git -C "$solo" config user.email t@example.com
    git -C "$solo" config user.name t
    printf 'const r = await axios.get("https://api.example.com/v1")\n' > "$solo/client.js"
    git -C "$solo" add -A
    git -C "$solo" commit -qm x
    run bash -c "printf '{\"tool_name\":\"Bash\",\"session_id\":\"s1\",\"cwd\":\"$solo\",\"tool_input\":{\"command\":\"git push\"}}' | bash '$GATE' pretooluse"
    [ "$status" -eq 0 ]
    [[ "$output" == *"fail-open"* ]]
    grep -q '"type":"skip","phase":"review","kind":"fail-open"' "$MANGOLOVE_DIR/efficacy/solo.jsonl"
}

@test "커버리지: 공백이 있는 경로도 정확히 covered 로 잡힌다" {
    # 해시와 경로를 한 번에 붙이는 경로(paste)가 어긋나면 조용한 오통과가 된다.
    printf 'const a = await axios.get("https://api.example.com/a")\n' > "$REPO_DIR/a file.js"
    printf 'const b = await axios.get("https://api.example.com/b")\n' > "$REPO_DIR/b.js"
    _run_all_reviews
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm "spaced"
    _gate "git push"
    [ "$status" -eq 0 ]
}

@test "커버리지: 사라진 파일은 _absent 로 기록돼 삭제 커밋이 covered 로 잡힌다" {
    git -C "$REPO_DIR" rm -q seed.txt
    printf 'const a = await axios.get("https://api.example.com/a")\n' > "$REPO_DIR/a.js"
    _run_all_reviews
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm "delete + add"
    _gate "git push"
    [ "$status" -eq 0 ]
}

@test "커버리지: 파일 형식은 <스킬>탭<blob>탭<경로> 다" {
    echo changed > "$REPO_DIR/seed.txt"
    printf '%s' "$(_json_skill simplify)" | bash "$GATE" record
    local h; h=$(git -C "$REPO_DIR" hash-object "$REPO_DIR/seed.txt")
    grep -qxF "simplify	$h	seed.txt" "$REPO_DIR/.git/mangolove/.review-covered"
}
