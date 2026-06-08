#!/usr/bin/env bash
# ─────────────────────────────────────────────
# MangoLove — Efficacy Ledger (Phase 2 / D5)
#
# 방법론(게이트·가드·트랙)이 "실제로 무엇을 잡았나"를 결정적 신호에만 앵커해
# 기록·집계한다. cost/stats(노력·부피)와 달리 효능(무엇을 막았나)을 측정.
#
#   record-block <phase> <kind>  게이트/가드 차단 시 실시간 append (결정적: 게이트 자신의 차단 결정)
#   report                       차단 원장 + 최근 커밋 리스크 분포(impact-score, 결정적) + revert 신호
#
# 저장: ${MANGOLOVE_DIR:-~/.mangolove}/efficacy/<project>.jsonl (로컬 전용)
# 절대원칙: 분자/분모는 HARD 신호(차단 exit code, git diff, git revert)에만 앵커.
# ─────────────────────────────────────────────
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EFF_DIR="${MANGOLOVE_DIR:-$HOME/.mangolove}/efficacy"

# 프로젝트 식별 — 단일 규칙(git toplevel basename)으로 고정(cost-tracker 휴리스틱과 충돌 방지).
_project() {
    local top
    if top="$(git rev-parse --show-toplevel 2>/dev/null)"; then basename "$top"; else echo "_no-git"; fi
}
_ledger() { printf '%s/%s.jsonl' "$EFF_DIR" "$(_project)"; }

# 게이트/가드 차단 1건 기록 (비차단·실패무시 — 게이트 동작을 절대 방해하지 않음)
record_block() {
    mkdir -p "$EFF_DIR" 2>/dev/null || return 0
    local ts p k
    ts="$(date '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || echo '')"
    # JSON 이스케이프 (역슬래시 먼저, 그다음 따옴표) — 향후 명령유래 문자열 호출에도 유효 JSON 보장
    p="${1:-?}"; p="${p//\\/\\\\}"; p="${p//\"/\\\"}"
    k="${2:-?}"; k="${k//\\/\\\\}"; k="${k//\"/\\\"}"
    printf '{"ts":"%s","type":"block","phase":"%s","kind":"%s"}\n' "$ts" "$p" "$k" \
        >> "$(_ledger)" 2>/dev/null || true
}

report() {
    local lg; lg="$(_ledger)"
    echo "방법론 효능 — $(_project)"
    echo ""
    echo "게이트가 막은 것 (결정적, 세션 중 실시간 기록):"
    if [ -f "$lg" ]; then
        # (phase,kind) 결합으로 상호배타 분류 — 버킷합 == 총합 보장
        local sec dng lt tot other
        sec="$(grep -cE '"phase":"gate","kind":"secret"' "$lg" 2>/dev/null)"; sec="${sec:-0}"
        dng="$(grep -cE '"phase":"guard"' "$lg" 2>/dev/null)"; dng="${dng:-0}"
        lt="$(grep -cE '"phase":"gate","kind":"(lint|test)"' "$lg" 2>/dev/null)"; lt="${lt:-0}"
        tot="$(grep -c '"type":"block"' "$lg" 2>/dev/null)"; tot="${tot:-0}"
        other=$((tot - sec - dng - lt)); [ "$other" -lt 0 ] && other=0
        printf '  시크릿 커밋 차단:        %s\n' "$sec"
        printf '  위험/비가역 명령 차단:   %s\n' "$dng"
        printf '  커밋 게이트(lint/test):  %s\n' "$lt"
        [ "$other" -gt 0 ] && printf '  기타 차단:               %s\n' "$other"
        printf '  (총 %s회 게이트/가드 차단 — 재시도 포함, 고유 사고 수 아님)\n' "$tot"
    else
        echo "  (아직 기록 없음 — 막을 게 없었거나 세션 게이트 미활성)"
    fi
    echo ""
    echo "참고 — 최근 mainline 히스토리 리스크 분포 (막은 것 아님; impact-score 커버 스택 한정, --first-parent):"
    local imp="$SELF_DIR/impact-score.sh"
    if [ -f "$imp" ] && git rev-parse --git-dir >/dev/null 2>&1; then
        local n=0 t=0 s=0 m=0 l=0 risky=0 sha j floor
        while IFS= read -r sha; do
            [ -z "$sha" ] && continue
            j="$(bash "$imp" score "$sha" 2>/dev/null)" || continue
            floor="$(printf '%s' "$j" | sed -E 's/.*"track_floor":"([^"]+)".*/\1/')"
            case "$floor" in
                Trivial) t=$((t + 1)) ;;
                Small)   s=$((s + 1)) ;;
                Medium)  m=$((m + 1)) ;;
                Large)   l=$((l + 1)) ;;
            esac
            if printf '%s' "$j" | grep -qE '"(db|auth|ext)":true'; then risky=$((risky + 1)); fi
            n=$((n + 1))
        done < <(git log -n 20 --first-parent --format='%H' 2>/dev/null)
        printf '  점수화된 최근 %s커밋:  Trivial %s / Small %s / Medium %s / Large %s\n' "$n" "$t" "$s" "$m" "$l"
        printf '  인증/DB/외부API 터치: %s건 (무거운 트랙이어야 할 변경)\n' "$risky"
    else
        echo "  (impact-score 미설치 또는 비-git)"
    fi
    echo ""
    echo "참고 — 되돌림(revert) 신호 (결함 무관 롤백 포함 — 효능 측정치 아님, 정밀 결함분류는 후속):"
    if git rev-parse --git-dir >/dev/null 2>&1; then
        local rev
        rev="$(git log -n 200 --format='%s' 2>/dev/null | grep -cE '^Revert ')"; rev="${rev:-0}"
        printf '  최근 200커밋 중 revert: %s건\n' "$rev"
    fi
}

main() {
    case "${1:-}" in
        record-block) shift; record_block "${1:-}" "${2:-}" ;;
        report|"")    report ;;
        *) echo "usage: efficacy-recorder.sh {record-block <phase> <kind>|report}" >&2; exit 2 ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
