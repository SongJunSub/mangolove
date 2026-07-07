#!/bin/bash
# ─────────────────────────────────────────────
# MangoLove — Methodology generator
# Regenerates methodology/core.md + cc-plugin/skills/* from methodology/strict.md
# by LINE RANGE extraction (never hand-rewrite), so strict.md stays the single
# source of truth. tests/methodology-split.bats asserts the committed files match
# a fresh regen, so any hand-edit or strict.md change that isn't regenerated fails CI.
#
# Usage: gen-methodology.sh [OUTPUT_ROOT]   (default: repo root)
# ─────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="$REPO_ROOT/methodology/strict.md"
OUT="${1:-$REPO_ROOT}"

[ -f "$SRC" ] || { echo "gen-methodology: source not found: $SRC" >&2; exit 1; }

# ── Anchor check — the extraction ranges below are coupled to strict.md's layout.
# If a section moves, fail loudly instead of silently mis-splitting the methodology.
assert_anchor() {
    local line="$1" expected="$2" actual
    actual="$(sed -n "${line}p" "$SRC")"
    if [ "$actual" != "$expected" ]; then
        echo "gen-methodology: anchor drift at line ${line}" >&2
        echo "  expected: ${expected}" >&2
        echo "  actual  : ${actual}" >&2
        echo "  → strict.md layout changed; update ranges in lib/gen-methodology.sh" >&2
        exit 1
    fi
}
total_lines="$(wc -l < "$SRC")"
[ "$total_lines" -eq 1047 ] || { echo "gen-methodology: strict.md line count ${total_lines} != 1047 (layout changed)" >&2; exit 1; }
assert_anchor 432  '## Large Track 워크플로우'
assert_anchor 434  '### 1단계: 분석 (항상 먼저)'
assert_anchor 663  '### 6단계: 구현'
assert_anchor 935  '## 스마트 리뷰 라우팅'
assert_anchor 947  '## 서브에이전트 병렬 작업 규칙'
assert_anchor 991  '## CI/CD 워크플로우 작업 규칙'
assert_anchor 1013 '## 신뢰성 게이트 — 프롬프트의 "강제 표현"은 신호다'

mkdir -p "$OUT/methodology" \
         "$OUT/cc-plugin/skills/mangolove-spec" \
         "$OUT/cc-plugin/skills/mangolove-large-review" \
         "$OUT/cc-plugin/skills/mangolove-subagent-worktree" \
         "$OUT/cc-plugin/skills/mangolove-cicd"

# ── core.md = strict head (1-431) + on-demand pointer + smart-review-routing (935-946)
#              + reliability-gate (1013-1047). Safety procedures (dry-run/memory/boundary)
#              live in the head range and therefore stay resident in core.
{
  sed -n '1,431p' "$SRC"
  cat <<'PTR'

## 트랙 워크플로우 상세 — 온디맨드 스킬

Trivial/Small 트랙은 위의 트랙 표만으로 충분하다 (구현 → 빌드/린트 [→ 셀프 리뷰 → 테스트] → 보고).

**Medium/Large 트랙**은 무거운 절차를 **온디맨드 스킬**로 로드한다 — 해당 시점에 아래 스킬을 반드시 호출한다:

| 스킬 | 언제 | 무엇 |
|------|------|------|
| `mangolove-spec` | Medium/Large 에서 Spec 작성·리뷰 시 | 7종 Spec 템플릿, Spec 적대적 리뷰, Product/Engineering 리뷰, 최종 승인 형식 |
| `mangolove-large-review` | Large 구현~완료 단계 | 구현 체크리스트, 셀프 리뷰, 3인 탈상관 find→verify 코드 리뷰, Dashboard, 완료 보고 |
| `mangolove-subagent-worktree` | 다른 티켓·브랜치를 병렬로 작업할 때 | worktree 격리 서브에이전트 실행·상태 보고·결과 재검증 규칙 |
| `mangolove-cicd` | CI/CD·Actions·빌드 설정 변경 시 | 외부 Action/CLI 검증, 버전 업 사용처 감사, 설정 diff 대조, 최소권한 규칙 |

**정합성 규칙 (코어가 authoritative)**: 이 코어 문서가 트랙 판정·승인 게이트·안전 절차의 단일 기준이다. 스킬은 상세 절차만 담는다. 트랙상 필요한 스킬이 로드되지 않았으면 **그 사실을 사용자에게 밝히고** 코어 기준으로 진행한다(침묵 금지). 스킬과 코어가 충돌하면 코어를 따른다.

**완료 보고 의무 (모든 트랙, 코어 상주)**: 완료 시 빌드/린트/테스트 결과를 **산출물 경로/URL과 함께** 보고한다("PASS"만 보고 금지). Medium/Large 는 Review Readiness Dashboard 를 출력한다(상세 형식은 `mangolove-large-review`). DoD 항목별 검증 결과를 포함한다.

---
PTR
  sed -n '935,946p' "$SRC"
  sed -n '1013,1047p' "$SRC"
} > "$OUT/methodology/core.md"

# ── mangolove-spec = Large workflow steps 1–5 (434-662)
{
  cat <<'FM'
---
name: mangolove-spec
description: "MangoLove Medium/Large 트랙에서 Spec 을 작성·검토할 때 사용한다. 7종 Spec 템플릿(API · 리팩토링 · 인프라/CICD · 배치 · 버그 · UI), Spec 적대적 리뷰 체크리스트, Product/Engineering 리뷰, 단일 최종 승인 제시 형식을 제공한다. 새 기능·API 수정·리팩토링·스키마 변경 등 Spec 이 필요한 작업에서 호출한다."
---

# MangoLove — Spec 작성 & 사전 리뷰 (mangolove-spec)

이 스킬은 strict 방법론 Large 워크플로우의 **분석 → Spec → Spec 적대적 리뷰 → Product/Engineering 리뷰 → 최종 승인** 단계 상세다.
트랙 판정 · 승인 원칙 · 안전 절차(dry-run · 메모리 · 경계면)는 **코어(core.md)** 에 있으며 그것이 authoritative 다.
Spec 은 세션 대화(메모리)에만 유지하고 레포에 파일로 남기지 않는다.

FM
  sed -n '434,662p' "$SRC"
} > "$OUT/cc-plugin/skills/mangolove-spec/SKILL.md"

# ── mangolove-large-review = Large workflow steps 6–10 (663-934)
{
  cat <<'FM'
---
name: mangolove-large-review
description: "MangoLove Large 트랙 구현~완료 단계에서 사용한다. 구현 시 보안(OWASP · ISMS-P)/성능/null/스타일 체크리스트, 셀프 리뷰, 3인 탈상관(정독 · 반증 · 반례) find→verify 코드 리뷰, Review Readiness Dashboard, 완료 보고 산출물 형식을 제공한다. 최종 승인 후 구현·리뷰·커밋 준비 단계에서 호출한다."
---

# MangoLove — 구현 & 코드 리뷰 (mangolove-large-review)

이 스킬은 strict 방법론 Large 워크플로우의 **구현 → 셀프 리뷰 → 3인 독립 코드 리뷰(find→verify) → Dashboard → 완료 보고** 단계 상세다.
앞 단계(분석 · Spec · 사전 리뷰 · 최종 승인)는 `mangolove-spec` 스킬과 코어에 있다.
트랙 판정 · 승인 원칙 · 안전 절차는 **코어(core.md)** 가 단일 기준이다.

FM
  sed -n '663,934p' "$SRC"
} > "$OUT/cc-plugin/skills/mangolove-large-review/SKILL.md"

# ── mangolove-subagent-worktree = 서브에이전트 병렬 작업 규칙 (947-990)
{
  cat <<'FM'
---
name: mangolove-subagent-worktree
description: "MangoLove에서 메인 세션과 다른 티켓·브랜치를 병렬로 작업할 때 사용한다. worktree 격리 서브에이전트 실행 규칙, 상태 보고(DONE · BLOCKED · NEEDS_CONTEXT), 서브에이전트 결과의 메인 세션 재검증(전수 Read · 영향 grep · 빌드/린트 재실행) 절차를 제공한다."
---

# MangoLove — 서브에이전트 병렬 worktree 작업 (mangolove-subagent-worktree)

이 스킬은 strict 방법론의 **서브에이전트 병렬 작업 규칙** 상세다. 트랙 판정·승인·안전 절차는 코어(core.md)가 단일 기준이다.

FM
  sed -n '947,990p' "$SRC"
} > "$OUT/cc-plugin/skills/mangolove-subagent-worktree/SKILL.md"

# ── mangolove-cicd = CI/CD 워크플로우 작업 규칙 (991-1012)
{
  cat <<'FM'
---
name: mangolove-cicd
description: "MangoLove에서 CI/CD 워크플로우·GitHub Actions·빌드 설정을 변경할 때 사용한다. 외부 Action/CLI 실존 검증, 버전 업그레이드 시 사용처 전수 감사, 설정 대체 시 old/new diff 대조, CI/CD 최소권한·시크릿·보안 규칙을 제공한다."
---

# MangoLove — CI/CD 작업 규칙 (mangolove-cicd)

이 스킬은 strict 방법론의 **CI/CD 워크플로우 작업 규칙** 상세다. 트랙 판정·승인·안전 절차는 코어(core.md)가 단일 기준이다.

FM
  sed -n '991,1012p' "$SRC"
} > "$OUT/cc-plugin/skills/mangolove-cicd/SKILL.md"

echo "gen-methodology: wrote core.md + 4 skills to ${OUT}"
