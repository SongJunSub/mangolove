#!/usr/bin/env bash
# ─────────────────────────────────────────────
# MangoLove: Review gate (트랙별 필수 리뷰의 결정적 강제)
#
# 왜 존재하나: 방법론은 Medium 이상 변경에 리뷰 단계를 요구하지만 그 요구는 산문이라
# 확률적으로만 지켜졌다. 실제 관측된 실패 모드는 "트랙을 선언하고 → 리뷰를 생략하고 →
# 사후에 고백하며 → 지금 돌릴까요라고 되묻는" 것이다. 사용자가 요청한 적 없는 결정을
# 사후에 떠넘기는, 가능한 선택지 중 최악이다.
# strict.md 의 신뢰성 게이트 원칙("강제 표현이 잦은 규칙은 hook 으로 옮겨라")을 리뷰
# 의무에 적용해, 커밋 경계에서 코드가 결정한다.
#
# 두 개의 훅으로 동작한다 (bare mangolove 세션에 claude --settings 로 주입):
#   PostToolUse(matcher=Skill) → review-gate.sh record
#       실제로 실행된 스킬만 원장에 남는다. 모델의 자기보고가 아니라 도구 호출 사실이다.
#   PreToolUse(matcher=Bash)   → review-gate.sh pretooluse
#       git commit 일 때만 발화. staged 변경의 track_floor 를 impact-score.sh 로 계산해
#       필수 리뷰가 원장에 있는지 대조하고, 없으면 커밋을 차단(exit 2)한다.
#
# 트랙이 Trivial/Small 이면 아무 것도 요구하지 않는다: 사소한 변경에 무거운 절차를
# 씌우지 않는 것이 이 게이트의 절반이다(과대 판정도 실패다).
#
# 계약:
#   review-gate.sh record       stdin=PostToolUse JSON. 항상 exit 0 (게이트가 작업을 막지 않는다).
#   review-gate.sh pretooluse   stdin=PreToolUse JSON. 통과 exit 0 / 차단 exit 2.
#   review-gate.sh required <track> <db> <auth> <ext>   필수 스킬 목록 출력: 정책 단일 출처.
#   review-gate.sh status [ref] 사람용: 계산된 트랙 + 원장 + 부족분.
#
# 우회(감사됨): .mangolove/.review-skip 파일(1회용, 세션 도중 가능)
#               또는 mangolove 실행 전에 export 한 MANGOLOVE_SKIP_REVIEW=1
#               (훅은 Claude Code 프로세스 환경에서 뜨므로 명령 앞 VAR=1 은 닿지 않는다)
# 비활성: MANGOLOVE_REVIEW_GATE=off (훅 자체가 주입되지 않음)
# ─────────────────────────────────────────────
set -uo pipefail

GATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMPACT="$GATE_DIR/impact-score.sh"
LEDGER_REL=".mangolove/.review-ledger"
# 원장이 어느 HEAD 위에서 만들어졌는지 기록한다. 커밋이 성공해 HEAD 가 움직이면 원장은
# 낡은 것이 되고, 다음 커밋은 자기 diff 에 대한 리뷰를 새로 요구한다.
# 통과 시점에 원장을 지우지 **않는** 이유: PreToolUse 는 커밋 성공을 알 수 없다. 같은
# 훅 목록의 시크릿 게이트가 커밋을 막아도 이 훅은 이미 돌았으므로, 통과 시 지우면
# 시크릿을 고치고 재시도할 때 리뷰를 다시 요구하게 된다(리뷰는 이미 했는데).
LEDGER_BASE_REL=".mangolove/.review-ledger.base"
# 세션 도중 쓸 수 있는 1회용 우회 파일. 환경변수 우회는 훅에 닿지 않기 때문에 필요하다.
SKIP_REL=".mangolove/.review-skip"

# .mangolove/ 는 프로젝트가 버전관리할 수도 있는 디렉토리다(.mangolove/hooks/ 는 감사 대상).
# 그러니 통째로 무시하지 않고, 게이트가 만드는 **일시 파일만** 자기 자신을 무시하게 한다.
# 이게 없으면 게이트를 켠 모든 레포에서 사용자가 손으로 .gitignore 를 고쳐야 한다.
# (dod-gate.sh 에 같은 함수가 있다. 훅 스크립트는 서로를 source 하지 않는다: 한 파일이
#  없거나 깨져도 다른 게이트가 같이 죽지 않게 하는 기존 설계를 따른다.)
_ml_seed_gitignore() {
    local d="./.mangolove"
    [ -d "$d" ] || return 0
    [ -f "$d/.gitignore" ] && return 0
    {
        echo "# MangoLove 게이트의 일시 상태 (자동 생성). 레포 내용이 아니다."
        echo "# 이 파일 자신도 무시한다. 게이트가 어느 머신에서든 다시 만든다."
        echo ".gitignore"
        echo "dod.sh"
        echo ".dod-gate-attempts"
        echo ".review-ledger"
        echo ".review-ledger.base"
        echo ".review-skip"
    } > "$d/.gitignore" 2>/dev/null || true
}


# ── stdin JSON 에서 문자열 필드 하나를 꺼낸다 (jq 비의존: 다른 게이트와 같은 방식).
_json_str() {
    local input="$1" key="$2" raw
    raw="$(printf '%s' "$input" | grep -oE "\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"\\\\]|\\\\.)*\"" | head -1)"
    [ -z "$raw" ] && return 0
    raw="${raw#*:}"
    raw="${raw#*\"}"
    printf '%s' "${raw%\"}"
}

# 훅은 다른 cwd 에서 실행될 수 있으므로 stdin 의 cwd 로 이동해 프로젝트를 정확히 식별한다.
_cd_to_hook_cwd() {
    local c; c="$(_json_str "$1" cwd)"
    if [ -n "$c" ] && [ -d "$c" ]; then cd "$c" 2>/dev/null || true; fi
}

# tool_input.command 는 JSON 문자열이라 개행이 역슬래시+n 두 글자로 온다. 그대로 정규식에
# 태우면 둘째 줄 git 앞 글자가 'n'(영숫자)이라 단어 경계에 걸리지 않고, 멀티라인 명령이
# 통째로 게이트를 빠져나간다(실측: 이 머신의 실제 커밋 호출 411건 중 84건, 20%).
# 실제 개행으로 되돌린 뒤 grep 이 줄 단위로 보게 한다.
_unescape_cmd() { printf '%s' "$1" | awk '{gsub(/\\n/,"\n"); gsub(/\\t/," "); print}'; }

# git 을 단어 경계로 잡고 옵션 토큰을 건너뛴 뒤 commit 서브커맨드만 매칭한다
# (git log --grep=commit 같은 비커밋은 통과). 매칭된 줄을 출력한다.
GIT_COMMIT_RE='(^|[^[:alnum:]_])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-][^[:space:]]*)?)*[[:space:]]+commit([[:space:]]|$)'
_commit_line() { printf '%s\n' "$1" | grep -E "$GIT_COMMIT_RE" | head -1; }

# 플러그인 스킬은 "<plugin>:<skill>" 로 들어온다(code-review:code-review).
# 마지막 콜론 뒤만 취해 내장/플러그인 경로를 같은 이름으로 취급한다.
_normalize_skill() { printf '%s' "${1##*:}"; }

# JSON 1줄에서 스칼라 필드 하나 (문자열/불리언 공용).
_json_field() { printf '%s' "$1" | sed -E "s/.*\"$2\":\"?([^,\"}]+)\"?.*/\1/"; }

_head_sha() { git rev-parse HEAD 2>/dev/null || echo "_no-head"; }

# 원장의 유효 범위를 한 줄로 적는다: "<session_id>\t<head_sha>".
# HEAD 가 움직였으면(= 커밋이 성공했으면) 그 리뷰는 이미 소진된 것이고,
# 세션이 바뀌었으면 어제 돌린 리뷰가 오늘의 첫 커밋을 통과시키면 안 된다.
# session 인자가 비면 세션 비교를 건너뛴다(터미널에서 status 를 볼 때).
_ledger_stamp() { printf '%s\t%s' "${1:-}" "$(_head_sha)"; }

_drop_stale_ledger() {
    local session="${1:-}"
    [ -f "$LEDGER_REL" ] || return 0
    local base="" b_session b_head
    [ -f "$LEDGER_BASE_REL" ] && base="$(cat "$LEDGER_BASE_REL" 2>/dev/null)"
    b_session="${base%%	*}"
    b_head="${base##*	}"
    if [ "$b_head" = "$(_head_sha)" ]; then
        [ -z "$session" ] && return 0
        [ "$b_session" = "$session" ] && return 0
    fi
    rm -f "$LEDGER_REL" "$LEDGER_BASE_REL" 2>/dev/null || true
}

# ── 정책 단일 출처 ──────────────────────────────────────────────
# 트랙별 필수 리뷰. strict.md 의 표와 이 함수가 어긋나면 tests/review-gate.bats 가 RED.
#   Trivial / Small : 없음 (셀프 리뷰는 산문 규율로 충분: 게이트를 걸지 않는다)
#   Medium          : simplify + code-review
#   Large           : simplify + code-review + security-review
#   + DB/인증/외부API 신호가 있으면 트랙과 무관하게 security-review 추가
required_skills() {
    local track="$1" db="${2:-false}" auth="${3:-false}" ext="${4:-false}" out=""
    case "$track" in
        Medium) out="simplify code-review" ;;
        Large)  out="simplify code-review security-review" ;;
        *)      return 0 ;;
    esac
    if [ "$db" = "true" ] || [ "$auth" = "true" ] || [ "$ext" = "true" ]; then
        case " $out " in
            *" security-review "*) : ;;
            *) out="$out security-review" ;;
        esac
    fi
    printf '%s' "$out"
}

# ── record: 실행된 스킬을 원장에 append (PostToolUse). 절대 실패로 turn 을 막지 않는다.
do_record() {
    local input skill session
    input="$(cat)"
    _cd_to_hook_cwd "$input"
    # 필드 이름은 런타임에서 실측했다: Skill 도구의 tool_input 은 {"skill":"simplify"} 다.
    # 훅 문서는 skill_name 이라고 적고 있어 양쪽을 다 받는다: 한쪽만 읽고 맞췄다가는
    # 원장이 영영 비어 Medium 이상 커밋이 전부 막힌다(경계면 교차검증).
    # 두 패턴은 서로 오탐하지 않는다: "skill" 뒤에 곧바로 콜론이 와야 매칭된다.
    session="$(_json_str "$input" session_id)"
    skill="$(_json_str "$input" skill)"
    [ -z "$skill" ] && skill="$(_json_str "$input" skill_name)"
    [ -z "$skill" ] && exit 0
    skill="$(_normalize_skill "$skill")"
    mkdir -p "$(dirname "$LEDGER_REL")" 2>/dev/null || exit 0
    _ml_seed_gitignore
    _drop_stale_ledger "$session"
    [ -f "$LEDGER_REL" ] || _ledger_stamp "$session" > "$LEDGER_BASE_REL" 2>/dev/null || true
    # 같은 스킬을 여러 번 호출해도 한 줄만 남긴다: 원장은 집합이지 호출 로그가 아니다.
    grep -qxF "$skill" "$LEDGER_REL" 2>/dev/null || printf '%s\n' "$skill" >> "$LEDGER_REL" 2>/dev/null || true
    exit 0
}

# ── 변경을 분석해 전역에 채운다. **명령치환으로 호출하지 않는다**: 서브셸이면 전역이 안 남는다.
#    반환 1 = impact 계산 실패(비-git 등) → 호출자는 fail-open 한다.
REVIEW_TRACK=""; REVIEW_JSON=""; REVIEW_REQUIRED=""; REVIEW_MISSING=""
_analyze() {
    local ref="$1" session="${2:-}" json track db auth ext s missing=""
    _drop_stale_ledger "$session"
    json="$(bash "$IMPACT" score "$ref" 2>/dev/null)" || return 1
    [ -z "$json" ] && return 1
    track="$(printf '%s' "$json" | sed -E 's/.*"track_floor":"([^"]+)".*/\1/')"
    db="$(_json_field "$json" db)"
    auth="$(_json_field "$json" auth)"
    ext="$(_json_field "$json" ext)"
    REVIEW_JSON="$json"
    REVIEW_TRACK="$track"
    REVIEW_REQUIRED="$(required_skills "$track" "$db" "$auth" "$ext")"
    for s in $REVIEW_REQUIRED; do
        grep -qxF "$s" "$LEDGER_REL" 2>/dev/null || missing="$missing $s"
    done
    REVIEW_MISSING="${missing# }"
    return 0
}

# ── pretooluse: git commit 경계에서만 게이트.
do_pretooluse() {
    local input cmd line after ref s rec
    input="$(cat)"
    cmd="$(_unescape_cmd "$(_json_str "$input" command)")"

    line="$(_commit_line "$cmd")"
    [ -n "$line" ] || exit 0

    _cd_to_hook_cwd "$input"
    git rev-parse --git-dir >/dev/null 2>&1 || exit 0

    if [ "${MANGOLOVE_SKIP_REVIEW:-}" = "1" ]; then
        echo "MangoLove review gate: MANGOLOVE_SKIP_REVIEW=1 (게이트 우회, 감사 대상)" >&2
        exit 0
    fi
    # 환경변수 우회는 mangolove 실행 **전에** export 돼 있어야 한다. 훅은 Claude Code
    # 프로세스의 환경에서 뜨므로, 명령 앞에 붙인 VAR=1 은 훅에 닿지 않는다. 세션 도중
    # 우회해야 할 때를 위해 에이전트가 직접 쓸 수 있는 파일 경로를 둔다(1회용, 감사됨).
    if [ -f "$SKIP_REL" ]; then
        rm -f "$SKIP_REL" 2>/dev/null || true
        echo "MangoLove review gate: .mangolove/.review-skip 으로 1회 우회 (감사 대상)" >&2
        rec="$GATE_DIR/efficacy-recorder.sh"
        if [ -f "$rec" ]; then bash "$rec" record-block review "bypassed" 2>/dev/null || true; fi
        exit 0
    fi

    # commit -a/--all 은 tracked 변경을 자동 스테이징하므로 판정 범위를 워킹트리로 넓힌다.
    # 플래그가 commit 바로 뒤에 없어도(예: git commit -m msg -a) 잡아야 한다. 커밋 메시지
    # 안의 " -a " 를 오탐하면 범위가 넓어질 뿐이라 안전한 방향으로 틀린다.
    ref="--staged"
    after="${line#*commit}"
    if printf '%s' "$after" | grep -qE '(^|[[:space:]])(--all|-[a-zA-Z]*a[a-zA-Z]*)([[:space:]]|$)'; then ref="--working"; fi

    # impact 계산 실패는 fail-open: 게이트가 작업을 인질로 잡지 않는다.
    _analyze "$ref" "$(_json_str "$input" session_id)" || exit 0

    if [ -z "$REVIEW_MISSING" ]; then
        # 통과. 원장은 여기서 지우지 않는다: 커밋이 실제로 성공했는지 알 수 없기 때문이다.
        # 커밋이 성공하면 HEAD 가 움직이고, 그때 _drop_stale_ledger 가 버린다.
        if [ -n "$REVIEW_REQUIRED" ]; then
            echo "MangoLove review gate: ${REVIEW_TRACK} 필수 리뷰 충족 (${REVIEW_REQUIRED})" >&2
        fi
        exit 0
    fi

    {
        echo "--- MangoLove review gate: 커밋 차단 ---"
        echo "이 변경의 트랙은 코드가 계산했습니다(모델 추정 아님): ${REVIEW_TRACK}"
        echo "  ${REVIEW_JSON}"
        echo ""
        echo "${REVIEW_TRACK} 트랙에 필요한 리뷰 중 이 세션에서 실행되지 않은 것:"
        for s in $REVIEW_MISSING; do echo "  - /${s}"; done
        echo ""
        echo "생략을 사후에 보고하지 말고 실행하세요. 과하다고 판단되면 실행하는 대신"
        echo "**커밋 전에** 사용자에게 물으세요."
        echo "부득이한 1회 우회(감사됨): touch .mangolove/.review-skip 후 다시 커밋"
        echo "(MANGOLOVE_SKIP_REVIEW=1 은 mangolove 실행 전에 export 돼 있어야 합니다."
        echo " 명령 앞에 붙인 값은 훅에 닿지 않습니다.)"
    } >&2

    rec="$GATE_DIR/efficacy-recorder.sh"
    if [ -f "$rec" ]; then bash "$rec" record-block review "missing" 2>/dev/null || true; fi
    exit 2
}

# ── status: 사람용 진단.
do_status() {
    local ref="${1:---working}"
    if ! _analyze "$ref"; then
        echo "review-gate: impact 계산 실패 (git 저장소인지 확인)" >&2; exit 1
    fi
    echo "Review gate: ${ref}"
    echo "  계산된 트랙: ${REVIEW_TRACK}"
    echo "  필수 리뷰: ${REVIEW_REQUIRED:-(없음)}"
    if [ -f "$LEDGER_REL" ]; then
        echo "  이번 세션 실행 스킬: $(tr '\n' ' ' < "$LEDGER_REL")"
    else
        echo "  이번 세션 실행 스킬: (없음)"
    fi
    if [ -z "$REVIEW_MISSING" ]; then
        echo "  판정: PASS"
    else
        echo "  판정: BLOCK, 부족: ${REVIEW_MISSING}"
    fi
}

main() {
    case "${1:-}" in
        record)     do_record ;;
        pretooluse) do_pretooluse ;;
        required)   required_skills "${2:-}" "${3:-false}" "${4:-false}" "${5:-false}"; echo ;;
        status)     do_status "${2:---working}" ;;
        *) echo "usage: review-gate.sh {record|pretooluse|required <track> <db> <auth> <ext>|status [ref]}" >&2; exit 2 ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
