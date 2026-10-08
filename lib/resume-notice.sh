#!/usr/bin/env bash
# ─────────────────────────────────────────────
# MangoLove: resume notice (SessionStart hook, matcher resume|fork)
#
# 무엇을 하는가:
#   프롬프트 캐시가 만료된 큰 대화를 재개하면, 첫 요청이 컨텍스트 전체를 다시 캐시에 쓴다.
#   claude v2.1.251 부터 SessionStart 훅이 그 비용을 미리 받는다(재개, 포크에 한해):
#     seconds_since_last_response, context_tokens, prompt_cache_likely_expired,
#     estimated_cache_write_usd
#   이 훅은 그 값을 **사용자에게만** 한 줄로 보여준다. 필드와 타입은 v2.1.293 에서 프로브
#   훅으로 확인했다(prompt_cache_likely_expired 는 따옴표 없는 boolean, 비용은 숫자).
#
# 하지 않는 것:
#   - 모델에 알리지 않는다. SessionStart 의 일반 텍스트 stdout 은 모델 컨텍스트에 들어가고,
#     그러면 모델이 "이어갈까요, /clear 할까요"를 묻기 시작한다. 그 질문은 사용자가 없애
#     달라고 한 것이다. 그래서 출력은 systemMessage 하나만 든 JSON 이다(프로브로 모델에
#     닿지 않음을 확인했다).
#   - 무엇을 하라고 권하지 않는다. 숫자만 보여주고 판단은 사용자가 한다.
#   - 세션 시작을 막지 않는다. 입력이 없거나 깨졌거나 타입이 어긋나면 조용히 exit 0.
#
# 끄기: MANGOLOVE_RESUME_NOTICE=off (훅 자체가 주입되지 않는다. bin/mangolove 참조)
# 임계: 재캐시 예상 비용이 MANGOLOVE_RESUME_NOTICE_MIN_USD(기본 1) 달러 미만이면 조용하다.
# ─────────────────────────────────────────────
set -uo pipefail

# 스크립트를 -c 로 전달한다: 그래야 python 의 stdin 이 파이프된 JSON 이 된다(statusline 과 같은 방식).
_ML_RN_PY=$(cat <<'PY'
import sys, os, json

try:
    d = json.load(sys.stdin)
    min_usd = float(os.environ.get("MANGOLOVE_RESUME_NOTICE_MIN_USD", "1"))
except Exception:
    sys.exit(0)
if not isinstance(d, dict):
    sys.exit(0)

def num(key):
    v = d.get(key)
    # bool 은 int 의 하위 타입이라 따로 거른다. 숫자가 아니면 추정하지 않는다.
    return v if isinstance(v, (int, float)) and not isinstance(v, bool) else None

usd = num("estimated_cache_write_usd")
tokens = num("context_tokens")
secs = num("seconds_since_last_response")
if d.get("prompt_cache_likely_expired") is not True or usd is None or tokens is None:
    sys.exit(0)
if usd < min_usd:
    sys.exit(0)

if tokens >= 1_000_000:
    size = f"{tokens / 1_000_000:.1f}M"
else:
    size = f"{tokens / 1000:.0f}K"

elapsed = ""
if secs is not None and secs >= 60:
    h, m = divmod(int(secs) // 60, 60)
    if h >= 24:
        elapsed = f"마지막 응답 후 {h // 24}일 {h % 24}시간, "
    elif h:
        elapsed = f"마지막 응답 후 {h}시간 {m}분, "
    else:
        elapsed = f"마지막 응답 후 {m}분, "

msg = (f"MangoLove: {elapsed}프롬프트 캐시가 만료됐습니다. "
       f"첫 요청이 컨텍스트 {size} 토큰을 다시 캐시에 씁니다 (예상 ${usd:.2f}).")
print(json.dumps({"systemMessage": msg}, ensure_ascii=False))
PY
)

command -v python3 >/dev/null 2>&1 || exit 0
python3 -c "$_ML_RN_PY" 2>/dev/null
exit 0
