#!/usr/bin/env bash
# ─────────────────────────────────────────────
# MangoLove — Methodology Audit (컨텍스트 파일 전수 감사)
#
# 방법론 파일은 단조 증가하기 쉽다. 줄이 늘수록 개별 지시의 효력은 희석되는데,
# "어떤 줄이 값을 못 내고 있는가"를 볼 방법이 없으면 삭제 결정을 내릴 수 없다.
# 이 명령은 삭제 판단에 필요한 결정적 수치만 산출하고, 판정은 세션(LLM)에 넘긴다.
#
#   report (기본)  섹션별 부피·강제표현 밀도·최종수정일 + 게이트 발동 0건 + 감사 프롬프트
#
# LLM 위임 경계: 수치는 전부 코드가 계산한다(HARD 신호 앵커 — 부피는 wc, 발동은 efficacy
#   원장의 차단 기록, 최종수정일은 git blame). 합성 점수(가중치 곱한 '위험도' 따위)는
#   만들지 않는다 — 근거 없는 정밀도는 삭제 결정을 오히려 흐린다.
# 읽기 전용: 어떤 파일도 쓰지 않는다.
# ─────────────────────────────────────────────
set -uo pipefail

AUDIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$AUDIT_DIR/.." && pwd)"
SRC="${MANGOLOVE_METHODOLOGY_SRC:-$ROOT/methodology/strict.md}"
CORE="$ROOT/methodology/core.md"

# efficacy 원장의 경로 규칙(git toplevel basename)을 다시 구현하지 않고 그대로 빌려 쓴다.
# shellcheck source=lib/efficacy-recorder.sh
[ -f "$AUDIT_DIR/efficacy-recorder.sh" ] && . "$AUDIT_DIR/efficacy-recorder.sh"

_fmt_kb() { awk -v c="$1" 'BEGIN{printf "%.1fKB", c/1024}'; }

# 섹션별 blame 최신 author-time — git 호출 1회로 전 줄을 얻는다(섹션당 호출 금지).
_blame_times() {
    # git 루트는 ROOT 가 아니라 SRC 자신의 위치에서 찾는다 — SRC 가 override 됐을 때
    # ROOT 기준으로 blame 하면 '레포 밖 경로'로 조용히 실패한다.
    local d; d="$(dirname "$SRC")"
    git -C "$d" rev-parse --git-dir >/dev/null 2>&1 || return 0
    git -C "$d" blame --line-porcelain -- "$SRC" 2>/dev/null | awk '
        /^\^?[0-9a-f]{39,40} [0-9]+ [0-9]+/ { line=$3; next }
        /^author-time / { if (line) print line, $2 }
    '
}

section_table() {
    local blame; blame="$(mktemp)"
    _blame_times > "$blame" 2>/dev/null
    local now; now="$(date +%s)"

    # 폭 고정 컬럼(ASCII 숫자)을 앞에, 가변폭 제목(한글)을 맨 뒤에 둔다.
    # printf 의 %-Ns 는 바이트를 세므로 한글 제목을 패딩하면 정렬이 깨진다 — 패딩하지 않는 배치로 회피.
    # 첫 파일 판별을 FNR==NR 로 하면 blame 이 비었을 때(비-git) 두 번째 파일이 첫 파일로
    # 오인돼 표 전체가 사라진다. 파일명으로 판별한다.
    awk -v now="$now" -v blamefile="$blame" '
        FILENAME == blamefile { bt[$1]=$2; next }
        {
            # 펜스(```/~~~) 안의 "## ..." 은 Spec·.progress.md 템플릿 예시지 실제 섹션이 아니다.
            if ($0 ~ /^(```|~~~)/) { fence = !fence }
            else if (!fence && $0 ~ /^## /) { sec++; title[sec]=substr($0,4) }
            s = sec + 0
            if (!(s in title)) title[s]="(머리말)"
            lines[s]++
            n = gsub(/반드시|필수|절대|금지|항상|MUST/, "&")
            imp[s] += n
            if (bt[FNR] + 0 > last[s] + 0) last[s] = bt[FNR] + 0
        }
        END {
            printf "  %6s %8s %10s   %s\n", "줄수", "강제표현", "최종수정", "섹션"
            printf "  %s\n", "─────────────────────────────────────────────────────────────"
            tot=0; totimp=0
            for (i=0; i<=sec; i++) {
                if (!(i in lines)) continue
                age = (last[i] > 0) ? int((now - last[i]) / 86400) "일 전" : "-"
                printf "  %6d %8d %10s   %s\n", lines[i], imp[i], age, title[i]
                tot += lines[i]; totimp += imp[i]
            }
            printf "  %s\n", "─────────────────────────────────────────────────────────────"
            printf "  %6d %8d %10s   %s\n", tot, totimp, "", "합계"
            if (fence) printf "  ! 코드 펜스가 홀수개입니다 — 섹션 경계가 부정확할 수 있습니다.\n"
        }
    ' "$blame" "$SRC"
    rm -f "$blame"
}

volume() {
    local sl sc cl cc mode
    sl="$(wc -l < "$SRC" | tr -d ' ')"; sc="$(wc -c < "$SRC" | tr -d ' ')"
    mode="${MANGOLOVE_METHODOLOGY_MODE:-monolith}"
    printf '  현재 전달 모드: %s\n' "$mode"
    printf '  strict.md (monolith 주입): %s줄 / %s / ≈%d~%d 토큰\n' \
        "$sl" "$(_fmt_kb "$sc")" "$((sc / 2))" "$((sc * 10 / 16))"
    if [ -f "$CORE" ] && [ "$sc" -gt 0 ]; then
        cl="$(wc -l < "$CORE" | tr -d ' ')"; cc="$(wc -c < "$CORE" | tr -d ' ')"
        printf '  core.md   (split 주입)   : %s줄 / %s / ≈%d~%d 토큰  (monolith 대비 %d%% 감소)\n' \
            "$cl" "$(_fmt_kb "$cc")" "$((cc / 2))" "$((cc * 10 / 16))" "$(( (sc - cc) * 100 / sc ))"
    fi
    echo "  (토큰은 문자수/2.0 ~ /1.6 근사 — 실측치 아님. 실제 점유는 statusline 의 context% 참조)"
}

gate_activity() {
    local lg=""
    command -v _ledger >/dev/null 2>&1 && lg="$(_ledger 2>/dev/null)"
    # 게이트 phase 우주는 호출부에서 파생한다 — 여기에 목록을 적어두면 두 번째 진실 출처가 된다.
    local phases p n silent=""
    phases="$(grep -rhoE 'record-block [a-z-]+' "$ROOT/lib" 2>/dev/null | awk '{print $2}' | sort -u)"
    if [ -z "$phases" ]; then echo "  (record-block 호출부 없음 — 게이트 미배선)"; return 0; fi
    # 원장은 현재 프로젝트 기준(mangolove efficacy 와 동일 범위). '발동 0건'을 '규칙이 무용'으로
    # 읽으려면 기록 기간이 충분한지부터 봐야 하므로 기간을 함께 낸다 — 감사 프롬프트가 요구하는 정보.
    if [ -n "$lg" ] && [ -f "$lg" ]; then
        local first last
        first="$(head -1 "$lg" | sed -E 's/.*"ts":"([^"]*)".*/\1/')"
        last="$(tail -1 "$lg" | sed -E 's/.*"ts":"([^"]*)".*/\1/')"
        printf '  기록 기간: %s ~ %s (현재 프로젝트 원장)\n' "${first:-?}" "${last:-?}"
    else
        echo "  기록 기간: (원장 없음 — 이 프로젝트에서 게이트가 아직 한 번도 차단하지 않음)"
    fi
    for p in $phases; do
        n=0
        [ -n "$lg" ] && [ -f "$lg" ] && n="$(grep -c "\"phase\":\"$p\"" "$lg" 2>/dev/null)"
        n="${n:-0}"
        printf '  %-12s %s회\n' "$p" "$n"
        [ "$n" -eq 0 ] && silent="$silent $p"
    done
    if [ -n "$silent" ]; then
        printf '  → 발동 0건:%s — 방법론이 이 구간에서 아직 값을 내지 못했다.\n' "$silent"
        echo "    (아직 위험 작업을 안 했거나 / 게이트 미활성 / 규칙이 실효 없음 — 셋을 구분해서 판단할 것)"
    fi
}

audit_prompt() {
    cat <<'PROMPT'
  위 수치를 근거로 각 섹션을 다음 세 가지로 분류하고, 분류마다 근거를 한 줄로 달아라.

    A) 삭제 후보 — 에이전트가 코드베이스를 뒤져 스스로 알아낼 수 있는 정보이거나,
       실제로 행동을 바꾼 적이 없는 줄. (구조·설치된 패키지·기존 코드 스타일 설명 등)
    B) 유지 — 이해는 하지만 지시가 없으면 기본값으로 하지 않는 행동. (Type 2)
       이것이 방법론의 본체다. 부피가 커도 삭제 대상이 아니다.
    C) 코드로 이관 — 강제 표현 밀도가 높은데 검증이 프롬프트 어조에만 의존하는 줄.
       hook / CI required check / 검증 스크립트로 옮기면 프롬프트에서 뺄 수 있다.

  판정 규칙:
  - 부피가 크다는 이유만으로 A 로 보내지 않는다. 근거는 '발동 여부'이지 '길이'가 아니다.
  - 발동 0건이라도 아직 해당 상황이 없었을 뿐일 수 있다 — 원장 기간을 확인하고 판단한다.
  - C 로 분류했으면 옮길 대상(어떤 hook / 어떤 체크)까지 지목한다. 지목 못 하면 B 다.
  - 최종 출력은 "삭제 N줄 / 이관 N줄" 회수량 추정으로 닫는다.

  방법론 파일은 직접 수정하지 않는다. 제안까지만 하고 사용자 승인 후 별도 사이클로 반영한다.
PROMPT
}

report() {
    if [ ! -f "$SRC" ]; then
        echo "audit-methodology: 방법론 파일을 찾을 수 없습니다: $SRC" >&2
        return 1
    fi
    echo "방법론 감사 — $(basename "$SRC")"
    echo ""
    echo "주입 부피:"
    volume
    echo ""
    echo "섹션별 부피 · 강제표현 밀도 · 최종수정 (강제표현이 많을수록 코드 이관 후보):"
    section_table
    echo ""
    echo "게이트 발동 (efficacy 원장, 결정적 차단 기록):"
    gate_activity
    echo ""
    echo "감사 판정 (아래는 세션이 이어서 수행):"
    audit_prompt
}

main() {
    case "${1:-}" in
        report|"") report ;;
        *) echo "usage: audit-methodology.sh [report]" >&2; exit 2 ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
