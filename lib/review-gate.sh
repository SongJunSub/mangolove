#!/usr/bin/env bash
# ─────────────────────────────────────────────
# MangoLove — Review gate (트랙별 필수 리뷰의 결정적 강제)
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
# 트랙이 Trivial/Small 이면 아무 것도 요구하지 않는다 — 사소한 변경에 무거운 절차를
# 씌우지 않는 것이 이 게이트의 절반이다(과대 판정도 실패다).
#
# 계약:
#   review-gate.sh record       stdin=PostToolUse JSON. 항상 exit 0 (게이트가 작업을 막지 않는다).
#   review-gate.sh pretooluse   stdin=PreToolUse JSON. 통과 exit 0 / 차단 exit 2.
#   review-gate.sh required <track> <db> <auth> <ext>   필수 스킬 목록 출력 — 정책 단일 출처.
#   review-gate.sh status [ref] 사람용: 계산된 트랙 + 원장 + 부족분.
#
# 우회(감사됨): MANGOLOVE_SKIP_REVIEW=1
# 비활성: MANGOLOVE_REVIEW_GATE=off (훅 자체가 주입되지 않음)
# ─────────────────────────────────────────────
set -uo pipefail

GATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMPACT="$GATE_DIR/impact-score.sh"
LEDGER_REL=".mangolove/.review-ledger"

# .mangolove/ 는 프로젝트가 버전관리할 수도 있는 디렉토리다(.mangolove/hooks/ 는 감사 대상).
# 그러니 통째로 무시하지 않고, 게이트가 만드는 **일시 파일만** 자기 자신을 무시하게 한다.
# 이게 없으면 게이트를 켠 모든 레포에서 사용자가 손으로 .gitignore 를 고쳐야 한다.
_ml_seed_gitignore() {
    local d="./.mangolove"
    [ -d "$d" ] || return 0
    [ -f "$d/.gitignore" ] && return 0
    {
        echo "# MangoLove 게이트의 일시 상태 (자동 생성). 레포 내용이 아니다."
        echo "dod.sh"
        echo ".dod-gate-attempts"
        echo ".review-ledger"
    } > "$d/.gitignore" 2>/dev/null || true
}


# ── stdin JSON 에서 문자열 필드 하나를 꺼낸다 (jq 비의존 — 다른 게이트와 같은 방식).
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

# 플러그인 스킬은 "<plugin>:<skill>" 로 들어온다(code-review:code-review).
# 마지막 콜론 뒤만 취해 내장/플러그인 경로를 같은 이름으로 취급한다.
_normalize_skill() { printf '%s' "${1##*:}"; }

# JSON 1줄에서 스칼라 필드 하나 (문자열/불리언 공용).
_json_field() { printf '%s' "$1" | sed -E "s/.*\"$2\":\"?([^,\"}]+)\"?.*/\1/"; }

# ── 정책 단일 출처 ──────────────────────────────────────────────
# 트랙별 필수 리뷰. strict.md 의 표와 이 함수가 어긋나면 tests/review-gate.bats 가 RED.
#   Trivial / Small : 없음 (셀프 리뷰는 산문 규율로 충분 — 게이트를 걸지 않는다)
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
    local input skill
    input="$(cat)"
    _cd_to_hook_cwd "$input"
    skill="$(_json_str "$input" skill_name)"
    [ -z "$skill" ] && exit 0
    skill="$(_normalize_skill "$skill")"
    mkdir -p "$(dirname "$LEDGER_REL")" 2>/dev/null || exit 0
    _ml_seed_gitignore
    printf '%s\n' "$skill" >> "$LEDGER_REL" 2>/dev/null || true
    exit 0
}

# ── 변경을 분석해 전역에 채운다. **명령치환으로 호출하지 않는다** — 서브셸이면 전역이 안 남는다.
#    반환 1 = impact 계산 실패(비-git 등) → 호출자는 fail-open 한다.
REVIEW_TRACK=""; REVIEW_JSON=""; REVIEW_REQUIRED=""; REVIEW_MISSING=""
_analyze() {
    local ref="$1" json track db auth ext s missing=""
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
    local input cmd ref s rec
    input="$(cat)"
    cmd="$(_json_str "$input" command)"

    # git 을 단어 경계로 잡고 옵션 토큰을 건너뛴 뒤 commit 서브커맨드만 매칭한다
    # (quality-gate.sh 와 같은 규칙 — git log --grep=commit 같은 비커밋은 통과).
    printf '%s' "$cmd" | grep -qE '(^|[^[:alnum:]_])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-][^[:space:]]*)?)*[[:space:]]+commit([[:space:]]|$)' || exit 0

    _cd_to_hook_cwd "$input"
    git rev-parse --git-dir >/dev/null 2>&1 || exit 0

    if [ "${MANGOLOVE_SKIP_REVIEW:-}" = "1" ]; then
        echo "MangoLove review gate: MANGOLOVE_SKIP_REVIEW=1 (게이트 우회 — 감사 대상)" >&2
        exit 0
    fi

    # commit -a/--all 은 tracked 변경을 자동 스테이징하므로 판정 범위를 워킹트리로 넓힌다.
    ref="--staged"
    if printf '%s' "$cmd" | grep -qE 'commit[[:space:]]+(-[a-zA-Z]*a|--all)'; then ref="--working"; fi

    # impact 계산 실패는 fail-open — 게이트가 작업을 인질로 잡지 않는다.
    _analyze "$ref" || exit 0

    if [ -z "$REVIEW_MISSING" ]; then
        # 통과 — 원장을 소비한다. 다음 커밋은 자기 diff 에 대한 리뷰를 새로 요구한다.
        rm -f "$LEDGER_REL" 2>/dev/null || true
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
        echo "**커밋 전에** 사용자에게 물으세요. 부득이한 우회(감사됨): MANGOLOVE_SKIP_REVIEW=1"
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
    echo "Review gate — ${ref}"
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
        echo "  판정: BLOCK — 부족: ${REVIEW_MISSING}"
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
