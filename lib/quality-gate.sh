#!/usr/bin/env bash
# ─────────────────────────────────────────────
# MangoLove — Quality Gate (커밋 경계 결정적 차단 게이트)
#
# bare mangolove 세션에 PreToolUse 훅으로 런타임 주입된다(claude --settings).
# 이 게이트 로직은 버전관리 대상이라 diff로 리뷰/감사된다 (어조가 아니라 코드로 강제).
#
# 사용:
#   quality-gate.sh precommit    # git pre-commit hook 에서 호출 (실패 시 exit 1 = 커밋 차단)
#   quality-gate.sh pretooluse   # Claude PreToolUse hook 에서 호출, stdin=JSON
#                                #   (git commit 일 때만 게이트, 실패 시 exit 2 = 도구 호출 차단)
#
# 우회(감사됨): MANGOLOVE_SKIP_GATE=1
# 설정: 같은 디렉토리의 gate.conf (GATE_LINT/GATE_TEST = block|warn|off, LINT_CMD/TEST_CMD)
# ─────────────────────────────────────────────
set -uo pipefail

GATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1:-precommit}"

# PreToolUse 모드: stdin JSON 에서 bare 명령을 추출해 git ... commit 서브커맨드일 때만 게이트.
# (matcher 가 Bash 전체라, git log --grep=commit / git config commit.x 같은 비커밋은 통과시킨다.)
if [ "$MODE" = "pretooluse" ]; then
    input="$(cat)"
    raw="$(printf '%s' "$input" | grep -oE '"command"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' | head -1)"
    cmd="${raw#*\"command\"*:*\"}"
    cmd="${cmd%\"}"
    # git 을 단어 경계로 잡고, 옵션 토큰(-C dir 등 인자 동반 포함)을 건너뛴 뒤 commit 서브커맨드만 매칭
    if ! printf '%s' "$cmd" | grep -qE '(^|[^[:alnum:]_])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-][^[:space:]]*)?)*[[:space:]]+commit([[:space:]]|$)'; then
        exit 0
    fi
    # git commit -a/-am 은 tracked 변경을 자동 스테이징하므로 시크릿 스캔을 인덱스+워킹트리(HEAD)로 확대
    if printf '%s' "$cmd" | grep -qE 'commit[[:space:]]+(-[a-zA-Z]*a|--all)'; then
        SECRET_DIFF_REF="HEAD"
    fi
    # 세션 hook 으로 다른 cwd 에서 실행될 수 있으므로 stdin 의 cwd 로 이동해 프로젝트를 정확히 식별
    cwd_field="$(printf '%s' "$input" | grep -oE '"cwd"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' | head -1)"
    cwd_field="${cwd_field#*\"cwd\"*:*\"}"
    cwd_field="${cwd_field%\"}"
    if [ -n "$cwd_field" ] && [ -d "$cwd_field" ]; then
        cd "$cwd_field" 2>/dev/null || true
    fi
fi

# 감사되는 우회구 — strict.md 는 우회를 금지하나 물리적으로는 존재한다.
if [ "${MANGOLOVE_SKIP_GATE:-}" = "1" ]; then
    echo "MangoLove gate: MANGOLOVE_SKIP_GATE=1 (게이트 우회 — 감사 대상)" >&2
    exit 0
fi

# gate.conf 를 셸로 source 하지 않는다 — 클론/공유된 레포의 악성 gate.conf 가 source
# 시점에 임의 코드를 실행하는 공급망 위험(RCE)을 차단. 화이트리스트 KEY=VALUE 만 파싱한다.
if [ -f "$GATE_DIR/gate.conf" ]; then
    while IFS='=' read -r _k _v; do
        case "$_k" in
            GATE_LINT|GATE_TEST|GATE_SECRET|SECRET_SCANNER|LINT_CMD|TEST_CMD)
                _v="${_v%\"}"; _v="${_v#\"}"   # 값 양끝 큰따옴표 제거
                printf -v "$_k" '%s' "$_v" ;;
        esac
    done < <(grep -E '^(GATE_LINT|GATE_TEST|GATE_SECRET|SECRET_SCANNER|LINT_CMD|TEST_CMD)=' "$GATE_DIR/gate.conf")
fi

GATE_LINT="${GATE_LINT:-off}"
GATE_TEST="${GATE_TEST:-off}"
GATE_SECRET="${GATE_SECRET:-off}"
SECRET_SCANNER="${SECRET_SCANNER:-builtin}"
LINT_CMD="${LINT_CMD:-}"
TEST_CMD="${TEST_CMD:-}"

failures=""
warnings=""

# run_step <이름> <모드> <명령>
# block: 실패 시 차단 대상에 추가 + 실패 출력 표시. warn: 경고만. off/빈 명령: 건너뜀.
run_step() {
    local name="$1" mode="$2" cmd="$3" out rc
    [ "$mode" = "off" ] && return 0
    [ -z "$cmd" ] && return 0
    out="$(eval "$cmd" 2>&1)"
    rc=$?
    [ "$rc" -eq 0 ] && return 0
    if [ "$mode" = "block" ]; then
        failures="${failures} ${name}"
        printf '%s\n' "--- MangoLove gate: ${name} 실패 (마지막 20줄) ---" >&2
        printf '%s\n' "$out" | tail -20 >&2
    else
        warnings="${warnings} ${name}"
    fi
}

# 스테이징된 변경에서 시크릿/자격증명 의심 패턴을 스캔한다 (값은 절대 출력하지 않음).
# 시크릿은 한 번 커밋되면 회수 불가 — 비가역 표면이라 고신뢰 패턴은 결정적으로 막는다.
# 고신뢰 prefix 패턴(오탐 거의 없음)은 차단, 제네릭 keyword=value 휴리스틱은 오탐 위험이 커 경고만.
# SECRET_SCANNER=gitleaks 면 gitleaks 로 위임(설치 시).

# 추가(+)된 스테이징 라인을 stdout 으로 (없으면 빈 출력). SECRET_DIFF_REF 로 범위 조정.
_staged_added() {
    git rev-parse --git-dir >/dev/null 2>&1 || return 0
    local staged
    staged="$(git diff "${SECRET_DIFF_REF:---cached}" --no-color 2>/dev/null)"
    [ -z "$staged" ] && return 0
    printf '%s\n' "$staged" | grep -E '^\+' | grep -vE '^\+\+\+'
}

# 고신뢰: 매치 시 0(found). private key / 클라우드·서비스 토큰 / 비밀번호 포함 접속 URL.
_secret_definite() {
    local a="$1"
    printf '%s\n' "$a" | grep -qE 'BEGIN [A-Z ]*PRIVATE KEY' && return 0
    printf '%s\n' "$a" | grep -qE 'AKIA[0-9A-Z]{16}' && return 0
    printf '%s\n' "$a" | grep -qE 'gh[pousr]_[A-Za-z0-9]{36}' && return 0
    printf '%s\n' "$a" | grep -qE 'github_pat_[0-9A-Za-z_]{22,}' && return 0
    printf '%s\n' "$a" | grep -qE 'xox[baprs]-[A-Za-z0-9-]{10,}' && return 0
    printf '%s\n' "$a" | grep -qE 'AIza[0-9A-Za-z_-]{35}' && return 0
    printf '%s\n' "$a" | grep -qE 'sk_(live|test)_[0-9A-Za-z]{24,}' && return 0
    printf '%s\n' "$a" | grep -qE 'npm_[A-Za-z0-9]{36}' && return 0
    printf '%s\n' "$a" | grep -qE 'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}' && return 0
    printf '%s\n' "$a" | grep -qE '://[^:/@[:space:]]+:[^@/[:space:]]+@' && return 0
    return 1
}

# 제네릭 휴리스틱: keyword 뒤 긴 값. 오탐 위험이 커 경고 전용. 매치 시 0(found).
_secret_heuristic() {
    printf '%s\n' "$1" | grep -qiE '(secret|api[_-]?key|access[_-]?token|password)[^A-Za-z0-9]{1,4}[A-Za-z0-9/_+.=-]{20,}' && return 0
    return 1
}

run_step "lint" "$GATE_LINT" "$LINT_CMD"
run_step "test" "$GATE_TEST" "$TEST_CMD"

if [ "$GATE_SECRET" != "off" ]; then
    secret_hit=""
    if [ "$SECRET_SCANNER" = "gitleaks" ] && command -v gitleaks >/dev/null 2>&1; then
        if git rev-parse --git-dir >/dev/null 2>&1 && ! gitleaks protect --staged --no-banner >/dev/null 2>&1; then
            secret_hit="definite"
        fi
    else
        secret_added="$(_staged_added)"
        if [ -n "$secret_added" ]; then
            if _secret_definite "$secret_added"; then
                secret_hit="definite"
            elif _secret_heuristic "$secret_added"; then
                secret_hit="heuristic"
            fi
        fi
    fi
    case "$secret_hit" in
        definite)
            if [ "$GATE_SECRET" = "block" ]; then
                failures="${failures} secret"
                echo "--- MangoLove gate: secret 의심 (값은 표시하지 않음) — 노출 시 즉시 회전(rotate) 필요 ---" >&2
            else
                warnings="${warnings} secret"
            fi ;;
        heuristic)
            warnings="${warnings} secret?"
            echo "--- MangoLove gate 경고: 시크릿 의심(휴리스틱, 비차단) — 확인 권장. 정밀 검사는 gitleaks ---" >&2 ;;
    esac
fi

[ -n "$warnings" ] && echo "MangoLove gate 경고(비차단):${warnings}" >&2

if [ -n "$failures" ]; then
    # 효능 원장에 차단 기록 (비차단·실패무시 — 게이트 동작을 방해하지 않음)
    rec="$GATE_DIR/efficacy-recorder.sh"
    if [ -f "$rec" ]; then
        read -ra _fk <<< "$failures"
        for _f in "${_fk[@]+"${_fk[@]}"}"; do bash "$rec" record-block gate "$_f" 2>/dev/null || true; done
    fi
    echo "MangoLove gate 차단 — 실패 단계:${failures}" >&2
    echo "  수정 후 재커밋하거나, 부득이하면 MANGOLOVE_SKIP_GATE=1 로 우회(감사됨)." >&2
    [ "$MODE" = "pretooluse" ] && exit 2
    exit 1
fi

exit 0
