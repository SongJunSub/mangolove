#!/usr/bin/env bash
# ─────────────────────────────────────────────
# MangoLove — DoD gate (Stop hook)
#
# 선언한 DoD 를 모델의 자기채점이 아니라 결정적 게이트로 닫는다(best-practices #1: Stop hook).
# bare mangolove 세션에 Stop 훅으로 런타임 주입된다(claude --settings), MANGOLOVE_DOD_GATE=on 일 때만.
# Stop 은 매 턴 종료마다 발화하나, DoD 가 외부화되지 않았으면 즉시 통과하므로 idle 비용이 없다.
#
# 계약(stdin=JSON, exit code 로 제어):
#   ./.mangolove/dod.sh 없음        → exit 0  (allow stop — DoD 미외부화)
#   dod.sh 있고 전 항목 PASS        → dod.sh + 카운터 제거 → exit 0 (게이트 충족, allow)
#   dod.sh 있고 하나라도 FAIL       → 카운터++, 실패 출력 stderr → exit 2 (block: 모델이 계속 수정)
#   FAIL 이 MAX회 연속             → exit 0 + 경고 (무한루프 backstop; stop_hook_active 미문서라 자체 종료 보장)
#
# 우회(감사됨): MANGOLOVE_SKIP_DOD=1
# 튜닝: MANGOLOVE_DOD_MAX_ATTEMPTS (기본 3)
#
# 모델은 완료를 주장하기 직전 DoD 를 실행형 체크로 ./.mangolove/dod.sh 에 외부화한다(system-prompt 참조).
# ─────────────────────────────────────────────
set -uo pipefail

GATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAX_ATTEMPTS="${MANGOLOVE_DOD_MAX_ATTEMPTS:-3}"
case "$MAX_ATTEMPTS" in ''|*[!0-9]*) MAX_ATTEMPTS=3 ;; esac

# Stop hook stdin JSON 에서 cwd 추출 — 세션 훅은 다른 cwd 에서 실행될 수 있어 프로젝트를 정확히 식별한다.
input="$(cat)"
cwd_field="$(printf '%s' "$input" | grep -oE '"cwd"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' | head -1)"
cwd_field="${cwd_field#*\"cwd\"*:*\"}"
cwd_field="${cwd_field%\"}"
if [ -n "$cwd_field" ] && [ -d "$cwd_field" ]; then
    cd "$cwd_field" 2>/dev/null || true
fi

DOD="./.mangolove/dod.sh"
STATE="./.mangolove/.dod-gate-attempts"

# DoD 가 외부화되지 않았으면 게이트 비활성 — 즉시 통과(무비용).
[ -f "$DOD" ] || exit 0

# 감사되는 우회구 — strict.md 는 우회를 금지하나 물리적으로는 존재한다.
if [ "${MANGOLOVE_SKIP_DOD:-}" = "1" ]; then
    echo "MangoLove DoD gate: MANGOLOVE_SKIP_DOD=1 (게이트 우회 — 감사 대상)" >&2
    exit 0
fi

attempts=0
[ -f "$STATE" ] && attempts="$(cat "$STATE" 2>/dev/null || echo 0)"
case "$attempts" in ''|*[!0-9]*) attempts=0 ;; esac

# 무한루프 backstop: MAX회 연속 실패면 게이트를 놓아준다(자체 종료 보장).
if [ "$attempts" -ge "$MAX_ATTEMPTS" ]; then
    echo "--- MangoLove DoD gate: ${attempts}회 시도에도 DoD 미통과 — 게이트 해제(무한루프 방지). 수동 확인 필요. ---" >&2
    rm -f "$STATE"
    exit 0
fi

# DoD 체크 실행.
out="$(bash "$DOD" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
    rm -f "$DOD" "$STATE"
    echo "MangoLove DoD gate: DoD 전 항목 통과 ✓" >&2
    exit 0
fi

# 실패 → 카운터 증가 후 block.
attempts=$((attempts + 1))
mkdir -p ./.mangolove 2>/dev/null || true
printf '%s' "$attempts" > "$STATE" 2>/dev/null || true
{
    echo "--- MangoLove DoD gate: DoD 미통과 (시도 ${attempts}/${MAX_ATTEMPTS}) — 완료를 주장하기 전에 아래를 해결하세요 ---"
    printf '%s\n' "$out" | tail -30
} >&2

# 효능 원장에 차단 기록(비차단·실패무시).
rec="$GATE_DIR/efficacy-recorder.sh"
[ -f "$rec" ] && bash "$rec" record-block dod-gate "fail" 2>/dev/null || true

exit 2
