#!/usr/bin/env bash
# ─────────────────────────────────────────────
# MangoLove — status line
# settings.json 의 statusLine 로 주입된다(claude --settings). stdin=JSON.
# context window 사용률·세션 비용·메서드러지 모드를 한 줄로 노출해 다이어트 효과를 가시화한다.
# (context_window.used_percentage, cost.total_cost_usd, model.display_name 등은 claude 가 제공.)
#
# 모드/게이트는 명령 문자열에 env 로 baked 된다 (generate_session_settings 참조).
# ─────────────────────────────────────────────
set -uo pipefail

# 스크립트를 -c 로 전달한다 — 이렇게 해야 python 의 stdin 이 (heredoc 이 아니라) 파이프된 JSON 이 된다.
# python3 로 파싱해 중첩 필드/null 을 견고하게 처리한다. MangoLove 는 python3 를 요구한다.
_ML_SL_PY=$(cat <<'PY'
import sys, os, json

mode = os.environ.get("MANGOLOVE_STATUSLINE_MODE", "monolith")
dod  = os.environ.get("MANGOLOVE_STATUSLINE_DOD", "off")

O="\033[38;5;208m"; DIM="\033[2m"; G="\033[38;5;113m"; Y="\033[38;5;220m"; RED="\033[38;5;203m"; R="\033[0m"

try:
    d = json.load(sys.stdin)
except Exception:
    print(f"{O}\U0001F96D MangoLove{R}")
    sys.exit(0)

def g(path, default=None):
    cur = d
    for k in path.split("."):
        if isinstance(cur, dict) and cur.get(k) is not None:
            cur = cur[k]
        else:
            return default
    return cur

parts = [f"{O}\U0001F96D{R}"]

model = g("model.display_name")
if model:
    parts.append(str(model))

cwd = g("workspace.current_dir") or g("cwd") or ""
proj = os.path.basename(cwd.rstrip("/")) if cwd else ""
if proj:
    parts.append(f"{DIM}{proj}{R}")

used = g("context_window.used_percentage")
if isinstance(used, (int, float)):
    col = G if used < 60 else (Y if used < 85 else RED)
    parts.append(f"ctx {col}{used:.0f}%{R}")
elif g("exceeds_200k_tokens") is True:
    parts.append(f"{RED}ctx >200k{R}")
else:
    parts.append(f"{DIM}ctx —{R}")

cost = g("cost.total_cost_usd")
if isinstance(cost, (int, float)) and cost > 0:
    parts.append(f"${cost:.2f}")

mcol = G if mode == "split" else DIM
parts.append(f"{mcol}{mode}{R}")
if dod == "on":
    parts.append(f"{G}dod{R}")

print(" · ".join(parts))
PY
)

exec python3 -c "$_ML_SL_PY"
