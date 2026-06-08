#!/usr/bin/env bash
# ─────────────────────────────────────────────
# MangoLove — Impact Score (결정적 트랙 분류)  [Phase 2 / D6]
#
# strict.md §44-76 Change Impact Score 의 "셀 수 있는 항목"을 LLM 추정이 아니라
# git diff 로 코드가 계산한다. 핵심 출력은 track_floor — 경로/심볼 패턴에 따른
# 트랙 하한으로, 동일 변경에 대해 결정적이다(DB→Medium, 외부API→Medium, 인증→Large).
# "새 로직 vs 기존 패턴 내 변경" 같은 의미론은 코드로 못 세므로 LLM 몫(이 스크립트 밖).
#
# 콘텐츠 패턴은 **실제 추가된 코드 라인**(diff 헤더/순수 주석/문서(.md 등) 제외)에만 적용해
# 파일명·주석·산문에 의한 오탐을 막는다. 정규식 커버 스택: Java/Kotlin/Spring, JS/TS,
# Python, Go, Rails/Django, C#/.NET(EF·[Authorize]), Rust(reqwest·tower/axum auth), PHP/Laravel(Schema),
# Ruby/Elixir HTTP (그 밖 스택·관용구는 미커버 — track_floor 보장은 커버 스택 한정).
#
# 사용:
#   impact-score.sh score          <sha|--working>             → JSON 1줄 (점수 분해 + track_floor)
#   impact-score.sh triage         <predicted> <sha|--working> → under_triage|ok|over_triage 판정(JSON)
#   impact-score.sh declared-track <sha>                       → 커밋의 Change-Track: trailer (없으면 빈 출력)
#   impact-score.sh triage-commit  <sha|--working>             → score + 선언트랙 + verdict(JSON 1줄)
#   impact-score.sh report         <sha|--working>             → 사람용 출력
# ─────────────────────────────────────────────
set -uo pipefail

# diff 추출 — 커밋(sha; 머지는 --first-parent 로 mainline 기준)과 워킹트리(--working) 지원.
# --working 은 untracked(아직 git add 안 한) 신규 파일도 포함한다(인덱스 변경 없이).
_ref_names() {
    if [ "$1" = "--working" ]; then
        { git diff --name-only HEAD 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null; } | sort -u
    else
        git show --first-parent --name-only --format='' "$1" 2>/dev/null
    fi
}
_ref_numstat() {
    if [ "$1" = "--working" ]; then
        git diff --numstat HEAD 2>/dev/null
        git ls-files --others --exclude-standard 2>/dev/null | awk 'NF{print "1\t0\t" $0}'
    else
        git show --first-parent --numstat --format='' "$1" 2>/dev/null
    fi
}
_ref_diff() {
    if [ "$1" = "--working" ]; then
        git diff HEAD 2>/dev/null
        local f
        git ls-files --others --exclude-standard 2>/dev/null | while IFS= read -r f; do
            git diff --no-index --no-color -- /dev/null "$f" 2>/dev/null
        done
    else
        git show --first-parent --format='' "$1" 2>/dev/null
    fi
}

# diff 에서 "실제 추가된 코드 라인"만 추출한다:
#  - diff 헤더(+++/---) 제외 (파일명-only 오탐 차단)
#  - 문서 확장자(.md 등) hunk 제외 (산문 속 키워드 오탐 차단)
#  - 순수 주석 라인(// # * <!--) 제외
_added_code() {
    printf '%s\n' "$1" | awk '
        /^\+\+\+ / { p=$0; sub(/^\+\+\+ (b\/)?/, "", p); doc = (p ~ /\.(md|markdown|txt|rst|adoc)$/); next }
        /^--- / { next }
        /^\+/ {
            t=$0; sub(/^\+[ \t]*/, "", t)
            if (t ~ /^(\/\/|#|\*|<!--)/) next
            if (!doc) print
        }
    '
}

_rank() { case "$1" in Small) echo 1;; Medium) echo 2;; Large) echo 3;; *) echo 0;; esac; }
_track_from_rank() { case "$1" in 1) echo Small;; 2) echo Medium;; 3) echo Large;; *) echo Trivial;; esac; }
_bool() { if [ "$1" -eq 1 ]; then echo true; else echo false; fi; }

# 잘못된/없는 ref 는 조용히 Trivial 로 흐르지 않게 비-0 종료한다.
_require_ref() {
    [ "$1" = "--working" ] && return 0
    git rev-parse --verify --quiet "${1}^{commit}" >/dev/null 2>&1 && return 0
    echo "impact-score: unknown revision: $1" >&2
    exit 1
}

# compute <ref> → JSON 1줄 (결정적)
compute() {
    local ref="$1" names numstat diff added
    names="$(_ref_names "$ref")"
    numstat="$(_ref_numstat "$ref")"
    diff="$(_ref_diff "$ref")"
    added="$(_added_code "$diff")"

    # 변경 파일 수 (numstat 비어있지 않은 줄). 빈/머지 커밋은 0 → set -u 안전.
    local files=0
    if [ -n "$numstat" ]; then
        files="$(printf '%s\n' "$numstat" | grep -cvE '^[[:space:]]*$')"
    fi

    # 파일 수 점수 (strict.md §50-53)
    local file_pts=0
    if   [ "$files" -ge 11 ]; then file_pts=8
    elif [ "$files" -ge 6 ];  then file_pts=5
    elif [ "$files" -ge 3 ];  then file_pts=3
    elif [ "$files" -ge 1 ];  then file_pts=1
    fi

    # 결정적 플래그 — 경로(names) 또는 추가-코드-라인(added) 패턴
    local db=0 auth=0 ext=0 api=0
    if printf '%s' "$names" | grep -qiE '(^|/)(migrations?|db/(migration|migrate|changelog)|flyway|liquibase)/' \
       || printf '%s' "$added" | grep -qiE '(CREATE[[:space:]]+TABLE|ALTER[[:space:]]+TABLE|@Entity|@Table([^A-Za-z]|$)|AutoMigrate|create_table|add_column|change_column|models\.Model|migrations\.(CreateModel|AddField)|migrationBuilder\.(CreateTable|DropTable|AddColumn|RenameColumn)|Schema::(create|table|dropIfExists))'; then
        db=1
    fi
    if printf '%s' "$names" | grep -qiE '(^|/)(auth|authn|authz|security|oauth|jwt|rbac|permissions|login|signin)/' \
       || printf '%s' "$added" | grep -qiE '(@PreAuthorize|@Secured|@RolesAllowed|@EnableWebSecurity|SecurityConfig|SecurityFilterChain|SecurityContextHolder|AuthenticationManager|UsernamePasswordAuthenticationToken|UserDetailsService|authenticate\(|authorize\(|bcrypt|argon2|scrypt|passport|next-auth|verifyPassword|\[Authorize|RequireAuthorizationLayer|tower_http::auth|axum_login|HttpAuthentication)'; then
        auth=1
    fi
    if printf '%s' "$added" | grep -qiE '(RestTemplate|WebClient|HttpClient|OkHttp|@FeignClient|RestClient|[^A-Za-z]axios[.(]|[^A-Za-z]fetch\(|requests\.(get|post|put|delete|patch|head)\(|httpx\.|urllib|http\.(Get|Post|NewRequest|Do)\(|reqwest::(get|post|put|delete|Client)|HTTPoison\.|Faraday\.)'; then
        ext=1
    fi
    # 라우팅 등록만 — getter 오탐 방지로 router/app 메서드는 첫 인자가 라우트 경로 리터럴("/...)일 때만.
    local api_q="['\"]" api_re
    api_re="(@(Get|Post|Put|Delete|Patch|Request)Mapping|@app\\.route|HandleFunc|[a-zA-Z_]+\\.(get|post|put|delete|patch)\\([[:space:]]*${api_q}/)"
    if printf '%s' "$added" | grep -qiE "$api_re"; then
        api=1
    fi

    local code_score=$file_pts
    [ "$db" -eq 1 ]   && code_score=$((code_score + 5))
    [ "$auth" -eq 1 ] && code_score=$((code_score + 6))
    [ "$ext" -eq 1 ]  && code_score=$((code_score + 4))
    [ "$api" -eq 1 ]  && code_score=$((code_score + 5))

    # 점수 → 트랙 (strict.md §67-70)
    local score_rank=0
    if   [ "$code_score" -ge 12 ]; then score_rank=3
    elif [ "$code_score" -ge 6 ];  then score_rank=2
    elif [ "$code_score" -ge 2 ];  then score_rank=1
    fi

    # 승격 하한 (strict.md §72-76): DB→Medium, 외부API→Medium, 인증→Large
    local floor_rank=$score_rank
    [ "$db" -eq 1 ]  && [ "$floor_rank" -lt 2 ] && floor_rank=2
    [ "$ext" -eq 1 ] && [ "$floor_rank" -lt 2 ] && floor_rank=2
    [ "$auth" -eq 1 ] && [ "$floor_rank" -lt 3 ] && floor_rank=3

    printf '{"ref":"%s","files":%d,"file_pts":%d,"db":%s,"auth":%s,"ext":%s,"api":%s,"code_score":%d,"track_from_score":"%s","track_floor":"%s"}\n' \
        "$ref" "$files" "$file_pts" \
        "$(_bool "$db")" "$(_bool "$auth")" "$(_bool "$ext")" "$(_bool "$api")" \
        "$code_score" "$(_track_from_rank "$score_rank")" "$(_track_from_rank "$floor_rank")"
}

# triage <predicted> <ref> → 선언 트랙이 코드 floor 보다 낮으면 under_triage (가장 비싼 누수)
triage() {
    local predicted="$1" ref="$2" json floor pr fr verdict norm
    norm="$(printf '%s' "$predicted" | tr '[:upper:]' '[:lower:]')"
    case "$norm" in
        trivial) pr=0 ;;
        small)   pr=1 ;;
        medium)  pr=2 ;;
        large)   pr=3 ;;
        *) echo "impact-score: unknown predicted track '$predicted' (Trivial|Small|Medium|Large)" >&2; exit 2 ;;
    esac
    json="$(compute "$ref")"
    floor="$(printf '%s' "$json" | sed -E 's/.*"track_floor":"([^"]+)".*/\1/')"
    fr="$(_rank "$floor")"
    if   [ "$pr" -lt "$fr" ]; then verdict="under_triage"
    elif [ "$pr" -gt "$fr" ]; then verdict="over_triage"
    else verdict="ok"
    fi
    printf '{"predicted":"%s","track_floor":"%s","verdict":"%s"}\n' "$predicted" "$floor" "$verdict"
}

# declared-track <ref> → 커밋 메시지의 Change-Track: trailer 를 정규화해 출력(없으면 빈 문자열).
# git interpret-trailers --parse 로 **footer 트레일러 블록만** 파싱 — 본문(prose) 속
# "Change-Track: ..." 라인을 트레일러로 오인하지 않는다(FP 차단). 마지막 트레일러 우선,
# 값의 첫 토큰만, 유효하지 않으면 undeclared 취급(빈 출력). --working 은 메시지가 없어 빈 출력.
declared_track() {
    local ref="$1" raw norm
    [ "$ref" = "--working" ] && return 0
    raw="$(git show -s --format='%B' "$ref" 2>/dev/null \
        | git interpret-trailers --parse 2>/dev/null \
        | grep -iE '^Change-Track:' | tail -1 \
        | sed -E 's/^[Cc]hange-[Tt]rack:[[:space:]]*//' \
        | awk '{print $1}')"
    [ -z "$raw" ] && return 0
    norm="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
    case "$norm" in
        trivial) echo Trivial ;;
        small)   echo Small ;;
        medium)  echo Medium ;;
        large)   echo Large ;;
        *) : ;;
    esac
}

# triage-commit <ref> → compute JSON 에 선언트랙(declared)과 verdict 를 합친 1줄.
# verdict: 선언이 없으면 undeclared, 있으면 floor 와 비교해 under_triage|over_triage|ok.
# (트리아지 판정의 단일 출처 — efficacy 집계는 이 verdict 만 읽는다.)
triage_commit() {
    local ref="$1" json floor decl dr fr verdict declared_json
    json="$(compute "$ref")"
    floor="$(printf '%s' "$json" | sed -E 's/.*"track_floor":"([^"]+)".*/\1/')"
    fr="$(_rank "$floor")"
    decl="$(declared_track "$ref")"
    if [ -z "$decl" ]; then
        verdict="undeclared"; declared_json="null"
    else
        dr="$(_rank "$decl")"
        if   [ "$dr" -lt "$fr" ]; then verdict="under_triage"
        elif [ "$dr" -gt "$fr" ]; then verdict="over_triage"
        else verdict="ok"
        fi
        declared_json="\"$decl\""
    fi
    printf '%s,"declared":%s,"verdict":"%s"}\n' "${json%\}}" "$declared_json" "$verdict"
}

# report <ref> → 사람용
report() {
    local ref="$1" json files score ts tf
    json="$(compute "$ref")"
    files="$(printf '%s' "$json" | sed -E 's/.*"files":([0-9]+).*/\1/')"
    score="$(printf '%s' "$json" | sed -E 's/.*"code_score":([0-9]+).*/\1/')"
    ts="$(printf '%s' "$json" | sed -E 's/.*"track_from_score":"([^"]+)".*/\1/')"
    tf="$(printf '%s' "$json" | sed -E 's/.*"track_floor":"([^"]+)".*/\1/')"
    echo "Impact (결정적): ${ref}"
    echo "  변경 파일: ${files}  |  code_score: ${score}  |  점수 트랙: ${ts}"
    echo "  -> track_floor (코드 강제 하한): ${tf}"
    if [ "$ts" != "$tf" ]; then
        echo "  ** 승격: 점수상 ${ts} 이나 DB/인증/외부API 변경으로 최소 ${tf}"
    fi
}

main() {
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        echo "impact-score: not a git repository" >&2; exit 1
    fi
    case "${1:-}" in
        score)  [ -n "${2:-}" ] || { echo "usage: impact-score.sh score <sha|--working>" >&2; exit 2; }; _require_ref "$2"; compute "$2" ;;
        triage) [ -n "${3:-}" ] || { echo "usage: impact-score.sh triage <predicted> <sha|--working>" >&2; exit 2; }; _require_ref "$3"; triage "$2" "$3" ;;
        declared-track) [ -n "${2:-}" ] || { echo "usage: impact-score.sh declared-track <sha>" >&2; exit 2; }; _require_ref "$2"; declared_track "$2" ;;
        triage-commit)  [ -n "${2:-}" ] || { echo "usage: impact-score.sh triage-commit <sha|--working>" >&2; exit 2; }; _require_ref "$2"; triage_commit "$2" ;;
        report) [ -n "${2:-}" ] || { echo "usage: impact-score.sh report <sha|--working>" >&2; exit 2; }; _require_ref "$2"; report "$2" ;;
        *) echo "usage: impact-score.sh {score|triage|declared-track|triage-commit|report} ..." >&2; exit 2 ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
