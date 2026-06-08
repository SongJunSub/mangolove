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
# 세션 hook 으로 다른 cwd 에서 실행될 수 있으므로 stdin 의 cwd 로 이동 (게이트와 동일 — 효능 기록을 정확한 프로젝트 원장으로)
_cwd="$(printf '%s' "$input" | grep -oE '"cwd"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' | head -1)"
_cwd="${_cwd#*\"cwd\"*:*\"}"; _cwd="${_cwd%\"}"
if [ -n "$_cwd" ] && [ -d "$_cwd" ]; then cd "$_cwd" 2>/dev/null || true; fi
# JSON 래퍼("command":"...")를 벗겨 bare 명령을 얻고, 따옴표/백슬래시/백틱을 제거한다.
# (따옴표로 감싼 위험 경로/SQL 우회와 토큰 경계 오인을 무력화)
raw="$(printf '%s' "$input" | grep -oE '"command"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' | head -1)"
[ -z "$raw" ] && exit 0
cmd="${raw#*\"command\"*:*\"}"
cmd="${cmd%\"}"
cmd="${cmd//\"/}"
cmd="${cmd//\\/}"
cmd="${cmd//\'/}"
cmd="${cmd//\`/}"

has() { printf '%s' "$cmd" | grep -qiE "$1"; }

block() {
    # 효능 원장에 차단 기록 (비차단·실패무시)
    local rec; rec="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/efficacy-recorder.sh"
    if [ -f "$rec" ]; then bash "$rec" record-block guard "$1" 2>/dev/null || true; fi
    echo "MangoLove guard 차단 — 비가역/파괴적 명령 의심: $1" >&2
    echo "  의도적이면 MANGOLOVE_ALLOW_DANGER=1 로 재실행하세요 (감사 대상)." >&2
    exit 2
}

# git 강제 푸시 — force-with-lease 토큰을 먼저 제거한 뒤 남은 평범한 --force/-f 를 검출
# (부분문자열 'force-with-lease' 존재로 진짜 --force 가 면제되던 우회를 차단)
if has 'git[[:space:]].*push'; then
    nolease="$(printf '%s' "$cmd" | sed -E 's/--force-with-lease[^[:space:]]*//g')"
    printf '%s' "$nolease" | grep -qiE '(^|[^-])--force([[:space:]=]|$)' && block "git push --force"
    printf '%s' "$nolease" | grep -qiE '[[:space:]]-f([[:space:]]|$)'     && block "git push -f"
fi

has 'git[[:space:]]+reset[[:space:]]+--hard' && block "git reset --hard"

# rm 위험 루트 — 분리/롱폼 플래그(-r -f, --recursive --force)와 따옴표 우회까지 차단
if has '(^|[[:space:]])rm[[:space:]]' \
   && has '(--recursive|[[:space:]]-[a-z]*r)' \
   && has '(--force|[[:space:]]-[a-z]*f)' \
   && has '[[:space:]](/|~|\$HOME)'; then
    block "rm -rf on dangerous root"
fi

# 파괴적 SQL — sql 클라이언트 호출에 앵커링 (echo/grep/sed/커밋 메시지의 키워드 오차단 방지)
if has '(psql|mysql|mariadb|sqlite3|mongosh|mongo|clickhouse-client|cqlsh)([[:space:]]|$)'; then
    has 'drop[[:space:]]+(table|database|schema)'        && block "destructive SQL (DROP)"
    has 'truncate([[:space:]]+table)?[[:space:]]+[a-z_]' && block "destructive SQL (TRUNCATE)"
    if has 'delete[[:space:]]+from'; then
        # 각 DELETE 문(;로 구분)에 WHERE 가 없으면 차단 — 다른 문의 WHERE 로 면제되지 않게
        printf '%s' "$cmd" | grep -oiE 'delete[[:space:]]+from[^;]*' | grep -qivE 'where' && block "SQL DELETE without WHERE"
    fi
fi

has 'kubectl[[:space:]]+delete'    && block "kubectl delete"
has 'terraform[[:space:]]+destroy' && block "terraform destroy"

exit 0
