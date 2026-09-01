#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove: Review gate (트랙별 필수 리뷰의 결정적 강제)
#
# 회귀 대상 행동: "Medium 트랙인데 /simplify 와 코드 리뷰를 돌리지 않았습니다,
# 필요하시면 지금 돌리겠습니다": 트랙을 선언하고 절차를 생략한 뒤 사후에 고백하는 것.
# 이 게이트는 커밋 경계에서 코드가 트랙을 계산해 그 답변 자체가 불가능하게 만든다.
# ─────────────────────────────────────────────

load test_helper

setup() {
    setup_test_env
    GATE="$MANGOLOVE_DIR/lib/review-gate.sh"
    REPO_DIR="$TEST_DIR/proj"
    mkdir -p "$REPO_DIR"
    git -C "$REPO_DIR" init -q
    git -C "$REPO_DIR" config user.email t@example.com
    git -C "$REPO_DIR" config user.name t
    echo seed > "$REPO_DIR/seed.txt"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm seed
}

teardown() {
    teardown_test_env
}

# PreToolUse(Bash) JSON: 명령 + cwd + session_id
_json_cmd() {
    local c="${1//\"/\\\"}"
    printf '{"tool_name":"Bash","session_id":"%s","cwd":"%s","tool_input":{"command":"%s"}}' \
        "${SESSION:-s1}" "$REPO_DIR" "$c"
}

# PostToolUse(Skill) JSON: 실행된 스킬 이름 + cwd
# 필드 이름은 실제 세션 트랜스크립트에서 실측한 것이다: {"skill":"simplify"}.
_json_skill() {
    printf '{"tool_name":"Skill","session_id":"%s","cwd":"%s","tool_input":{"skill":"%s"}}' \
        "${SESSION:-s1}" "$REPO_DIR" "$1"
}

# 훅 문서가 적고 있는 대체 필드명. 런타임이 어느 쪽을 보내도 원장이 채워져야 한다.
_json_skill_alt() {
    printf '{"tool_name":"Skill","session_id":"%s","cwd":"%s","tool_input":{"skill_name":"%s"}}' \
        "${SESSION:-s1}" "$REPO_DIR" "$1"
}

# Medium 이상이 되도록 파일 N개를 스테이징한다 (파일 6개 = +5, 그 위에 외부 API 신호로 승격).
_stage_files() {
    local n="$1" i
    for i in $(seq 1 "$n"); do echo "export const V$i = $i" > "$REPO_DIR/f$i.js"; done
    git -C "$REPO_DIR" add -A
}

_stage_external_api() {
    printf 'const r = await axios.get("https://api.example.com/v1")\n' > "$REPO_DIR/client.js"
    git -C "$REPO_DIR" add -A
}

# ── 정책 표 (required_skills): strict.md 의 트랙별 리뷰 표와 단일 출처를 공유한다 ──

@test "policy: Trivial/Small 은 아무 리뷰도 요구하지 않는다 (과대 판정 방지)" {
    run bash "$GATE" required Trivial false false false
    [ "$status" -eq 0 ]
    [ -z "$(echo "$output" | tr -d '[:space:]')" ]
    run bash "$GATE" required Small false false false
    [ -z "$(echo "$output" | tr -d '[:space:]')" ]
}

@test "policy: Medium 은 simplify + code-review" {
    run bash "$GATE" required Medium false false false
    [ "$output" = "simplify code-review" ]
}

@test "policy: Large 는 security-review 까지" {
    run bash "$GATE" required Large false false false
    [ "$output" = "simplify code-review security-review" ]
}

@test "policy: DB/인증/외부API 신호가 있으면 트랙과 무관하게 security-review 추가" {
    run bash "$GATE" required Medium true false false
    [[ "$output" == *"security-review"* ]]
    run bash "$GATE" required Medium false false true
    [[ "$output" == *"security-review"* ]]
}

# ── 커밋 경계 게이트 ────────────────────────────────────────────

@test "gate: git commit 이 아닌 Bash 는 통과 (게이트가 일반 작업을 막지 않는다)" {
    _stage_external_api
    run bash -c "cd '$REPO_DIR' && printf '%s' '$(_json_cmd "git log --grep=commit")' | bash '$GATE' pretooluse"
    [ "$status" -eq 0 ]
}

@test "gate: Trivial 변경 커밋은 리뷰 없이 통과 (사소한 작업에 절차를 씌우지 않는다)" {
    echo "one line" > "$REPO_DIR/a.txt"
    git -C "$REPO_DIR" add -A
    run bash -c "printf '%s' '$(_json_cmd "git commit -m x")' | bash '$GATE' pretooluse"
    [ "$status" -eq 0 ]
}

@test "gate: Medium 변경인데 리뷰 미실행이면 커밋 차단(exit 2)" {
    _stage_external_api
    run bash -c "printf '%s' '$(_json_cmd "git commit -m x")' | bash '$GATE' pretooluse"
    [ "$status" -eq 2 ]
    [[ "$output" == *"커밋 차단"* ]]
    [[ "$output" == *"simplify"* ]]
    [[ "$output" == *"code-review"* ]]
}

@test "gate: 원장에 필수 스킬이 기록돼 있으면 통과한다" {
    _stage_external_api
    printf '%s' "$(_json_skill simplify)"    | bash "$GATE" record
    printf '%s' "$(_json_skill code-review)" | bash "$GATE" record
    printf '%s' "$(_json_skill security-review)" | bash "$GATE" record
    [ -f "$REPO_DIR/.mangolove/.review-ledger" ]
    run bash -c "printf '%s' '$(_json_cmd "git commit -m x")' | bash '$GATE' pretooluse"
    [ "$status" -eq 0 ]
}

@test "gate: 통과 후 커밋이 실패해 재시도해도 다시 막지 않는다 (원장을 미리 소비하지 않는다)" {
    # 같은 PreToolUse 목록의 시크릿 게이트가 커밋을 막으면 이 훅은 이미 통과한 뒤다.
    # 통과 시점에 원장을 지우면, 시크릿을 고치고 재시도할 때 이미 한 리뷰를 또 요구하게 된다.
    _stage_external_api
    printf '%s' "$(_json_skill simplify)"        | bash "$GATE" record
    printf '%s' "$(_json_skill code-review)"     | bash "$GATE" record
    printf '%s' "$(_json_skill security-review)" | bash "$GATE" record
    run bash -c "printf '%s' '$(_json_cmd "git commit -m x")' | bash '$GATE' pretooluse"
    [ "$status" -eq 0 ]
    # 커밋은 실패했다고 치고(HEAD 불변) 재시도
    run bash -c "printf '%s' '$(_json_cmd "git commit -m x")' | bash '$GATE' pretooluse"
    [ "$status" -eq 0 ]
}

@test "gate: 커밋이 성공해 HEAD 가 움직이면 원장은 낡은 것이 되어 다음 커밋에 리뷰를 다시 요구한다" {
    _stage_external_api
    printf '%s' "$(_json_skill simplify)"        | bash "$GATE" record
    printf '%s' "$(_json_skill code-review)"     | bash "$GATE" record
    printf '%s' "$(_json_skill security-review)" | bash "$GATE" record
    run bash -c "printf '%s' '$(_json_cmd "git commit -m x")' | bash '$GATE' pretooluse"
    [ "$status" -eq 0 ]
    git -C "$REPO_DIR" commit -qm "actually committed"
    # 새 Medium 변경 + HEAD 이동 → 원장 무효
    printf 'const r2 = await axios.post("https://api.example.com/v2", {})\n' > "$REPO_DIR/client2.js"
    git -C "$REPO_DIR" add -A
    run bash -c "printf '%s' '$(_json_cmd "git commit -m y")' | bash '$GATE' pretooluse"
    [ "$status" -eq 2 ]
    [ ! -f "$REPO_DIR/.mangolove/.review-ledger" ]
}

@test "gate: 플러그인 네임스페이스(code-review:code-review)도 같은 스킬로 인정" {
    _stage_external_api
    printf '%s' "$(_json_skill simplify)" | bash "$GATE" record
    printf '%s' "$(_json_skill "code-review:code-review")" | bash "$GATE" record
    printf '%s' "$(_json_skill "security:security-review")" | bash "$GATE" record
    run bash -c "printf '%s' '$(_json_cmd "git commit -m x")' | bash '$GATE' pretooluse"
    [ "$status" -eq 0 ]
}

@test "gate: 일부만 실행하면 부족분만 지목하며 차단" {
    _stage_external_api
    printf '%s' "$(_json_skill simplify)" | bash "$GATE" record
    run bash -c "printf '%s' '$(_json_cmd "git commit -m x")' | bash '$GATE' pretooluse"
    [ "$status" -eq 2 ]
    [[ "$output" == *"code-review"* ]]
}

@test "gate: MANGOLOVE_SKIP_REVIEW=1 은 통과하되 감사 문구를 남긴다" {
    _stage_external_api
    run bash -c "printf '%s' '$(_json_cmd "git commit -m x")' | MANGOLOVE_SKIP_REVIEW=1 bash '$GATE' pretooluse"
    [ "$status" -eq 0 ]
    [[ "$output" == *"감사 대상"* ]]
}

@test "gate: 비-git 디렉토리에서는 fail-open (게이트가 작업을 인질로 잡지 않는다)" {
    local nogit="$TEST_DIR/nogit"; mkdir -p "$nogit"
    run bash -c "printf '{\"tool_name\":\"Bash\",\"cwd\":\"$nogit\",\"tool_input\":{\"command\":\"git commit -m x\"}}' | bash '$GATE' pretooluse"
    [ "$status" -eq 0 ]
}

@test "gate: commit -a 는 판정 범위를 워킹트리로 넓힌다 (스테이징 안 된 변경도 셈)" {
    # 워킹트리에만 외부 API 호출을 만들고 스테이징하지 않는다.
    _stage_external_api
    git -C "$REPO_DIR" commit -qm base
    printf 'const r2 = await axios.post("https://api.example.com/v2", {})\n' >> "$REPO_DIR/client.js"
    # --staged 로는 아무 것도 안 잡히지만 commit -a 는 이 변경을 담는다.
    run bash -c "printf '%s' '$(_json_cmd "git commit -am x")' | bash '$GATE' pretooluse"
    [ "$status" -eq 2 ]
}

@test "record: skill_name 이 없는 페이로드는 조용히 통과 (훅이 세션을 깨지 않는다)" {
    run bash -c "printf '{\"tool_name\":\"Skill\",\"cwd\":\"$REPO_DIR\",\"tool_input\":{}}' | bash '$GATE' record"
    [ "$status" -eq 0 ]
}

@test "status: 계산된 트랙과 부족분을 사람이 읽을 수 있게 보고한다" {
    _stage_external_api
    run bash -c "cd '$REPO_DIR' && bash '$GATE' status --staged"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Medium"* ]]
    [[ "$output" == *"BLOCK"* ]]
}

@test "gate: 원장 디렉토리를 만들 때 .mangolove/.gitignore 를 심는다 (레포 오염 방지)" {
    # 게이트를 켠 모든 레포에서 사용자가 손으로 .gitignore 를 고치게 만들지 않는다.
    # 단, .mangolove/ 를 통째로 무시하면 안 된다: .mangolove/hooks/ 는 버전관리 감사 대상이다.
    printf '%s' "$(_json_skill simplify)" | bash "$GATE" record
    [ -f "$REPO_DIR/.mangolove/.gitignore" ]
    grep -qx '.review-ledger' "$REPO_DIR/.mangolove/.gitignore"
    grep -qx 'dod.sh' "$REPO_DIR/.mangolove/.gitignore"
    # 자기 자신도 무시해야 사용자 레포에 요청하지 않은 파일이 생기지 않는다.
    grep -qx '.gitignore' "$REPO_DIR/.mangolove/.gitignore"
    # 통째 무시(*)는 안 된다: .mangolove/hooks/ 는 버전관리 감사 대상이다.
    ! grep -qx '\*' "$REPO_DIR/.mangolove/.gitignore"
    [ -z "$(git -C "$REPO_DIR" status --porcelain -- .mangolove)" ]
}

@test "record: 같은 스킬을 여러 번 호출해도 원장에 한 줄만 남는다" {
    printf '%s' "$(_json_skill simplify)" | bash "$GATE" record
    printf '%s' "$(_json_skill simplify)" | bash "$GATE" record
    printf '%s' "$(_json_skill "code-review:simplify")" | bash "$GATE" record
    [ "$(grep -cx simplify "$REPO_DIR/.mangolove/.review-ledger")" -eq 1 ]
}

@test "record: tool_input 의 skill 과 skill_name 을 모두 받는다 (문서와 런타임이 다르다)" {
    # 경계면 교차검증 회귀: 한쪽 이름만 받으면 원장이 영영 비어 Medium 이상 커밋이
    # 전부 막힌다. 실측한 런타임 필드는 skill, 훅 문서가 적은 것은 skill_name 이다.
    printf '%s' "$(_json_skill simplify)"        | bash "$GATE" record
    printf '%s' "$(_json_skill_alt code-review)" | bash "$GATE" record
    grep -qx simplify    "$REPO_DIR/.mangolove/.review-ledger"
    grep -qx code-review "$REPO_DIR/.mangolove/.review-ledger"
}

# ── 코드 리뷰에서 나온 회귀들 ──────────────────────────────────

@test "gate: 멀티라인 명령의 git commit 도 잡는다 (JSON 의 \\n 이 단어 경계를 지운다)" {
    # command 는 JSON 문자열이라 개행이 역슬래시+n 두 글자로 온다. 되돌리지 않으면
    # 둘째 줄 git 앞 글자가 'n'(영숫자)이라 경계에 안 걸려 명령 전체가 게이트를 빠져나간다.
    _stage_external_api
    # JSON 안에서의 개행은 역슬래시+n 두 글자다: 런타임이 실제로 보내는 형태 그대로 쓴다.
    run bash -c "printf '%s' '$(_json_cmd 'git add -A\ngit commit -m x')' | bash '$GATE' pretooluse"
    [ "$status" -eq 2 ]
}

@test "gate: 여러 줄이어도 커밋이 없으면 통과한다 (오탐 방지)" {
    _stage_external_api
    run bash -c "printf '%s' '$(_json_cmd 'git log --grep=commit\necho done')' | bash '$GATE' pretooluse"
    [ "$status" -eq 0 ]
}

@test "gate: -a 가 commit 바로 뒤가 아니어도 워킹트리로 넓힌다" {
    _stage_external_api
    git -C "$REPO_DIR" commit -qm base
    printf 'const r2 = await axios.post("https://api.example.com/v2", {})\n' >> "$REPO_DIR/client.js"
    run bash -c "printf '%s' '$(_json_cmd "git commit -m msg -a")' | bash '$GATE' pretooluse"
    [ "$status" -eq 2 ]
}

@test "gate: 다른 세션의 원장은 오늘의 커밋을 통과시키지 않는다" {
    # 원장은 파일이라 세션을 넘어 남는다. HEAD 만으로 무효화하면 어제 돌린 리뷰가
    # 오늘의 첫 커밋을 통과시킨다. 차단 메시지가 "이 세션에서"라고 말하는 것과도 어긋난다.
    _stage_external_api
    SESSION=s1
    printf '%s' "$(_json_skill simplify)"        | bash "$GATE" record
    printf '%s' "$(_json_skill code-review)"     | bash "$GATE" record
    printf '%s' "$(_json_skill security-review)" | bash "$GATE" record
    run bash -c "printf '%s' '$(SESSION=s1; _json_cmd "git commit -m x")' | bash '$GATE' pretooluse"
    [ "$status" -eq 0 ]
    run bash -c "printf '%s' '$(SESSION=s2; _json_cmd "git commit -m x")' | bash '$GATE' pretooluse"
    [ "$status" -eq 2 ]
}

@test "gate: .mangolove/.review-skip 은 1회용 우회이고 소비된다" {
    # 환경변수 우회는 훅에 닿지 않는다(훅은 Claude Code 프로세스 환경에서 뜬다).
    # 세션 도중 막혔을 때 에이전트가 실제로 쓸 수 있는 경로가 있어야 한다.
    _stage_external_api
    mkdir -p "$REPO_DIR/.mangolove"
    touch "$REPO_DIR/.mangolove/.review-skip"
    run bash -c "printf '%s' '$(_json_cmd "git commit -m x")' | bash '$GATE' pretooluse"
    [ "$status" -eq 0 ]
    [ ! -f "$REPO_DIR/.mangolove/.review-skip" ]
    # 소비됐으므로 다음 커밋은 다시 막힌다
    run bash -c "printf '%s' '$(_json_cmd "git commit -m x")' | bash '$GATE' pretooluse"
    [ "$status" -eq 2 ]
}
