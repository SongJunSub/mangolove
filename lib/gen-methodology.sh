#!/bin/bash
# ─────────────────────────────────────────────
# MangoLove: Methodology generator
# Regenerates methodology/core.md + cc-plugin/skills/* from methodology/strict.md
# by section-heading-derived ranges (never hand-rewrite), so strict.md stays the single
# source of truth. tests/methodology-split.bats asserts the committed files match
# a fresh regen, so any hand-edit or strict.md change that isn't regenerated fails CI.
#
# Usage: gen-methodology.sh [OUTPUT_ROOT]   (default: repo root)
#        gen-methodology.sh --print-ranges    (계산된 추출 범위만 출력, 파일 안 씀)
# ─────────────────────────────────────────────
set -euo pipefail

MODE="generate"
if [ "${1:-}" = "--print-ranges" ]; then MODE="print-ranges"; shift; fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="$REPO_ROOT/methodology/strict.md"
OUT="${1:-$REPO_ROOT}"

[ -f "$SRC" ] || { echo "gen-methodology: source not found: $SRC" >&2; exit 1; }

# ── 섹션 경계는 줄 번호가 아니라 헤딩 '텍스트'로 찾는다.
# 예전엔 total_lines 1개 + 앵커 7개 + sed 범위 7개, 총 15개 숫자를 손으로 맞췄다.
# strict.md 에 한 줄만 넣어도 15개가 전부 어긋나고, CI 가 잡아준 뒤 사람이 산술을
# 다시 해야 했다. 범위의 단일 출처를 헤딩으로 옮겨 그 수작업을 없앤다.
# 하드코딩이 주던 보호(새 섹션이 조용히 엉뚱한 목적지로 흡수되는 것 차단)는
# 아래 불변식 검사로 그대로 유지한다.
line_of() {
    local heading="$1" hits n
    hits="$(grep -nxF -- "$heading" "$SRC" | cut -d: -f1 || true)"
    n="$(printf '%s\n' "$hits" | grep -c . || true)"
    if [ "$n" -ne 1 ]; then
        echo "gen-methodology: 섹션 헤딩이 ${n}회 등장했다(정확히 1회여야 함)" >&2
        echo "  heading: ${heading}" >&2
        echo "  → strict.md 에서 헤딩이 바뀌었거나 중복됐다. 헤딩을 되돌리거나 이 목록을 고쳐라." >&2
        exit 1
    fi
    printf '%s' "$hits"
}

# wc 는 macOS 에서 앞에 공백을 붙인다. 문자열로 끼워 넣으므로 반드시 제거한다.
TOTAL="$(wc -l < "$SRC" | tr -d "[:space:]")"
L_LARGE="$(line_of '## Large Track 워크플로우')"
L_STEP1="$(line_of '### 1단계: 분석 (항상 먼저)')"
L_STEP6="$(line_of '### 6단계: 구현')"
L_SMART="$(line_of '## 스마트 리뷰 라우팅')"
L_SUB="$(line_of '## 서브에이전트 병렬 작업 규칙')"
L_CICD="$(line_of '## CI/CD 워크플로우 작업 규칙')"
L_GATE="$(line_of '## 신뢰성 게이트: 프롬프트의 "강제 표현"은 신호다')"

# 순서가 뒤바뀌면 범위가 조용히 역전되어 빈 추출이 된다.
_prev=0
for _n in "$L_LARGE" "$L_STEP1" "$L_STEP6" "$L_SMART" "$L_SUB" "$L_CICD" "$L_GATE"; do
    [ "$_n" -gt "$_prev" ] || { echo "gen-methodology: 섹션 순서가 문서와 다르다(줄 ${_n} 이 ${_prev} 뒤에 와야 함)" >&2; exit 1; }
    _prev="$_n"
done
[ "$L_GATE" -le "$TOTAL" ] || { echo "gen-methodology: 마지막 섹션이 파일 끝을 넘는다" >&2; exit 1; }

# 'Large Track 워크플로우' 헤더와 뒤따르는 빈 줄, 딱 2줄만 드롭된다는 불변식.
# (core.md 는 이 자리를 '온디맨드 스킬' 포인터로 대체한다.)
[ "$L_STEP1" -eq $((L_LARGE + 2)) ] || { echo "gen-methodology: Large Track 헤더와 1단계 사이에 새 내용이 생겼다(드롭 범위 재검토 필요)" >&2; exit 1; }
[ -z "$(sed -n "$((L_LARGE + 1))p" "$SRC")" ] || { echo "gen-methodology: Large Track 헤더 다음 줄이 빈 줄이 아니다" >&2; exit 1; }

# 꼬리 영역(스마트 리뷰 이후)의 구조 섹션은 정확히 4개다. 여기에 새 섹션을 붙이면
# 큰소리로 실패해서 '코어에 남길지 스킬로 내릴지'를 사람이 결정하게 만든다.
_tail_heads="$(sed -n "${L_SMART},${TOTAL}p" "$SRC" | grep -c '^## ' || true)"
[ "$_tail_heads" -eq 4 ] || { echo "gen-methodology: 꼬리 영역의 '## ' 섹션이 4개가 아니라 ${_tail_heads}개다. 새 섹션의 목적지를 정하고 이 파일의 섹션 목록을 갱신하라." >&2; exit 1; }

# ── 계산된 추출 범위 (sed 인자 형태)
R_CORE_HEAD="1,$((L_LARGE - 1))"
R_SMART="${L_SMART},$((L_SUB - 1))"
R_GATE="${L_GATE},${TOTAL}"
R_SPEC="${L_STEP1},$((L_STEP6 - 1))"
R_LARGE="${L_STEP6},$((L_SMART - 1))"
R_SUB="${L_SUB},$((L_CICD - 1))"
R_CICD="${L_CICD},$((L_GATE - 1))"

# 커버리지 테스트는 이 출력을 읽는다. 범위를 테스트에 다시 적으면 두 번째 진실 출처가 된다.
if [ "$MODE" = "print-ranges" ]; then
    printf '%s\n' "$R_CORE_HEAD" "$R_SPEC" "$R_LARGE" "$R_SMART" "$R_SUB" "$R_CICD" "$R_GATE" | tr ',' '-'
    exit 0
fi

mkdir -p "$OUT/methodology" \
         "$OUT/cc-plugin/skills/mangolove-spec" \
         "$OUT/cc-plugin/skills/mangolove-large-review" \
         "$OUT/cc-plugin/skills/mangolove-subagent-worktree" \
         "$OUT/cc-plugin/skills/mangolove-cicd"

# ── core.md = strict head (1-505) + on-demand pointer + smart-review-routing (1023-1034)
#              + reliability-gate (1100-1136). Safety procedures (dry-run/memory/boundary)
#              live in the head range and therefore stay resident in core.
{
  sed -n "${R_CORE_HEAD}p" "$SRC"
  cat <<'PTR'

## 트랙 워크플로우 상세: 온디맨드 스킬

Trivial/Small 트랙은 위의 트랙 표만으로 충분하다 (구현 → 빌드/린트 [→ 셀프 리뷰 → 테스트] → 보고).

**Medium/Large 트랙**은 무거운 절차를 **온디맨드 스킬**로 로드한다. 해당 시점에 아래 스킬을 반드시 호출한다:

| 스킬 | 언제 | 무엇 |
|------|------|------|
| `mangolove-spec` | Medium/Large 에서 Spec 작성, 리뷰 시 | 7종 Spec 템플릿, Spec 적대적 리뷰, Product/Engineering 리뷰, 최종 승인 형식 |
| `mangolove-large-review` | Large 구현~완료 단계 | 구현 체크리스트, 셀프 리뷰, 3인 탈상관 find→verify 코드 리뷰, Dashboard, 완료 보고 |
| `mangolove-subagent-worktree` | 다른 티켓, 브랜치를 병렬로 작업할 때 | worktree 격리 서브에이전트 실행, 상태 보고, 결과 재검증 규칙 |
| `mangolove-cicd` | CI/CD, Actions, 빌드 설정 변경 시 | 외부 Action/CLI 검증, 버전 업 사용처 감사, 설정 diff 대조, 최소권한 규칙 |

**정합성 규칙 (코어가 authoritative)**: 이 코어 문서가 트랙 판정, 승인 게이트, 안전 절차의 단일 기준이다. 스킬은 상세 절차만 담는다. 트랙상 필요한 스킬이 로드되지 않았으면 **그 사실을 사용자에게 밝히고** 코어 기준으로 진행한다(침묵 금지). 스킬과 코어가 충돌하면 코어를 따른다.

**완료 보고 의무 (모든 트랙, 코어 상주)**: 완료 시 빌드/린트/테스트 결과를 **산출물 경로/URL과 함께** 보고한다("PASS"만 보고 금지). Medium/Large 는 Review Readiness Dashboard 를 출력한다(상세 형식은 `mangolove-large-review`). DoD 항목별 검증 결과를 포함한다.

---
PTR
  sed -n "${R_SMART}p" "$SRC"
  sed -n "${R_GATE}p" "$SRC"
} > "$OUT/methodology/core.md"

# ── mangolove-spec = Large workflow steps 1–5
{
  cat <<'FM'
---
name: mangolove-spec
description: "MangoLove Medium/Large 트랙에서 Spec 을 작성, 검토할 때 사용한다. 7종 Spec 템플릿(API, 리팩토링, 인프라/CICD, 배치, 버그, UI), Spec 적대적 리뷰 체크리스트, Product/Engineering 리뷰, 단일 최종 승인 제시 형식을 제공한다. 새 기능, API 수정, 리팩토링, 스키마 변경 등 Spec 이 필요한 작업에서 호출한다."
---

# MangoLove: Spec 작성 & 사전 리뷰 (mangolove-spec)

이 스킬은 strict 방법론 Large 워크플로우의 **분석 → Spec → Spec 적대적 리뷰 → Product/Engineering 리뷰 → 최종 승인** 단계 상세다.
트랙 판정, 승인 원칙, 안전 절차(dry-run, 메모리, 경계면)는 **코어(core.md)** 에 있으며 그것이 authoritative 다.
Spec 은 세션 대화(메모리)에만 유지하고 레포에 파일로 남기지 않는다.

FM
  sed -n "${R_SPEC}p" "$SRC"
} > "$OUT/cc-plugin/skills/mangolove-spec/SKILL.md"

# ── mangolove-large-review = Large workflow steps 6–10
{
  cat <<'FM'
---
name: mangolove-large-review
description: "MangoLove Large 트랙 구현~완료 단계에서 사용한다. 구현 시 보안(OWASP, ISMS-P)/성능/null/스타일 체크리스트, 셀프 리뷰, 3인 탈상관(정독, 반증, 반례) find→verify 코드 리뷰, Review Readiness Dashboard, 완료 보고 산출물 형식을 제공한다. 최종 승인 후 구현, 리뷰, 커밋 준비 단계에서 호출한다."
---

# MangoLove: 구현 & 코드 리뷰 (mangolove-large-review)

이 스킬은 strict 방법론 Large 워크플로우의 **구현 → 셀프 리뷰 → 3인 독립 코드 리뷰(find→verify) → Dashboard → 완료 보고** 단계 상세다.
앞 단계(분석, Spec, 사전 리뷰, 최종 승인)는 `mangolove-spec` 스킬과 코어에 있다.
트랙 판정, 승인 원칙, 안전 절차는 **코어(core.md)** 가 단일 기준이다.

FM
  sed -n "${R_LARGE}p" "$SRC"
} > "$OUT/cc-plugin/skills/mangolove-large-review/SKILL.md"

# ── mangolove-subagent-worktree = 서브에이전트 병렬 작업 규칙
{
  cat <<'FM'
---
name: mangolove-subagent-worktree
description: "MangoLove에서 메인 세션과 다른 티켓, 브랜치를 병렬로 작업할 때 사용한다. worktree 격리 서브에이전트 실행 규칙, 상태 보고(DONE, BLOCKED, NEEDS_CONTEXT), 서브에이전트 결과의 메인 세션 재검증(전수 Read, 영향 grep, 빌드/린트 재실행) 절차를 제공한다."
---

# MangoLove: 서브에이전트 병렬 worktree 작업 (mangolove-subagent-worktree)

이 스킬은 strict 방법론의 **서브에이전트 병렬 작업 규칙** 상세다. 트랙 판정, 승인, 안전 절차는 코어(core.md)가 단일 기준이다.

FM
  sed -n "${R_SUB}p" "$SRC"
} > "$OUT/cc-plugin/skills/mangolove-subagent-worktree/SKILL.md"

# ── mangolove-cicd = CI/CD 워크플로우 작업 규칙
{
  cat <<'FM'
---
name: mangolove-cicd
description: "MangoLove에서 CI/CD 워크플로우, GitHub Actions, 빌드 설정을 변경할 때 사용한다. 외부 Action/CLI 실존 검증, 버전 업그레이드 시 사용처 전수 감사, 설정 대체 시 old/new diff 대조, CI/CD 최소권한, 시크릿, 보안 규칙을 제공한다."
---

# MangoLove: CI/CD 작업 규칙 (mangolove-cicd)

이 스킬은 strict 방법론의 **CI/CD 워크플로우 작업 규칙** 상세다. 트랙 판정, 승인, 안전 절차는 코어(core.md)가 단일 기준이다.

FM
  sed -n "${R_CICD}p" "$SRC"
} > "$OUT/cc-plugin/skills/mangolove-cicd/SKILL.md"

echo "gen-methodology: wrote core.md + 4 skills to ${OUT}"
