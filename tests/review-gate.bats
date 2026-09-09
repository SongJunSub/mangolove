#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove: Review gate (트랙별 필수 리뷰의 결정적 강제)
#
# 회귀 대상 행동: "Medium 트랙인데 /simplify 와 코드 리뷰를 돌리지 않았습니다,
# 필요하시면 지금 돌리겠습니다": 트랙을 선언하고 절차를 생략한 뒤 사후에 고백하는 것.
# 이 게이트는 push 경계에서 코드가 트랙을 계산해 그 답변 자체가 불가능하게 만든다.
#
# 경계가 commit 이 아니라 push 인 이유는 실측이다(차단 39건 중 23건이 10분 내 재차단).
# 그 이동이 안전을 깎지 않는다는 것을 이 파일의 "위험 N" 테스트들이 고정한다.
# ─────────────────────────────────────────────

load test_helper

setup() {
    setup_test_env
    GATE="$MANGOLOVE_DIR/lib/review-gate.sh"
    REPO_DIR="$TEST_DIR/proj"
    mkdir -p "$REPO_DIR"
    git -C "$REPO_DIR" init -q -b main
    git -C "$REPO_DIR" config user.email t@example.com
    git -C "$REPO_DIR" config user.name t
    echo seed > "$REPO_DIR/seed.txt"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm seed
    # upstream 을 흉내낸다(네트워크도 클론도 없이). --set-upstream-to 는 실제 remote 의
    # fetch refspec 을 요구하므로 원격 추적 ref 와 branch.* 설정을 직접 심는다.
    git -C "$REPO_DIR" remote add origin "$TEST_DIR/fake-remote.git"
    git -C "$REPO_DIR" update-ref refs/remotes/origin/main HEAD
    git -C "$REPO_DIR" config branch.main.remote origin
    git -C "$REPO_DIR" config branch.main.merge refs/heads/main
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
# $2 가 있으면 args 까지 실은 페이로드를 만든다(런타임이 보내는 모양 그대로).
_json_skill() {
    if [ -n "${2:-}" ]; then
        printf '{"tool_name":"Skill","session_id":"%s","cwd":"%s","tool_input":{"skill":"%s","args":"%s"}}' \
            "${SESSION:-s1}" "$REPO_DIR" "$1" "$2"
    else
        printf '{"tool_name":"Skill","session_id":"%s","cwd":"%s","tool_input":{"skill":"%s"}}' \
            "${SESSION:-s1}" "$REPO_DIR" "$1"
    fi
}

# 훅 문서가 적고 있는 대체 필드명. 런타임이 어느 쪽을 보내도 원장이 채워져야 한다.
_json_skill_alt() {
    printf '{"tool_name":"Skill","session_id":"%s","cwd":"%s","tool_input":{"skill_name":"%s"}}' \
        "${SESSION:-s1}" "$REPO_DIR" "$1"
}

_gate() { run bash -c "printf '%s' '$(_json_cmd "$1")' | bash '$GATE' pretooluse"; }

# 외부 API 신호 = Medium 승격. 커밋까지 해야 push 범위에 들어간다.
_commit_external_api() {
    printf 'const r = await axios.get("https://api.example.com/%s")\n' "${1:-v1}" \
        > "$REPO_DIR/client${1:-}.js"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm "api ${1:-v1}"
}

# 이 세션에서 Medium 필수 리뷰 3종을 모두 돌린 것으로 기록한다(외부 API 신호가 있으면
# security-review 까지 필수다). record 는 그 시점 내용을 커버리지로 함께 스냅샷한다.
_run_all_reviews() {
    printf '%s' "$(_json_skill simplify "${1:-}")"        | bash "$GATE" record
    printf '%s' "$(_json_skill code-review "${1:-}")"     | bash "$GATE" record
    printf '%s' "$(_json_skill security-review "${1:-}")" | bash "$GATE" record
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

# ── push 경계 게이트 ────────────────────────────────────────────

@test "gate: push 가 아닌 Bash 는 통과 (게이트가 일반 작업을 막지 않는다)" {
    _commit_external_api
    _gate "git log --grep=push"
    [ "$status" -eq 0 ]
}

@test "gate: commit 은 더 이상 게이트 대상이 아니다 (로컬 작업을 방해하지 않는다)" {
    # 경계를 push 로 옮긴 핵심. 커밋마다 막던 것이 재차단 23건의 원인이었다.
    _commit_external_api
    _gate "git commit -m x"
    [ "$status" -eq 0 ]
}

@test "gate: Trivial 범위 push 는 리뷰 없이 통과 (사소한 작업에 절차를 씌우지 않는다)" {
    echo "one line" > "$REPO_DIR/a.txt"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm x
    _gate "git push"
    [ "$status" -eq 0 ]
}

@test "gate: Medium 범위인데 리뷰 미실행이면 push 차단(exit 2)" {
    _commit_external_api
    _gate "git push"
    [ "$status" -eq 2 ]
    [[ "$output" == *"push 차단"* ]]
    [[ "$output" == *"simplify"* ]]
    [[ "$output" == *"code-review"* ]]
}

@test "gate: 원장에 필수 스킬이 기록돼 있고 그 내용이면 통과한다" {
    _commit_external_api
    _run_all_reviews
    [ -f "$REPO_DIR/.mangolove/.review-ledger" ]
    _gate "git push"
    [ "$status" -eq 0 ]
}

@test "gate: 일부만 실행하면 부족분만 지목하며 차단" {
    _commit_external_api
    printf '%s' "$(_json_skill simplify)" | bash "$GATE" record
    _gate "git push"
    [ "$status" -eq 2 ]
    [[ "$output" == *"code-review"* ]]
}

@test "gate: 플러그인 네임스페이스(code-review:code-review)도 같은 스킬로 인정" {
    _commit_external_api
    printf '%s' "$(_json_skill simplify)" | bash "$GATE" record
    printf '%s' "$(_json_skill "code-review:code-review")" | bash "$GATE" record
    printf '%s' "$(_json_skill "security:security-review")" | bash "$GATE" record
    _gate "git push"
    [ "$status" -eq 0 ]
}

# ── 이 이동이 없앤 소음 ─────────────────────────────────────────

@test "개선: 리뷰 한 번 뒤 커밋을 몇 개로 쪼개 담아도 push 는 통과한다" {
    # 옛 게이트의 실패 모드: 커밋이 성공해 HEAD 가 움직이면 원장을 버려서, 두 번째
    # 커밋부터 이미 한 리뷰를 다시 요구했다. 실측 차단의 59%가 이것이었다.
    printf 'const a = await axios.get("https://api.example.com/a")\n' > "$REPO_DIR/a.js"
    printf 'const b = await axios.get("https://api.example.com/b")\n' > "$REPO_DIR/b.js"
    printf 'const c = await axios.get("https://api.example.com/c")\n' > "$REPO_DIR/c.js"
    _run_all_reviews   # 워킹트리 상태 그대로를 리뷰가 봤다

    local f
    for f in a b c; do
        git -C "$REPO_DIR" add "$f.js"
        git -C "$REPO_DIR" commit -qm "add $f"
    done
    _gate "git push"
    [ "$status" -eq 0 ]
}

@test "개선: 이미 upstream 에 있는 브랜치를 머지해도 push 는 통과한다 (머지 특별처리 없이)" {
    # 원래 막혔던 케이스: `merge: HUB2-378 ... 반영` 이 13개 파일 Large 로 계산됐다.
    # 세 점 범위의 merge base 가 그 내용을 자동으로 뺀다.
    git -C "$REPO_DIR" checkout -q -b feat-378
    printf 'const x = await axios.get("https://api.example.com/378")\n' > "$REPO_DIR/f378.js"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm "378 work"

    # 378 이 upstream 에 반영됐다 (= 그 브랜치에서 이미 검토, 공유된 코드)
    git -C "$REPO_DIR" checkout -q main
    git -C "$REPO_DIR" merge -q --no-ff -m "merge 378" feat-378
    git -C "$REPO_DIR" update-ref refs/remotes/origin/main HEAD

    # 내 브랜치는 378 을 머지하고 사소한 작업만 얹는다
    git -C "$REPO_DIR" checkout -q -b feat-379 refs/remotes/origin/main
    echo mine > "$REPO_DIR/mine.txt"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm "my small work"

    _gate "git push"
    [ "$status" -eq 0 ]
}

# ── 위험 회귀: push 로 옮기면서 안전이 깎이지 않았음을 고정한다 ──

@test "위험1: 머지 충돌을 해결하며 새로 쓴 코드는 범위에 남아 차단된다" {
    git -C "$REPO_DIR" checkout -q -b other
    echo theirs > "$REPO_DIR/shared.js"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm theirs
    git -C "$REPO_DIR" checkout -q main
    echo ours > "$REPO_DIR/shared.js"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm ours
    git -C "$REPO_DIR" merge -q other 2>/dev/null || true
    # 충돌 해결이랍시고 검토되지 않은 새 코드를 써 넣는다
    printf 'const evil = await axios.post("https://api.example.com/x", {})\n' > "$REPO_DIR/shared.js"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm "resolve"
    _gate "git push"
    [ "$status" -eq 2 ]
}

@test "위험2: 리뷰가 본 뒤에 고친 파일은 커버리지에서 빠져 차단된다" {
    printf 'const a = await axios.get("https://api.example.com/a")\n' > "$REPO_DIR/a.js"
    _run_all_reviews    # 이 내용까지가 리뷰가 본 것
    # 리뷰 이후에 내용을 바꾼다
    printf 'const a = await axios.get("https://api.example.com/a")\nconst evil = eval(userInput)\n' > "$REPO_DIR/a.js"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm "sneak"
    _gate "git push"
    [ "$status" -eq 2 ]
}

@test "위험3: 작은 커밋으로 쪼개도 범위는 합쳐서 계산돼 차단된다" {
    # 커밋 하나하나는 Trivial 이라 커밋 경계 게이트라면 전부 통과했을 변경이다.
    local i
    for i in $(seq 1 11); do
        echo "export const V$i = $i" > "$REPO_DIR/f$i.js"
        git -C "$REPO_DIR" add -A
        git -C "$REPO_DIR" commit -qm "c$i"
    done
    _gate "git push"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Medium"* ]]
}

@test "위험4: upstream 에 없는 브랜치를 머지하면 그 내용이 범위에 남아 차단된다" {
    git -C "$REPO_DIR" checkout -q -b rogue
    printf 'const r = await axios.post("https://api.example.com/rogue", {})\n' > "$REPO_DIR/rogue.js"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm rogue
    git -C "$REPO_DIR" checkout -q main
    git -C "$REPO_DIR" merge -q --no-ff -m "merge rogue" rogue
    _gate "git push"
    [ "$status" -eq 2 ]
}

@test "위험: 다른 세션의 원장은 오늘의 push 를 통과시키지 않는다" {
    _commit_external_api
    SESSION=s1
    _run_all_reviews
    run bash -c "printf '%s' '$(SESSION=s1; _json_cmd "git push")' | bash '$GATE' pretooluse"
    [ "$status" -eq 0 ]
    run bash -c "printf '%s' '$(SESSION=s2; _json_cmd "git push")' | bash '$GATE' pretooluse"
    [ "$status" -eq 2 ]
}

# ── 명령 인식 경계 ──────────────────────────────────────────────

@test "gate: --dry-run push 는 아무 것도 공유하지 않으므로 통과" {
    _commit_external_api
    _gate "git push --dry-run"
    [ "$status" -eq 0 ]
}

@test "gate: push 뒤에 붙은 다른 명령의 -n 을 dry-run 으로 오인하지 않는다" {
    # 오인하면 게이트가 통째로 샌다. 오탐보다 누락이 위험한 방향이다.
    _commit_external_api
    _gate "git push origin main && echo -n done"
    [ "$status" -eq 2 ]
}

@test "gate: 멀티라인 명령의 git push 도 잡는다 (JSON 의 \\n 이 단어 경계를 지운다)" {
    _commit_external_api
    _gate 'git add -A\ngit push'
    [ "$status" -eq 2 ]
}

@test "gate: gh pr create 도 같은 경계로 본다" {
    _commit_external_api
    _gate "gh pr create --fill"
    [ "$status" -eq 2 ]
}

@test "gate: 여러 줄이어도 push 가 없으면 통과한다 (오탐 방지)" {
    _commit_external_api
    _gate 'git log --grep=push\necho done'
    [ "$status" -eq 0 ]
}

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
    [ "$(grep -cx simplify "$REPO_DIR/.mangolove/.review-ledger")" -eq 1 ]
}

@test "record: tool_input 의 skill 과 skill_name 을 모두 받는다 (문서와 런타임이 다르다)" {
    # 경계면 교차검증 회귀: 한쪽 이름만 받으면 원장이 영영 비어 Medium 이상 push 가
    # 전부 막힌다. 실측한 런타임 필드는 skill, 훅 문서가 적은 것은 skill_name 이다.
    printf '%s' "$(_json_skill simplify)"        | bash "$GATE" record
    printf '%s' "$(_json_skill_alt code-review)" | bash "$GATE" record
    grep -qx simplify    "$REPO_DIR/.mangolove/.review-ledger"
    grep -qx code-review "$REPO_DIR/.mangolove/.review-ledger"
}

@test "record: 리뷰가 본 내용을 커버리지 파일에 blob 해시로 남긴다" {
    echo changed > "$REPO_DIR/seed.txt"
    printf '%s' "$(_json_skill simplify)" | bash "$GATE" record
    [ -f "$REPO_DIR/.mangolove/.review-covered" ]
    local h; h=$(git -C "$REPO_DIR" hash-object "$REPO_DIR/seed.txt")
    grep -qF "$h" "$REPO_DIR/.mangolove/.review-covered"
}

@test "record: 커버리지는 중복 없이 집합으로 유지된다" {
    echo changed > "$REPO_DIR/seed.txt"
    printf '%s' "$(_json_skill simplify)"    | bash "$GATE" record
    printf '%s' "$(_json_skill code-review)" | bash "$GATE" record
    local cov="$REPO_DIR/.mangolove/.review-covered"
    [ "$(sort -u "$cov" | wc -l | tr -d ' ')" -eq "$(wc -l < "$cov" | tr -d ' ')" ]
}

@test "record: 원장 디렉토리를 만들 때 .mangolove/.gitignore 를 심는다 (레포 오염 방지)" {
    # 게이트를 켠 모든 레포에서 사용자가 손으로 .gitignore 를 고치게 만들지 않는다.
    # 단, .mangolove/ 를 통째로 무시하면 안 된다: .mangolove/hooks/ 는 버전관리 감사 대상이다.
    printf '%s' "$(_json_skill simplify)" | bash "$GATE" record
    [ -f "$REPO_DIR/.mangolove/.gitignore" ]
    grep -qx '.review-ledger' "$REPO_DIR/.mangolove/.gitignore"
    grep -qx '.review-covered' "$REPO_DIR/.mangolove/.gitignore"
    grep -qx 'dod.sh' "$REPO_DIR/.mangolove/.gitignore"
    # 자기 자신도 무시해야 사용자 레포에 요청하지 않은 파일이 생기지 않는다.
    grep -qx '.gitignore' "$REPO_DIR/.mangolove/.gitignore"
    # 통째 무시(*)는 안 된다: .mangolove/hooks/ 는 버전관리 감사 대상이다.
    ! grep -qx '\*' "$REPO_DIR/.mangolove/.gitignore"
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
    grep -qxF "simplify	$h	seed.txt" "$REPO_DIR/.mangolove/.review-covered"
}

# ── 코드/보안 리뷰가 찾은 우회들 (전부 조용한 통과였다) ────────

@test "우회: 비-ASCII 파일명이 게이트를 통과하지 않는다 (core.quotePath)" {
    # git 은 기본값에서 비-ASCII 경로를 "\355\225\234..." 로 C-quote 한다. 그 문자열을
    # pathspec 으로 넘기면 아무 파일도 안 잡혀 잔여 0건 -> Trivial -> 조용히 통과했다.
    printf 'const a = await axios.get("https://api.example.com/a")\n' > "$REPO_DIR/a.js"
    _run_all_reviews
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm reviewed
    # 리뷰가 본 적 없는 한글 파일명 Medium 변경을 얹는다
    printf 'const k = await axios.post("https://api.example.com/k", {})\n' > "$REPO_DIR/한글파일.js"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm korean
    _gate "git push"
    [ "$status" -eq 2 ]
}

@test "우회: dry-run 미끼 뒤에 붙은 진짜 push 를 잡는다" {
    # `git push --dry-run && git push origin main` 은 한 줄이다. push 키워드 뒤를
    # 첫 구분자에서 끊으면 앞의 dry-run 만 보고 뒤의 진짜 push 를 통째로 놓쳤다.
    _commit_external_api
    _gate "git push --dry-run && git push origin main"
    [ "$status" -eq 2 ]
}

@test "우회: 줄바꿈으로 이어진 dry-run + 진짜 push 도 잡는다" {
    _commit_external_api
    _gate 'git push --dry-run\ngit push origin main'
    [ "$status" -eq 2 ]
}

@test "우회: refspec 으로 다른 브랜치를 올리면 그 브랜치를 판정한다" {
    # `git push origin topic:main` 은 현재 브랜치가 아니라 topic 을 올린다.
    # HEAD 를 가정하면 (깨끗한) main 을 보고 통과시켰다.
    git -C "$REPO_DIR" checkout -q -b topic
    printf 'const t = await axios.get("https://api.example.com/t")\n' > "$REPO_DIR/t.js"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm topic
    git -C "$REPO_DIR" checkout -q main    # main 은 origin/main 과 동일 = 범위 비어 있음
    _gate "git push origin topic:main"
    [ "$status" -eq 2 ]
}

@test "게이트 대상 아님: 원격 브랜치 삭제는 내용을 공유하지 않는다" {
    _commit_external_api
    _gate "git push --delete origin oldbranch"
    [ "$status" -eq 0 ]
    _gate "git push -d origin oldbranch"
    [ "$status" -eq 0 ]
}

@test "status: 범위가 아닌 ref 는 거짓 PASS 대신 거부한다" {
    # _range_signature 는 A...B 만 이해한다. sha 를 넘기면 서명이 비어 모든 스킬이
    # 충족으로 보이고 "필수 리뷰: simplify code-review / 판정: PASS" 라는 모순이 났다.
    _commit_external_api
    run bash -c "cd '$REPO_DIR' && bash '$GATE' status HEAD"
    [ "$status" -eq 2 ]
    [[ "$output" == *"범위(A...B)만"* ]]
    run bash -c "cd '$REPO_DIR' && bash '$GATE' status --working"
    [ "$status" -eq 2 ]
}

@test "보안: 상태 파일이 심볼릭 링크면 그리로 쓰지 않는다" {
    # 적대적 브랜치가 .review-covered 를 레포 밖으로 향하는 링크로 커밋해 두면,
    # 리뷰 스킬 한 번으로 그 파일에 공격자가 정한 경로 문자열이 append 된다.
    local target="$TEST_DIR/outside.txt"
    echo "원본" > "$target"
    mkdir -p "$REPO_DIR/.mangolove"
    ln -s "$target" "$REPO_DIR/.mangolove/.review-covered"
    echo changed > "$REPO_DIR/seed.txt"
    printf '%s' "$(_json_skill simplify)" | bash "$GATE" record
    [ "$(cat "$target")" = "원본" ]
    [ ! -L "$REPO_DIR/.mangolove/.review-covered" ]
}

# ── prepush: git 이 주는 ref 목록을 쓴다 ───────────────────────

@test "prepush: git 이 준 ref 로 판정한다 (현재 브랜치를 가정하지 않는다)" {
    _commit_external_api
    local sha; sha=$(git -C "$REPO_DIR" rev-parse HEAD)
    local base; base=$(git -C "$REPO_DIR" rev-parse origin/main)
    run bash -c "cd '$REPO_DIR' && printf 'refs/heads/main %s refs/heads/main %s\n' '$sha' '$base' | bash '$GATE' prepush origin /tmp/fake.git"
    [ "$status" -eq 1 ]
    [[ "$output" == *"push 차단"* ]]
}

@test "prepush: 삭제 ref 는 통과시킨다 (내용을 공유하지 않는다)" {
    _commit_external_api
    local sha; sha=$(git -C "$REPO_DIR" rev-parse HEAD)
    run bash -c "cd '$REPO_DIR' && printf '(delete) 0000000000000000000000000000000000000000 refs/heads/old %s\n' '$sha' | bash '$GATE' prepush origin /tmp/fake.git"
    [ "$status" -eq 0 ]
}

@test "prepush: git 이 불렀는데 올릴 ref 가 없으면 통과한다" {
    # 이미 up-to-date 인 push 다. 공유되는 내용이 없으므로 막을 이유가 없다.
    _commit_external_api
    run bash -c "cd '$REPO_DIR' && bash '$GATE' prepush origin /tmp/fake.git </dev/null"
    [ "$status" -eq 0 ]
}

@test "prepush: 설치된 게이트가 구버전이면 push 를 막지 않는다 (버전 스큐 fail-open)" {
    # 훅은 레포에 커밋돼 함께 배포되고 게이트는 머신마다 따로 설치된다. 설치본이
    # prepush 를 모르면 usage + exit 2 라, 그대로 exec 하면 그 머신의 push 가 전부 막힌다.
    local old="$TEST_DIR/oldinstall"; mkdir -p "$old/lib"
    cat > "$old/lib/review-gate.sh" <<'OLD'
#!/usr/bin/env bash
echo "usage: review-gate.sh {record|pretooluse|required|status}" >&2
exit 2
OLD
    run bash -c "MANGOLOVE_DIR='$old' bash '$BATS_TEST_DIRNAME/../.githooks/pre-push' origin url </dev/null"
    [ "$status" -eq 0 ]
}

# ── 커버리지 범위: 스킬이 실제로 본 것만 인정한다 ──────────────
#
# args 는 도구 호출 사실이라 근거로 쓸 수 있다. 무시하면 `/code-review 1952` 처럼
# **원격 PR 을 본 리뷰**가 이 워킹트리 전체를 통과시킨다(이 트리를 쳐다보지도 않았는데).

@test "범위: PR 번호를 리뷰한 스킬은 이 워킹트리를 커버하지 않는다" {
    _commit_external_api
    _run_all_reviews "1952"
    _gate "git push"
    [ "$status" -eq 2 ]
}

@test "범위: PR URL 을 리뷰한 스킬도 이 워킹트리를 커버하지 않는다" {
    _commit_external_api
    _run_all_reviews "https://github.com/o/r/pull/710"
    _gate "git push"
    [ "$status" -eq 2 ]
}

@test "범위: 레포 밖 경로(다른 worktree)를 리뷰하면 커버하지 않는다" {
    _commit_external_api
    local other="$TEST_DIR/otherworktree"; mkdir -p "$other"
    _run_all_reviews "high $other"
    _gate "git push"
    [ "$status" -eq 2 ]
}

@test "범위: 짚은 경로만 커버한다 (짚지 않은 파일은 여전히 미검토)" {
    printf 'const a = await axios.get("https://api.example.com/a")\n' > "$REPO_DIR/a.js"
    printf 'const b = await axios.get("https://api.example.com/b")\n' > "$REPO_DIR/b.js"
    _run_all_reviews "high a.js"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm two
    _gate "git push"
    [ "$status" -eq 2 ]
    # a.js 는 covered, b.js 는 아니다
    grep -q "	a.js\$" "$REPO_DIR/.mangolove/.review-covered"
    ! grep -q "	b.js\$" "$REPO_DIR/.mangolove/.review-covered"
}

@test "범위: 짚은 경로를 전부 덮으면 통과한다" {
    printf 'const a = await axios.get("https://api.example.com/a")\n' > "$REPO_DIR/a.js"
    _run_all_reviews "high a.js"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm one
    _gate "git push"
    [ "$status" -eq 0 ]
}

@test "범위: 강도만 준 args 는 기존대로 전체를 커버한다" {
    _commit_external_api
    _run_all_reviews "high"
    _gate "git push"
    [ "$status" -eq 0 ]
}

@test "범위: 무언가를 가리키는데 이 트리에서 못 찾으면 커버하지 않는다" {
    # 기본값을 ALL 로 두면 열거 밖의 인자 모양마다 조용한 과대 인정이 생긴다.
    # "해석하지 않겠다"는 안전한 쪽으로 두겠다는 뜻이지 최대로 믿겠다는 뜻이 아니다.
    _commit_external_api
    _run_all_reviews "리뷰 200 줄 정도 워킹트리 변경분 봐줘"
    _gate "git push"
    [ "$status" -eq 2 ]
}

@test "범위: 강도뿐인 호출만 기본 범위를 커버한다 (산문은 아니다)" {
    # 모르는 낱말을 수식어로 넘기면 두 가지가 샌다: 부정문의 경로를 긍정으로 읽고,
    # 브랜치 이름(main)을 준 호출이 전체를 커버한다. 닫힌 목록만 인정한다.
    _commit_external_api
    _run_all_reviews "medium"
    _gate "git push"
    [ "$status" -eq 0 ]
}

@test "위험: 부정문 안의 경로를 커버 대상으로 읽지 않는다" {
    # "lib 는 빼고" 를 "lib 를 봤다" 로 읽으면, 리뷰가 명시적으로 제외한 코드가 통과한다.
    mkdir -p "$REPO_DIR/lib"
    printf 'const a = await axios.get("https://api.example.com/a")\n' > "$REPO_DIR/lib/a.js"
    _run_all_reviews "review everything except lib"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm neg
    _gate "git push"
    [ "$status" -eq 2 ]
}

@test "위험: 브랜치 이름을 리뷰한 호출이 이 워킹트리를 커버하지 않는다" {
    # /code-review main 은 다른 브랜치를 본다. 평범한 낱말이라 형태로는 구별되지 않으므로
    # 닫힌 강도 목록에 없으면 모르는 토큰으로 취급한다.
    _commit_external_api
    _run_all_reviews "main"
    _gate "git push"
    [ "$status" -eq 2 ]
    SESSION=s3
    _run_all_reviews "my-feature-branch"
    run bash -c "printf '%s' '$(SESSION=s3; _json_cmd "git push")' | bash '$GATE' pretooluse"
    [ "$status" -eq 2 ]
}

@test "범위: 열거에 없던 인자 모양도 조용히 통과하지 않는다" {
    # 옛 규칙(PR 낱말 + 순수숫자)을 그대로 빠져나가던 반례다.
    _commit_external_api
    _run_all_reviews "크스-1952 관련 PR 검토해줘"
    _gate "git push"
    [ "$status" -eq 2 ]
}

@test "범위: 짚은 경로 중 하나라도 이 트리에 없으면 커버하지 않는다" {
    printf 'const a = await axios.get("https://api.example.com/a")\n' > "$REPO_DIR/a.js"
    _run_all_reviews "high a.js nosuch.js"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm partial
    _gate "git push"
    [ "$status" -eq 2 ]
}

# ── 코드 리뷰가 실증한 fail-open 들 (전부 조용한 통과였다) ─────

@test "범위: 인용부호로 감싼 경로도 그 경로만 커버한다" {
    # args 는 JSON 이스케이프되어 도착하고(\" ), 되돌려도 셸 인용부호가 토큰에 붙어 있다.
    # 둘 다 처리하지 않으면 토큰이 실제 파일명과 달라 경로 지정이 통째로 무시된다.
    printf 'const a = await axios.get("https://api.example.com/a")\n' > "$REPO_DIR/a b.js"
    printf 'const o = await axios.get("https://api.example.com/o")\n' > "$REPO_DIR/other.js"
    _run_all_reviews 'high \"a b.js\"'
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm quoted
    _gate "git push"
    [ "$status" -eq 2 ]
    grep -q "	a b.js\$"  "$REPO_DIR/.mangolove/.review-covered"
    ! grep -q "	other.js\$" "$REPO_DIR/.mangolove/.review-covered"
}

@test "범위: JSON 이스케이프된 개행으로 나열한 경로들을 인식한다" {
    printf 'const a = await axios.get("https://api.example.com/a")\n' > "$REPO_DIR/a.js"
    printf 'const b = await axios.get("https://api.example.com/b")\n' > "$REPO_DIR/b.js"
    printf 'const c = await axios.get("https://api.example.com/c")\n' > "$REPO_DIR/c.js"
    _run_all_reviews 'a.js\nb.js'
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm nl
    _gate "git push"
    [ "$status" -eq 2 ]
    ! grep -q "	c.js\$" "$REPO_DIR/.mangolove/.review-covered"
}

@test "범위: 스킴 없는 PR 링크도 원격 참조로 본다" {
    _commit_external_api
    _run_all_reviews 'github.com/onda/repo/pull/710'
    _gate "git push"
    [ "$status" -eq 2 ]
}

@test "범위: PR 번호가 낱말과 흩어져 있어도 원격 참조로 본다" {
    # 실측한 실제 호출의 다수가 이 모양이다: "tportio/crs PR #1891".
    _commit_external_api
    _run_all_reviews 'tportio/crs PR #1891'
    _gate "git push"
    [ "$status" -eq 2 ]
    SESSION=s2
    _run_all_reviews 'PR #423 (crs-admin-web)'
    run bash -c "printf '%s' '$(SESSION=s2; _json_cmd "git push")' | bash '$GATE' pretooluse"
    [ "$status" -eq 2 ]
}

@test "범위: 후행 슬래시 디렉토리도 그 아래를 커버한다 (git pathspec)" {
    mkdir -p "$REPO_DIR/lib"
    printf 'const a = await axios.get("https://api.example.com/a")\n' > "$REPO_DIR/lib/a.js"
    _run_all_reviews 'high lib/'
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm dir
    _gate "git push"
    [ "$status" -eq 0 ]
}

@test "범위: 레포 안 절대경로는 경로로, 레포 밖 절대경로는 미커버로 본다" {
    printf 'const a = await axios.get("https://api.example.com/a")\n' > "$REPO_DIR/a.js"
    _run_all_reviews "high $REPO_DIR/a.js"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm abs
    _gate "git push"
    [ "$status" -eq 0 ]
}

@test "범위: 실재하는 pull 경로는 PR 링크로 오인하지 않는다" {
    mkdir -p "$REPO_DIR/docs/pull"
    printf 'const a = await axios.get("https://api.example.com/a")\n' > "$REPO_DIR/docs/pull/710"
    _run_all_reviews "high docs/pull/710"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm realpath
    _gate "git push"
    [ "$status" -eq 0 ]
}

@test "범위: # 없이 'PR 1891' 로 써도 원격 참조로 본다" {
    # #번호 규칙과 별개 경로다. 이 테스트가 없으면 낱말+숫자 규칙이 검증되지 않는다
    # (변이 테스트로 확인: 규칙을 지워도 다른 테스트가 아무도 실패하지 않았다).
    _commit_external_api
    _run_all_reviews 'tportio/crs PR 1891'
    _gate "git push"
    [ "$status" -eq 2 ]
}
