#!/usr/bin/env bash
# ─────────────────────────────────────────────
# MangoLove — Impact Score (결정적 트랙 분류)  [Phase 2 / D6]
#
# strict.md §44-76 Change Impact Score 의 "셀 수 있는 항목"을 LLM 추정이 아니라
# git diff 로 코드가 계산한다. 핵심 출력은 track_floor — 경로/심볼 패턴에 따른
# 트랙 하한으로 100% 결정적이다(DB→Medium, 외부API→Medium, 인증→Large).
# "새 로직 vs 기존 패턴 내 변경" 같은 의미론은 코드로 못 세므로 LLM 몫(이 스크립트 밖).
#
# 사용:
#   impact-score.sh score  <sha|--working>             → JSON 1줄 (점수 분해 + track_floor)
#   impact-score.sh triage <predicted> <sha|--working> → under_triage|ok|over_triage 판정(JSON)
#   impact-score.sh report <sha|--working>             → 사람용 출력
# ─────────────────────────────────────────────
set -uo pipefail

# diff 추출 — 커밋(sha) 과 워킹트리(--working) 양쪽 지원. 워크트리/서브모듈에서도 cwd git 으로 동작.
_ref_names() {
    if [ "$1" = "--working" ]; then git diff --name-only HEAD 2>/dev/null
    else git show --name-only --format='' "$1" 2>/dev/null; fi
}
_ref_numstat() {
    if [ "$1" = "--working" ]; then git diff --numstat HEAD 2>/dev/null
    else git show --numstat --format='' "$1" 2>/dev/null; fi
}
_ref_diff() {
    if [ "$1" = "--working" ]; then git diff HEAD 2>/dev/null
    else git show --format='' "$1" 2>/dev/null; fi
}

_rank() { case "$1" in Small) echo 1;; Medium) echo 2;; Large) echo 3;; *) echo 0;; esac; }
_track_from_rank() { case "$1" in 1) echo Small;; 2) echo Medium;; 3) echo Large;; *) echo Trivial;; esac; }
_bool() { if [ "$1" -eq 1 ]; then echo true; else echo false; fi; }

# compute <ref> → JSON 1줄 (결정적)
compute() {
    local ref="$1" names numstat diff
    names="$(_ref_names "$ref")"
    numstat="$(_ref_numstat "$ref")"
    diff="$(_ref_diff "$ref")"

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

    # 결정적 플래그 (경로 또는 diff 추가라인 패턴)
    local db=0 auth=0 ext=0 api=0
    if printf '%s' "$names" | grep -qiE '(^|/)(migrations?|db/(migration|changelog)|flyway|liquibase)/' \
       || printf '%s' "$diff" | grep -qiE '^\+.*(CREATE[[:space:]]+TABLE|ALTER[[:space:]]+TABLE|@Entity|@Table([^A-Za-z]|$))'; then
        db=1
    fi
    if printf '%s' "$names" | grep -qiE '(^|/)(auth|security|oauth|jwt|rbac|permission)' \
       || printf '%s' "$diff" | grep -qiE '^\+.*(@PreAuthorize|@Secured|@RolesAllowed|SecurityConfig|authenticat|authoriz)'; then
        auth=1
    fi
    if printf '%s' "$diff" | grep -qiE '^\+.*(RestTemplate|WebClient|HttpClient|OkHttp|@FeignClient|RestClient|axios|requests\.(get|post|put|delete))'; then
        ext=1
    fi
    if printf '%s' "$diff" | grep -qiE '^\+.*(@(Get|Post|Put|Delete|Patch|Request)Mapping|router\.(get|post|put|delete)|app\.(get|post|put|delete))'; then
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
    local predicted="$1" ref="$2" json floor pr fr verdict
    json="$(compute "$ref")"
    floor="$(printf '%s' "$json" | sed -E 's/.*"track_floor":"([^"]+)".*/\1/')"
    pr="$(_rank "$predicted")"
    fr="$(_rank "$floor")"
    if   [ "$pr" -lt "$fr" ]; then verdict="under_triage"
    elif [ "$pr" -gt "$fr" ]; then verdict="over_triage"
    else verdict="ok"
    fi
    printf '{"predicted":"%s","track_floor":"%s","verdict":"%s"}\n' "$predicted" "$floor" "$verdict"
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
        score)  [ -n "${2:-}" ] || { echo "usage: impact-score.sh score <sha|--working>" >&2; exit 2; }; compute "$2" ;;
        triage) [ -n "${3:-}" ] || { echo "usage: impact-score.sh triage <predicted> <sha|--working>" >&2; exit 2; }; triage "$2" "$3" ;;
        report) [ -n "${2:-}" ] || { echo "usage: impact-score.sh report <sha|--working>" >&2; exit 2; }; report "$2" ;;
        *) echo "usage: impact-score.sh {score|triage|report} ..." >&2; exit 2 ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
