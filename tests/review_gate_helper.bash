#!/bin/bash
# ─────────────────────────────────────────────
# MangoLove: review-gate 테스트 공용 준비 코드
#
# review-gate 테스트는 주제별로 여러 파일에 나뉘어 있다(tests/review-gate*.bats). 나눈 이유는
# tests/run.sh 머리말에 있다.
# ─────────────────────────────────────────────

setup() {
    setup_test_env
    GATE="$MANGOLOVE_DIR/lib/review-gate.sh"
    REPO_DIR="$TEST_DIR/proj"
    _init_repo_with_upstream "$REPO_DIR" "$TEST_DIR/fake-remote.git"
}

# seed 커밋 하나와 upstream(origin/main)을 가진 레포를 심는다(네트워크도 클론도 없이).
# --set-upstream-to 는 실제 remote 의 fetch refspec 을 요구하므로 원격 추적 ref 와 branch.* 설정을 직접 심는다.
_init_repo_with_upstream() {
    mkdir -p "$1"
    git -C "$1" init -q -b main
    git -C "$1" config user.email t@example.com
    git -C "$1" config user.name t
    echo seed > "$1/seed.txt"
    git -C "$1" add -A
    git -C "$1" commit -qm seed
    git -C "$1" remote add origin "$2"
    git -C "$1" update-ref refs/remotes/origin/main HEAD
    git -C "$1" config branch.main.remote origin
    git -C "$1" config branch.main.merge refs/heads/main
}

teardown() {
    teardown_test_env
}

# PreToolUse(Bash) JSON: 명령 + cwd + session_id
_json_cmd() {
    local c="${1//\"/\\\"}"
    printf '{"tool_name":"Bash","session_id":"%s","cwd":"%s","tool_input":{"command":"%s"}}' \
        "${SESSION:-s1}" "${CWD:-$REPO_DIR}" "$c"
}

# PostToolUse(Skill) JSON: 실행된 스킬 이름 + cwd
# 필드 이름은 실제 세션 트랜스크립트에서 실측한 것이다: {"skill":"simplify"}.
# $2 가 있으면 args 까지 실은 페이로드를 만든다(런타임이 보내는 모양 그대로).
_json_skill() {
    if [ -n "${2:-}" ]; then
        printf '{"tool_name":"Skill","session_id":"%s","cwd":"%s","tool_input":{"skill":"%s","args":"%s"}}' \
            "${SESSION:-s1}" "${CWD:-$REPO_DIR}" "$1" "$2"
    else
        printf '{"tool_name":"Skill","session_id":"%s","cwd":"%s","tool_input":{"skill":"%s"}}' \
            "${SESSION:-s1}" "${CWD:-$REPO_DIR}" "$1"
    fi
}

# 훅 문서가 적고 있는 대체 필드명. 런타임이 어느 쪽을 보내도 원장이 채워져야 한다.
_json_skill_alt() {
    printf '{"tool_name":"Skill","session_id":"%s","cwd":"%s","tool_input":{"skill_name":"%s"}}' \
        "${SESSION:-s1}" "${CWD:-$REPO_DIR}" "$1"
}

_gate() { run bash -c "printf '%s' '$(_json_cmd "$1")' | bash '$GATE' pretooluse"; }

# 외부 API 신호 = Medium 승격. 커밋까지 해야 push 범위에 들어간다.
_commit_external_api() { _commit_external_api_in "$REPO_DIR" "$@"; }

# 외부 API 신호(Medium)를 지정한 레포에 커밋한다. $2 가 있으면 파일 이름과 경로에 붙인다.
_commit_external_api_in() {
    printf 'const r = await axios.get("https://api.example.com/%s")\n' "${2:-v1}" \
        > "$1/client${2:-}.js"
    git -C "$1" add -A
    git -C "$1" commit -qm "api ${2:-v1}"
}

# 파일 $1 끝에 외부 호출 한 줄을 덧붙인다(커밋하지 않는다). $2 는 호출을 구별하는 꼬리표.
_add_external_call() {
    printf 'const r_%s = await axios.get("https://api.example.com/%s")\n' "$2" "$2" >> "$1"
}

# 이 세션에서 Medium 필수 리뷰 3종을 모두 돌린 것으로 기록한다(외부 API 신호가 있으면
# security-review 까지 필수다). record 는 그 시점 내용을 커버리지로 함께 스냅샷한다.
_run_all_reviews() {
    printf '%s' "$(_json_skill simplify "${1:-}")"        | bash "$GATE" record
    printf '%s' "$(_json_skill code-review "${1:-}")"     | bash "$GATE" record
    printf '%s' "$(_json_skill security-review "${1:-}")" | bash "$GATE" record
}

# 브랜치 하나에 파일 N개짜리 커밋을 만든다. 끝나면 main 으로 돌아온다. $1 브랜치, $2 시작점, $3 파일 수
_branch_commit() {
    local i tag="$1-$RANDOM"
    git -C "$REPO_DIR" checkout -q -B "$1" "$2"
    for i in $(seq 1 "$3"); do echo "export const F$i = $i" > "$REPO_DIR/work-$tag-$i.js"; done
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm "work $1"
    git -C "$REPO_DIR" checkout -q main
}

# 갈라진 형제 브랜치(현재 브랜치의 조상도 upstream 도 아니다).
_make_sibling() { _branch_commit "$1" main 1; }

# 파일 11개(= Medium)짜리 남의 작업을 원격 추적 ref 로 올린다. $1 원격 브랜치 이름, $2 시작점(기본 main)
_remote_foreign_work() {
    _branch_commit "tmp-$1" "${2:-main}" 11
    git -C "$REPO_DIR" update-ref "refs/remotes/origin/$1" "tmp-$1"
}

# 세션 cwd 가 아닌 두 번째 레포. REPO_DIR 과 같은 절차로 심는다.
_other_repo() {
    OTHER="$TEST_DIR/other"
    _init_repo_with_upstream "$OTHER" "$TEST_DIR/other-remote.git"
}

_block_kinds() { grep -o '"kind":"[a-z]*"' "$MANGOLOVE_DIR/efficacy/proj.jsonl" 2>/dev/null | tail -1; }
