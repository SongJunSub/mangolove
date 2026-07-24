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
# JSON 은 개행/캐리지리턴/탭을 \n \r \t 로 이스케이프한다. 아래 백슬래시 제거 '전에'
# 이들을 명령 구분자로 치환한다 — 안 그러면 \n 이 글자 'n' 이 되어 여러 줄 명령이 한 줄로
# 붙고, push 세그먼트 격리([^;|&])가 깨져 다른 명령의 -f/--force(예: 'git commit -F -')가
# push 의 force 로 오탐된다. (개행=명령 경계이므로 ';' 로 치환)
cmd="${cmd//\\n/;}"
cmd="${cmd//\\r/;}"
cmd="${cmd//\\t/ }"
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

# git 강제 푸시 — push '세그먼트'에 한해서만 --force/-f 를 검출한다.
# 명령줄 전체를 보면 체인된 무관 명령의 -f/--force 가 push 의 force 로 오탐된다:
#   'git push origin --delete X && rm -f y'                 → '-f' 가 rm 의 것인데 push -f 로 오탐
#   'git push origin --delete X && git worktree remove --force …' → '--force' 가 worktree 의 것인데 push --force 로 오탐
# 따라서 git 으로 시작해 push 를 포함하고 다음 구분자(; | &) 직전까지의 세그먼트만 검사한다.
# force-with-lease 토큰은 먼저 제거(부분문자열 존재로 진짜 --force 가 면제되던 우회 차단).
if has 'git[[:space:]].*push'; then
    nolease="$(printf '%s' "$cmd" | sed -E 's/--force-with-lease[^[:space:]]*//g')"
    push_seg="$(printf '%s' "$nolease" | grep -oiE 'git[[:space:]]+([^;|&]*[[:space:]])?push[^;|&]*')"
    if [ -n "$push_seg" ]; then
        printf '%s' "$push_seg" | grep -qiE '(^|[^-])--force([[:space:]=]|$)' && block "git push --force"
        # 단축 force 는 소문자 -f 만(대소문자 구분): 'git commit -F'(from-file) 등 -F 오탐 방지.
        printf '%s' "$push_seg" | grep -qE '[[:space:]]-f([[:space:]]|$)'      && block "git push -f"
    fi
fi

has 'git[[:space:]]+reset[[:space:]]+--hard' && block "git reset --hard"

# rm 위험 루트 — 분리/롱폼 플래그(-r -f, --recursive --force)와 따옴표 우회까지 차단.
# 위험 루트엔 리터럴(/,~)·환경변수(\$HOME,\$PWD,\${HOME},\${PWD})·명령치환(\$(pwd))까지 포함.
# 보수적: 이 루트 '아래 하위경로'(예: \$PWD/build, \$HOME/.ssh)도 함께 막는다 — 안전한 하위삭제와
# 위험한 하위삭제(.ssh 등)를 정규식으로 구분할 수 없으므로 안전을 택한다. 의도된 삭제는 override.
# 4개 조건을 명령 전체가 아니라 각 rm '세그먼트'에서만 확인 — 위 git push 검사와 동일 원리.
# 무관한 토큰(다른 명령의 -r, jq '//=' 의 '/', 설정 경로의 $HOME 등)이 합쳐져 생기던 오탐 제거.
# 진짜 'rm -rf $HOME' / 'rm -rf /' 는 그 세그먼트에서 3조건이 모두 참이므로 그대로 차단.
while IFS= read -r rm_seg; do
    [ -z "$rm_seg" ] && continue
    printf '%s' "$rm_seg" | grep -qiE '(--recursive|[[:space:]]-[a-z]*r)' || continue
    printf '%s' "$rm_seg" | grep -qiE '(--force|[[:space:]]-[a-z]*f)'     || continue
    printf '%s' "$rm_seg" | grep -qiE '[[:space:]](/|~|\$HOME|\$PWD|\$\{HOME\}|\$\{PWD\}|\$\(pwd\))' || continue
    block "rm -rf on dangerous root"
done < <(printf '%s' "$cmd" | grep -oiE '(^|[;|&])[[:space:]]*rm[[:space:]][^;|&]*')

# 파괴적 SQL — sql 클라이언트 호출에 앵커링 (echo/grep/sed/커밋 메시지의 키워드 오차단 방지)
if has '(psql|mysql|mariadb|sqlite3|mongosh|mongo|clickhouse-client|cqlsh)([[:space:]]|$)'; then
    has 'drop[[:space:]]+(table|database|schema)'        && block "destructive SQL (DROP)"
    has 'truncate([[:space:]]+table)?[[:space:]]+[a-z_]' && block "destructive SQL (TRUNCATE)"
    if has 'delete[[:space:]]+from'; then
        # 각 DELETE 문(;로 구분)에 WHERE 가 없으면 차단 — 다른 문의 WHERE 로 면제되지 않게
        printf '%s' "$cmd" | grep -oiE 'delete[[:space:]]+from[^;]*' | grep -qivE 'where' && block "SQL DELETE without WHERE"
    fi
fi

# 파괴적 Mongo — mongo/mongosh 호출에 앵커링 (SQL 구문이 아닌 문서 메서드라 위 블록이 못 잡음).
# 조건 없는 전체 삭제·컬렉션/DB drop 만 차단; 필터가 있는 deleteMany 는 통과(정밀도 보존).
if has '(mongosh|mongo)([[:space:]]|$)'; then
    has 'dropDatabase[[:space:]]*\(' && block "destructive Mongo (dropDatabase)"
    # drop( 은 인자 유무와 무관히 파괴적(컬렉션 제거). mongo 앵커라 list.drop(n) 등 오탐 없음; .dropIndex 는 제외됨.
    has '\.drop[[:space:]]*\('        && block "destructive Mongo (collection.drop())"
    # 필터에 필드(:)가 없으면 = 조건 없는 전체 삭제 → 차단. 필드가 있으면(: 포함) 통과(정밀도).
    # 이스케이프(\n,\t)가 역슬래시 제거로 n,t 만 잔류해도 콜론이 없으므로 동일하게 잡힌다(우회 차단).
    has '(deleteMany|remove)[[:space:]]*\([[:space:]]*\{[^:}]*\}' && block "destructive Mongo (no-filter deleteMany/remove)"
fi

has 'kubectl[[:space:]]+delete'    && block "kubectl delete"
has 'terraform[[:space:]]+destroy' && block "terraform destroy"

exit 0
