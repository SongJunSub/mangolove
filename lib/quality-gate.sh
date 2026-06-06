#!/usr/bin/env bash
# ─────────────────────────────────────────────
# MangoLove — Quality Gate (커밋 경계 결정적 차단 게이트)
#
# init --strict 시 프로젝트의 .mangolove/hooks/quality-gate.sh 로 설치된다.
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

# PreToolUse 모드: stdin 의 JSON 명령을 보고 git commit 일 때만 게이트한다.
# (matcher 가 Bash 전체라, 커밋이 아닌 명령은 즉시 통과시킨다.)
if [ "$MODE" = "pretooluse" ]; then
    input="$(cat)"
    cmd="$(printf '%s' "$input" | grep -oE '"command"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' | head -1)"
    case "$cmd" in
        *git*commit*) : ;;   # 커밋 명령 → 게이트 진행
        *) exit 0 ;;          # 그 외 → 허용
    esac
fi

# 감사되는 우회구 — strict.md 는 우회를 금지하나 물리적으로는 존재한다.
if [ "${MANGOLOVE_SKIP_GATE:-}" = "1" ]; then
    echo "MangoLove gate: MANGOLOVE_SKIP_GATE=1 (게이트 우회 — 감사 대상)" >&2
    exit 0
fi

# shellcheck source=/dev/null
[ -f "$GATE_DIR/gate.conf" ] && . "$GATE_DIR/gate.conf"

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
# 기본은 내장 정규식(이식성·무의존). SECRET_SCANNER=gitleaks 면 gitleaks 사용(설치 시).
# 시크릿은 한 번 커밋되면 코드에서 지워도 회수 불가 — 비가역 표면이라 결정적으로 막는다.
scan_secrets() {
    git rev-parse --git-dir >/dev/null 2>&1 || return 0
    local staged added
    staged="$(git diff --cached --no-color 2>/dev/null)"
    [ -z "$staged" ] && return 0
    if [ "$SECRET_SCANNER" = "gitleaks" ] && command -v gitleaks >/dev/null 2>&1; then
        gitleaks protect --staged --no-banner >/dev/null 2>&1 && return 0
        return 1
    fi
    added="$(printf '%s\n' "$staged" | grep -E '^\+' | grep -vE '^\+\+\+' || true)"
    [ -z "$added" ] && return 0
    printf '%s\n' "$added" | grep -qE 'BEGIN [A-Z ]*PRIVATE KEY' && return 1
    printf '%s\n' "$added" | grep -qE 'AKIA[0-9A-Z]{16}' && return 1
    printf '%s\n' "$added" | grep -qE 'gh[pousr]_[A-Za-z0-9]{36}' && return 1
    printf '%s\n' "$added" | grep -qE 'xox[baprs]-[A-Za-z0-9-]{10,}' && return 1
    printf '%s\n' "$added" | grep -qiE '(secret|api[_-]?key|access[_-]?token|password)[^A-Za-z0-9]{1,4}[A-Za-z0-9/_+.-]{20,}' && return 1
    return 0
}

run_step "lint" "$GATE_LINT" "$LINT_CMD"
run_step "test" "$GATE_TEST" "$TEST_CMD"

if [ "$GATE_SECRET" != "off" ] && ! scan_secrets; then
    if [ "$GATE_SECRET" = "block" ]; then
        failures="${failures} secret"
        echo "--- MangoLove gate: secret 의심 (값은 표시하지 않음) — 노출 시 즉시 회전(rotate) 필요 ---" >&2
    else
        warnings="${warnings} secret"
    fi
fi

[ -n "$warnings" ] && echo "MangoLove gate 경고(비차단):${warnings}" >&2

if [ -n "$failures" ]; then
    echo "MangoLove gate 차단 — 실패 단계:${failures}" >&2
    echo "  수정 후 재커밋하거나, 부득이하면 MANGOLOVE_SKIP_GATE=1 로 우회(감사됨)." >&2
    [ "$MODE" = "pretooluse" ] && exit 2
    exit 1
fi

exit 0
