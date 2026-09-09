#!/usr/bin/env bash
# ─────────────────────────────────────────────
# MangoLove: Efficacy Ledger (Phase 2 / D5)
#
# 방법론(게이트, 가드, 트랙)이 "실제로 무엇을 잡았나"를 결정적 신호에만 앵커해
# 기록, 집계한다. cost/stats(노력, 부피)와 달리 효능(무엇을 막았나)을 측정.
#
#   record-block <phase> <kind>  게이트/가드 차단 시 실시간 append (결정적: 게이트 자신의 차단 결정)
#   record-skip  <phase> <kind>  게이트가 강제하지 않고 넘긴 시점 (우회, 소유권, 해제 등)
#   report                       차단 원장 + 넘긴 것 + 리스크 분포 + under-triage + revert 신호
#
# 저장: ${MANGOLOVE_DIR:-~/.mangolove}/efficacy/<project>.jsonl (로컬 전용)
# 절대원칙: 분자/분모는 HARD 신호(차단 exit code, git diff, git revert)에만 앵커.
#   차단(block)과 넘김(skip)은 절대 같은 버킷에 넣지 않는다. 통과를 차단으로 세면 효능이
#   부풀고, 부푼 수치로는 게이트가 느슨한지 빡빡한지 판단할 수 없다. 넘김은 따로 센다.
#   under-triage: floor 는 git diff 로 결정적, 분모는 '선언된' 커밋만(미선언은 거짓 통과로
#   세지 않고 coverage 로 분리): 선언 자체는 모델 주장이나 갭의 기준값은 코드가 강제한다.
# ─────────────────────────────────────────────
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EFF_DIR="${MANGOLOVE_DIR:-$HOME/.mangolove}/efficacy"

# 프로젝트 식별: 단일 규칙(git toplevel basename)으로 고정(cost-tracker 휴리스틱과 충돌 방지).
_project() {
    local top
    if top="$(git rev-parse --show-toplevel 2>/dev/null)"; then basename "$top"; else echo "_no-git"; fi
}
_ledger() { printf '%s/%s.jsonl' "$EFF_DIR" "$(_project)"; }

# 원장 1줄 기록 (비차단, 실패무시: 게이트 동작을 절대 방해하지 않음). $1=type $2=phase $3=kind
_record() {
    mkdir -p "$EFF_DIR" 2>/dev/null || return 0
    local ts t p k
    ts="$(date '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || echo '')"
    # JSON 이스케이프 (역슬래시 먼저, 그다음 따옴표): 향후 명령유래 문자열 호출에도 유효 JSON 보장
    t="${1:-?}"
    p="${2:-?}"; p="${p//\\/\\\\}"; p="${p//\"/\\\"}"
    k="${3:-?}"; k="${k//\\/\\\\}"; k="${k//\"/\\\"}"
    printf '{"ts":"%s","type":"%s","phase":"%s","kind":"%s"}\n' "$ts" "$t" "$p" "$k" \
        >> "$(_ledger)" 2>/dev/null || true
}

record_block() { _record block "${1:-}" "${2:-}"; }

# 게이트가 강제할 수 있었으나 넘긴 시점. 차단이 아니므로 차단 집계에 절대 들어가지 않는다.
# 이 눈금이 없으면 "게이트가 얼마나 자주 손을 떼는가"를 볼 방법이 없다.
record_skip() { _record skip "${1:-}" "${2:-}"; }

report() {
    local lg; lg="$(_ledger)"
    echo "방법론 효능, $(_project)"
    echo ""
    echo "게이트가 막은 것 (결정적, 세션 중 실시간 기록):"
    if [ -f "$lg" ]; then
        # (phase,kind) 결합으로 상호배타 분류: 버킷합 == 총합 보장
        local sec dng lt rev bud tot other hard
        # 패턴에 "type":"block" 을 함께 건다: 같은 phase/kind 의 skip 줄이 차단으로 세지면
        # 버킷합 == 총합 이 깨지고, 무엇보다 통과가 차단으로 둔갑한다.
        sec="$(grep -cE '"type":"block","phase":"gate","kind":"secret"' "$lg" 2>/dev/null)"; sec="${sec:-0}"
        dng="$(grep -cE '"type":"block","phase":"guard"' "$lg" 2>/dev/null)"; dng="${dng:-0}"
        lt="$(grep -cE '"type":"block","phase":"gate","kind":"(lint|test)"' "$lg" 2>/dev/null)"; lt="${lt:-0}"
        rev="$(grep -cE '"type":"block","phase":"review"' "$lg" 2>/dev/null)"; rev="${rev:-0}"
        # 리뷰 차단은 사유를 갈라 본다. 둘이 한 숫자면 "엄격해진 커버리지 판정이 오탐 차단을
        # 늘리고 있는가"를 데이터로 답할 수 없고, safe-by-default 가 조용히
        # ignored-by-default(우회 파일 상습 사용)로 바뀌는 것을 놓친다.
        # 하위 분류이므로 rev 에 이미 포함된다. 버킷합에 따로 더하지 않는다.
        local rev_miss rev_scope rev_stale
        rev_miss="$(grep -cE '"type":"block","phase":"review","kind":"missing"' "$lg" 2>/dev/null)"; rev_miss="${rev_miss:-0}"
        rev_scope="$(grep -cE '"type":"block","phase":"review","kind":"scope"' "$lg" 2>/dev/null)"; rev_scope="${rev_scope:-0}"
        rev_stale="$(grep -cE '"type":"block","phase":"review","kind":"stale"' "$lg" 2>/dev/null)"; rev_stale="${rev_stale:-0}"
        # 세션 예산은 exit 2 를 쓰지만 **차단이 아니라 안내**다(Stop 훅에서 모델에 메시지를
        # 전달하는 경로가 exit 2 뿐이라 그 턴을 한 번 붙잡을 뿐이다). 별도 버킷으로 빼고
        # 차단 합계에서 제외한다. 여기 섞으면 장기 세션마다 반복되는 안내가 시크릿/가드
        # 차단과 한 숫자로 합쳐져 효능이 부푼다(이 파일의 절대원칙).
        bud="$(grep -cE '"type":"block","phase":"budget"' "$lg" 2>/dev/null)"; bud="${bud:-0}"
        tot="$(grep -c '"type":"block"' "$lg" 2>/dev/null)"; tot="${tot:-0}"
        other=$((tot - sec - dng - lt - rev - bud)); [ "$other" -lt 0 ] && other=0
        hard=$((tot - bud)); [ "$hard" -lt 0 ] && hard=0
        printf '  시크릿 커밋 차단:        %s\n' "$sec"
        printf '  위험/비가역 명령 차단:   %s\n' "$dng"
        printf '  커밋 게이트(lint/test):  %s\n' "$lt"
        printf '  리뷰 미실행 push 차단:   %s\n' "$rev"
        if [ "$((rev_miss + rev_scope + rev_stale))" -gt 0 ]; then
            printf '    - 스킬이 안 돌았음:    %s\n' "$rev_miss"
            printf '    - 딴 데를 리뷰함:      %s  (이 값이 크면 커버리지 판정이 너무 엄격하다)\n' "$rev_scope"
            printf '    - 보고 나서 더 씀:     %s  (정상. 설계상 가장 흔한 사유다)\n' "$rev_stale"
        fi
        [ "$other" -gt 0 ] && printf '  기타 차단:               %s\n' "$other"
        printf '  (총 %s회 게이트/가드 차단, 재시도 포함, 고유 사고 수 아님)\n' "$hard"
        [ "$bud" -gt 0 ] && printf '  세션 예산 안내:          %s회 (차단 아님, 위 합계에 포함되지 않음)\n' "$bud"
    else
        echo "  (아직 기록 없음, 막을 게 없었거나 세션 게이트 미활성)"
    fi
    echo ""
    echo "게이트가 강제하지 않고 넘긴 것 (차단 아님, 게이트가 손을 떼는 빈도):"
    if [ -f "$lg" ] && grep -q '"type":"skip"' "$lg" 2>/dev/null; then
        grep '"type":"skip"' "$lg" 2>/dev/null \
            | sed -E 's/.*"phase":"([^"]*)","kind":"([^"]*)".*/\1\/\2/' \
            | sort | uniq -c | sort -rn \
            | while read -r c pk; do printf '  %-26s %s\n' "$pk" "$c"; done
    else
        echo "  (기록 없음)"
    fi

    echo ""
    echo "참고, 최근 mainline 히스토리 리스크 분포 (막은 것 아님; impact-score 커버 스택 한정, --first-parent):"
    local imp="$SELF_DIR/impact-score.sh"
    if [ -f "$imp" ] && git rev-parse --git-dir >/dev/null 2>&1; then
        local n=0 t=0 s=0 m=0 l=0 risky=0 declared=0 under=0 sha j floor verdict
        while IFS= read -r sha; do
            [ -z "$sha" ] && continue
            # triage-commit 1회로 floor, 리스크플래그, 선언트랙, verdict 를 함께 얻는다(커밋당 1콜).
            j="$(bash "$imp" triage-commit "$sha" 2>/dev/null)" || continue
            floor="$(printf '%s' "$j" | sed -E 's/.*"track_floor":"([^"]+)".*/\1/')"
            case "$floor" in
                Trivial) t=$((t + 1)) ;;
                Small)   s=$((s + 1)) ;;
                Medium)  m=$((m + 1)) ;;
                Large)   l=$((l + 1)) ;;
            esac
            if printf '%s' "$j" | grep -qE '"(db|auth|ext)":true'; then risky=$((risky + 1)); fi
            # under-triage 집계: 분모는 '선언된' 커밋만(undeclared 는 거짓 통과로 세지 않음)
            verdict="$(printf '%s' "$j" | sed -E 's/.*"verdict":"([^"]+)".*/\1/')"
            case "$verdict" in
                under_triage)   declared=$((declared + 1)); under=$((under + 1)) ;;
                ok|over_triage) declared=$((declared + 1)) ;;
            esac
            n=$((n + 1))
        done < <(git log -n 20 --first-parent --format='%H' 2>/dev/null)
        printf '  점수화된 최근 %s커밋:  Trivial %s / Small %s / Medium %s / Large %s\n' "$n" "$t" "$s" "$m" "$l"
        printf '  인증/DB/외부API 터치: %s건 (무거운 트랙이어야 할 변경)\n' "$risky"
        echo ""
        echo "참고, 트랙 under-triage (선언 트랙 < 코드 floor; 선언은 자기보고, floor는 git diff 결정적):"
        echo "  (분모=선언된 커밋만; --first-parent 기준이라 merge-커밋으로 들어온 선언은 미집계)"
        if [ "$declared" -gt 0 ]; then
            # 커버리지를 명시적으로: '미선언 N건은 측정 대상 외'로 오독(높은 선언율로 위장) 차단
            printf '  선언 커버리지: %s커밋 중 %s건 선언 (%s%%), 미선언 %s건은 측정 대상 외\n' \
                "$n" "$declared" "$(( declared * 100 / n ))" "$(( n - declared ))"
            # 소표본에서 오해를 부르는 단독 %% 대신 raw 분수를 1급으로: 선언 D건 중 U건
            if [ "$under" -gt 0 ]; then
                printf '  under-triage: 선언 %s건 중 %s건, 선언보다 무거운 트랙 필요(Spec/리뷰 누락 신호)\n' "$declared" "$under"
            else
                printf '  under-triage: 선언 %s건 중 0건, 선언 트랙 모두 floor 이상\n' "$declared"
            fi
        else
            echo "  (선언된 커밋 없음, Change-Track: trailer 미사용; coverage 0, 측정 불가)"
        fi
    else
        echo "  (impact-score 미설치 또는 비-git)"
    fi
    echo ""
    echo "참고, 되돌림(revert) 신호 (결함 무관 롤백 포함, 효능 측정치 아님, 정밀 결함분류는 후속):"
    if git rev-parse --git-dir >/dev/null 2>&1; then
        local rev
        rev="$(git log -n 200 --format='%s' 2>/dev/null | grep -cE '^Revert ')"; rev="${rev:-0}"
        printf '  최근 200커밋 중 revert: %s건\n' "$rev"
    fi
}

main() {
    case "${1:-}" in
        record-block) shift; record_block "${1:-}" "${2:-}" ;;
        record-skip)  shift; record_skip  "${1:-}" "${2:-}" ;;
        report|"")    report ;;
        *) echo "usage: efficacy-recorder.sh {record-block <phase> <kind>|record-skip <phase> <kind>|report}" >&2; exit 2 ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
