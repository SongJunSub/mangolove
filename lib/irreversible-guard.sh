#!/usr/bin/env bash
# ─────────────────────────────────────────────
# MangoLove — Irreversible/Destructive Command Guard (Claude PreToolUse)
#
# 되돌리기 어려운 명령을 실행 전에 차단한다 (exit 2 = 도구 호출 차단).
# strict.md dry-run 게이트 철학("AI가 DB를 9초 만에 삭제한 사례는 dry-run 부재가
# 아니라 확인 단계 부재가 원인")을, 어조가 아니라 명령 실행 경로상의 결정적
# 관문으로 인코딩한다. 심층 방어 1겹(정규식이 못 잡는 변형은 잔여 위험).
#
# stdin = Claude PreToolUse JSON. 의도적 실행: MANGOLOVE_ALLOW_DANGER=1 (감사 대상).
# ─────────────────────────────────────────────
set -uo pipefail

# 명시적 허용 — 감사됨
[ "${MANGOLOVE_ALLOW_DANGER:-}" = "1" ] && exit 0

input="$(cat)"
cmd="$(printf '%s' "$input" | grep -oE '"command"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' | head -1)"
[ -z "$cmd" ] && exit 0

has() { printf '%s' "$cmd" | grep -qiE "$1"; }

block() {
    echo "MangoLove guard 차단 — 비가역/파괴적 명령 의심: $1" >&2
    echo "  의도적이면 MANGOLOVE_ALLOW_DANGER=1 로 재실행하세요 (감사 대상)." >&2
    exit 2
}

# git 강제 푸시 (force-with-lease 는 비교적 안전하므로 허용)
if has 'git[[:space:]].*push'; then
    if has '[-]-force' && ! has 'force-with-lease'; then block "git push --force"; fi
    has 'push.*[[:space:]]-f([[:space:]]|"|$)' && block "git push -f"
fi

has 'git[[:space:]]+reset[[:space:]]+--hard'        && block "git reset --hard"
has 'drop[[:space:]]+(table|database|schema)'       && block "destructive SQL (DROP)"
has 'truncate[[:space:]]+table'                     && block "destructive SQL (TRUNCATE)"
if has 'delete[[:space:]]+from' && ! has 'where'; then block "SQL DELETE without WHERE"; fi
has 'rm[[:space:]]+-[a-z]*(rf|fr)[a-z]*[[:space:]]+(/|~|\$HOME)' && block "rm -rf on dangerous root"
has 'kubectl[[:space:]]+delete'                     && block "kubectl delete"
has 'terraform[[:space:]]+destroy'                  && block "terraform destroy"

exit 0
