#!/bin/bash
# ─────────────────────────────────────────────
# MangoLove: Cost Tracker
# Parse Claude Code session data for token usage and cost
# ─────────────────────────────────────────────

set -o pipefail

MANGOLOVE_DIR="${MANGOLOVE_DIR:-$HOME/.mangolove}"
# shellcheck source=colors.sh
source "${MANGOLOVE_DIR}/lib/colors.sh"

CLAUDE_DIR="$HOME/.claude"
PROJECTS_DIR="${MANGOLOVE_COST_PROJECTS_DIR:-$CLAUDE_DIR/projects}"

# 단가는 모델별로 다르다: 세션 레코드의 message.model 에 따라 아래 batch_parse_sessions
# 의 PRICES 로 레코드 단위 적용한다. (과거엔 Opus 단가를 전 세션에 평면 적용해 경량 모델
# 비용을 과대 계상했다. 게다가 그 Opus 값($15/$75)마저 구형이라 현행 Opus($5/$25)의 3배였다.)
# fast mode(usage.speed=='fast')는 같은 모델의 프리미엄 단가로 별도 계산한다 (FAST_PRICES).
# cache write=input×1.25, cache read=input×0.1 (5분 ephemeral 기준)로 유도한다.

# ─────────────────────────────────────────────
# Parse a single session file and sum tokens
# ─────────────────────────────────────────────
# ─────────────────────────────────────────────
# Batch-process all session files with a single python3 call
# Input: list of "project_name:file_path" on stdin
# Output: "project_name,input,output,cache_write,cache_read,msgs" per project
# ─────────────────────────────────────────────
# 단가표, 모델 정규화는 프로젝트 집계와 세션 집계가 **공유**한다.
# 두 곳에 복사하면 단가가 조용히 갈라진다: 이 파일이 이미 한 번 겪은 사고다
# (전 세션에 구형 Opus 단가를 평면 적용해 3배로 계산했다. tests/cost-tracker.bats 참조).
_ML_PRICE_PY=$(cat <<'PRICEPY'
# 모델별 (input, output) 달러/1M 토큰. cache write=input*1.25, read=input*0.1 로 유도.
PRICES = {
    'claude-opus-5': (5.0, 25.0),
    'claude-opus-4-8': (5.0, 25.0),
    'claude-opus-4-7': (5.0, 25.0),
    'claude-opus-4-6': (5.0, 25.0),
    'claude-opus-4-5': (5.0, 25.0),
    'claude-sonnet-5': (2.0, 10.0),
    'claude-sonnet-4-6': (3.0, 15.0),
    'claude-sonnet-4-5': (3.0, 15.0),
    'claude-haiku-4-5': (1.0, 5.0),
    'claude-fable-5': (10.0, 50.0),
    'claude-mythos-5': (10.0, 50.0),
}
DEFAULT = PRICES['claude-opus-5']  # 미상 모델 → 현행 Opus 단가로 추정

# fast mode(usage.speed == 'fast')는 같은 모델을 더 비싸게 과금한다. 세션 jsonl 의
# usage.speed 를 읽어 프리미엄 단가로 계산한다. 공개 단가가 확인된 모델만 싣는다
# (미등재 모델의 fast 는 표준 단가로 계산: 과소 계상될 수 있는 known-gap, 추정 금지).
FAST_PRICES = {
    'claude-opus-5': (10.0, 50.0),
}

# 세션 레코드의 model 은 변형 접미사를 달고 온다: 실측: 'claude-opus-5[1m]'(1M 컨텍스트),
# 그리고 과거 모델의 '-20251101' 같은 날짜 스냅샷. 정규화 없이 정확 일치 표만 보면
# 'claude-sonnet-5[1m]' 이 접두사 폴백(sonnet 4.6 단가)으로 새어 교정한 단가가 무효가 되고,
# fast 판정도 정확 일치라 'claude-opus-5[1m]' 의 프리미엄 과금이 통째로 빠진다.
def normalize_model(model):
    if not model:
        return model
    m = model.split('[', 1)[0]                       # [1m] 등 변형 접미사 제거
    return re.sub(r'-20\d{6}$', '', m)                # -YYYYMMDD 날짜 스냅샷 제거

# 한 usage 레코드의 비용. 단가표만 공유하고 이 식을 복제해 두면, 캐시 승수(1.25/0.1)를
# 바꾸는 순간 프로젝트 뷰와 세션 뷰의 비용이 다시 갈라진다. 공유의 의도를 여기서 완성한다.
def cost_of(usage, model):
    i = usage.get('input_tokens', 0) or 0
    o = usage.get('output_tokens', 0) or 0
    cw = usage.get('cache_creation_input_tokens', 0) or 0
    cr = usage.get('cache_read_input_tokens', 0) or 0
    p_in, p_out = price_for(model, usage.get('speed'))
    return (i, o, cw, cr,
            (i * p_in + o * p_out + cw * (p_in * 1.25) + cr * (p_in * 0.1)) / 1_000_000)

def price_for(model, speed=None):
    model = normalize_model(model)
    if speed == 'fast' and model in FAST_PRICES:
        return FAST_PRICES[model]
    if not model:
        return DEFAULT
    if model in PRICES:
        return PRICES[model]
    if model.startswith('claude-fable') or model.startswith('claude-mythos'):
        return (10.0, 50.0)
    if model.startswith('claude-opus'):
        return (5.0, 25.0)
    if model.startswith('claude-sonnet'):
        return (3.0, 15.0)
    if model.startswith('claude-haiku'):
        return (1.0, 5.0)
    return DEFAULT
PRICEPY
)

batch_parse_sessions() {
    python3 -c "
import json, os, re, sys
from collections import defaultdict

${_ML_PRICE_PY}

# [input, output, cache_write, cache_read, msgs, sessions, cost]
projects = defaultdict(lambda: [0, 0, 0, 0, 0, 0, 0.0])
file_list = sys.stdin.read()

for line in file_list.strip().split('\n'):
    line = line.strip()
    if not line or ':' not in line:
        continue
    idx = line.index(':')
    proj_name = line[:idx]
    file_path = line[idx+1:]
    if not os.path.isfile(file_path):
        continue
    session_msgs = 0
    with open(file_path, 'r') as f:
        for fline in f:
            fline = fline.strip()
            if not fline:
                continue
            try:
                data = json.loads(fline)
                msg = data.get('message', {}) or {}
                usage = msg.get('usage', {}) or {}
                if usage:
                    i, o, cw, cr, cost = cost_of(usage, msg.get('model'))
                    projects[proj_name][0] += i
                    projects[proj_name][1] += o
                    projects[proj_name][2] += cw
                    projects[proj_name][3] += cr
                    projects[proj_name][4] += 1
                    projects[proj_name][6] += cost
                    session_msgs += 1
            except (json.JSONDecodeError, KeyError):
                continue
    if session_msgs > 0:
        projects[proj_name][5] += 1

for name, v in projects.items():
    print(f'{name},{v[0]},{v[1]},{v[2]},{v[3]},{v[4]},{v[5]},{v[6]:.2f}')
" 2>/dev/null
}

# ─────────────────────────────────────────────
# Batch-process session files, aggregated per SESSION (not per project)
# Input: list of "project_name:file_path" on stdin
# Output: sorted "S|cost|turns|cache_read|peak_ctx|session_id|project" rows, then one "T|..." summary
#
# peak_ctx 는 저장된 필드가 아니다. 한 요청이 실제로 보낸 컨텍스트는
#   input_tokens + cache_creation_input_tokens + cache_read_input_tokens
# 이고, 그 세션 최대값이 peak 다 (러닝 max: 프로젝트 집계의 합산과는 다른 축).
# ─────────────────────────────────────────────
batch_parse_by_session() {
    python3 -c "
import json, os, re, sys
${_ML_PRICE_PY}

LONG_TURNS = int(os.environ.get('ML_LONG_TURNS', '300'))
TOP_N = int(os.environ.get('ML_TOP_N', '10'))

rows = []
file_list = sys.stdin.read()

for line in file_list.strip().split('\n'):
    line = line.strip()
    if not line or ':' not in line:
        continue
    idx = line.index(':')
    proj_name = line[:idx]
    file_path = line[idx+1:]
    if not os.path.isfile(file_path):
        continue
    turns = 0; cr_tot = 0; peak = 0; cost = 0.0
    with open(file_path, 'r') as f:
        for fline in f:
            fline = fline.strip()
            if not fline:
                continue
            try:
                data = json.loads(fline)
            except (json.JSONDecodeError, KeyError):
                continue
            msg = data.get('message', {}) or {}
            usage = msg.get('usage', {}) or {}
            if not usage:
                continue
            i, o, cw, cr, one = cost_of(usage, msg.get('model'))
            cost += one
            turns += 1
            cr_tot += cr
            if i + cw + cr > peak:
                peak = i + cw + cr
    if turns > 0:
        sid = os.path.basename(file_path)
        if sid.endswith('.jsonl'):
            sid = sid[:-6]
        rows.append((cost, turns, cr_tot, peak, sid, proj_name))

rows.sort(key=lambda r: r[0], reverse=True)
total = sum(r[0] for r in rows)
for r in rows:
    print('S|%.4f|%d|%d|%d|%s|%s' % r)

# 집계할 세션이 없으면 요약행 자체를 내지 않는다. 내면 show_sessions 는
# 세션 0개 / 총비용 0 을 찍는데 같은 픽스처에서 show_cost 는 데이터 없음을
# 안내한다. 두 뷰가 같은 상황을 다르게 말하면 안 된다.
if not rows:
    raise SystemExit(0)

top_cost = sum(r[0] for r in rows[:TOP_N])
long_rows = [r for r in rows if r[1] >= LONG_TURNS]
long_cost = sum(r[0] for r in long_rows)
def pct(x):
    return (x / total * 100.0) if total > 0 else 0.0
print('T|%.4f|%d|%d|%.4f|%.1f|%d|%.4f|%.1f|%d' % (
    total, len(rows), min(TOP_N, len(rows)), top_cost, pct(top_cost),
    len(long_rows), long_cost, pct(long_cost), LONG_TURNS))
" 2>/dev/null
}

# ─────────────────────────────────────────────
# Show per-session cost concentration
#
# 왜 별도 뷰인가: show_cost 는 프로젝트별로 합산하므로 "세션 하나가 얼마나 컸는가"가
# 구조적으로 보이지 않는다. 실측에서 비용은 세션 크기에 극단적으로 쏠려 있었다.
# 그 분포를 보는 것이 /clear, /compact 시점을 잡는 근거가 된다.
# ─────────────────────────────────────────────
show_sessions() {
    local period="${1:-all}"
    case "$period" in today|week|month|all) ;; *) period="all" ;; esac
    local since_date
    since_date=$(_since_date "$period")

    if ! command -v python3 &>/dev/null; then
        echo -e "  ${Y}python3 required for cost tracking.${R}"
        return 1
    fi

    echo ""
    echo -e "${O}${B}MangoLove: Cost by Session${R}"
    echo -e "${DIM}──────────────────────────────────────${R}"
    echo -e "  Period: ${C}${period}${R} (since ${since_date})"
    echo ""

    local file_list
    file_list=$(_collect_session_files "$since_date")

    if [ -z "$file_list" ]; then
        echo -e "  ${DIM}No session data found for this period.${R}"
        echo ""
        return 0
    fi

    local parsed
    parsed=$(echo "$file_list" | batch_parse_by_session) || true
    if [ -z "$parsed" ]; then
        echo -e "  ${DIM}No session data found for this period.${R}"
        echo ""
        return 0
    fi

    echo -e "  ${G}Top Sessions${R} ${DIM}(추정 비용순)${R}"
    printf "    %9s %6s %11s %9s  %s\n" "cost" "turns" "cacheRead" "peak ctx" "session"

    # 파서 출력은 S 행들 뒤에 T 행 하나다. 한 번만 훑는다.
    # 두 행은 필드 수가 다르므로(S=7, T=10) 줄을 통째로 읽고 태그별로 나눠 담는다.
    local shown=0 line
    local c t cr pk sid proj
    local total n topn topc toppct longn longc longpct thr
    while IFS= read -r line; do
        case "$line" in
            S\|*)
                [ "$shown" -ge 20 ] && continue
                shown=$((shown + 1))
                IFS='|' read -r c t cr pk sid proj <<< "${line#S|}"
                printf "    %9s %6s %11s %9s  %s ${DIM}%s${R}\n" \
                    "\$$(printf '%.2f' "$c")" "$t" \
                    "$(format_tokens "$cr")" "$(format_tokens "$pk")" \
                    "${sid:0:8}" "$proj"
                ;;
            T\|*)
                IFS='|' read -r total n topn topc toppct longn longc longpct thr <<< "${line#T|}"
                echo ""
                echo -e "  ${G}집중도${R}"
                printf "    세션 %s개, 추정 총비용 \$%s\n" "$n" "$(printf '%.2f' "$total")"
                printf "    상위 %s세션이 총비용의 %s%% (\$%s)\n" "$topn" "$toppct" "$(printf '%.2f' "$topc")"
                printf "    턴 %s+ 세션 %s개가 총비용의 %s%% (\$%s)\n" "$thr" "$longn" "$longpct" "$(printf '%.2f' "$longc")"
                ;;
        esac
    done < <(printf '%s\n' "$parsed")

    echo ""
    echo -e "${DIM}──────────────────────────────────────${R}"
    echo -e "  ${DIM}peak ctx = 한 요청이 보낸 최대 컨텍스트(input+cache write+cache read). 저장된 필드가 아니라 유도값.${R}"
    echo -e "  ${DIM}구독 과금이면 비용은 청구액이 아니라 플랜 사용량 소모의 대리 지표다.${R}"
    echo ""
}

# ─────────────────────────────────────────────
# 기간 문자열 → since_date. 두 뷰(show_cost / show_sessions)가 공유한다.
# 복제해 두었더니 한쪽에만 GNU date 폴백이 들어가 같은 파일 안에서 기간 정의가 갈라졌다.
# ─────────────────────────────────────────────
_since_date() {
    case "${1:-week}" in
        today) date -v-0d '+%Y-%m-%d' 2>/dev/null || date -d 'today' '+%Y-%m-%d' ;;
        week)  date -v-7d '+%Y-%m-%d' 2>/dev/null || date -d '7 days ago' '+%Y-%m-%d' ;;
        month) date -v-1m '+%Y-%m-%d' 2>/dev/null || date -d '1 month ago' '+%Y-%m-%d' ;;
        *)     echo "2020-01-01" ;;
    esac
}

# ─────────────────────────────────────────────
# since_date 이후에 갱신된 세션 파일을 "project_name:path" 줄로 낸다. 두 뷰가 공유한다.
# ─────────────────────────────────────────────
_collect_session_files() {
    local since_date="$1"
    local project_dir proj_name session_file file_date
    for project_dir in "$PROJECTS_DIR"/*/; do
        [ ! -d "$project_dir" ] && continue
        proj_name=$(dir_to_project_name "$(basename "$project_dir")")
        for session_file in "$project_dir"/*.jsonl; do
            [ ! -f "$session_file" ] && continue
            file_date=$(stat -f "%Sm" -t "%Y-%m-%d" "$session_file" 2>/dev/null) || \
            file_date=$(stat -c "%y" "$session_file" 2>/dev/null | cut -d' ' -f1) || continue
            if [[ ! "$file_date" < "$since_date" ]]; then
                printf '%s:%s\n' "$proj_name" "$session_file"
            fi
        done
    done
}

# ─────────────────────────────────────────────
# Get project name from directory path
# ─────────────────────────────────────────────
dir_to_project_name() {
    local dir_name="$1"
    # Convert -Users-ltm-luan-Project-CRS-crs-be to crs-be
    echo "$dir_name" | rev | cut -d'-' -f1-2 | rev | sed 's/^-//'
}

# ─────────────────────────────────────────────
# Format token count with K/M suffix
# ─────────────────────────────────────────────
format_tokens() {
    local count="$1"
    if [ "$count" -ge 1000000 ]; then
        printf "%.1fM" "$(echo "scale=1; $count / 1000000" | bc)"
    elif [ "$count" -ge 1000 ]; then
        printf "%.1fK" "$(echo "scale=1; $count / 1000" | bc)"
    else
        echo "$count"
    fi
}

# ─────────────────────────────────────────────
# Show cost summary
# ─────────────────────────────────────────────
show_cost() {
    local period="${1:-week}"
    case "$period" in today|week|month|all) ;; *) period="week" ;; esac
    local since_date
    since_date=$(_since_date "$period")

    if ! command -v python3 &>/dev/null; then
        echo -e "  ${Y}python3 required for cost tracking.${R}"
        return 1
    fi

    echo ""
    echo -e "${O}${B}MangoLove: Cost Tracker${R}"
    echo -e "${DIM}──────────────────────────────────────${R}"
    echo -e "  Period: ${C}${period}${R} (since ${since_date})"
    echo ""

    # Collect all session files matching the date range (show_sessions 와 같은 헬퍼를 쓴다)
    local file_list
    file_list=$(_collect_session_files "$since_date")

    # Single python3 call for all session files
    local batch_result=""
    if [ -n "$file_list" ]; then
        batch_result=$(echo "$file_list" | batch_parse_sessions) || true
    fi

    local total_input=0 total_output=0 total_cache_write=0 total_cache_read=0
    local total_messages=0 total_sessions=0
    local total_cost=0
    local project_data=""

    while IFS=',' read -r pname p_in p_out p_cw p_cr p_msgs p_sess p_cost; do
        [ -z "$pname" ] && continue
        project_data="${project_data}${p_cost}|${pname}|${p_in}|${p_out}|${p_cw}|${p_cr}|${p_msgs}|${p_sess}
"
        total_input=$((total_input + p_in))
        total_output=$((total_output + p_out))
        total_cache_write=$((total_cache_write + p_cw))
        total_cache_read=$((total_cache_read + p_cr))
        total_messages=$((total_messages + p_msgs))
        total_sessions=$((total_sessions + p_sess))
        total_cost=$(echo "${total_cost} + ${p_cost}" | bc)
    done <<< "$batch_result"

    if [ "$total_messages" -eq 0 ]; then
        echo -e "  ${DIM}No session data found for this period.${R}"
        echo ""
        return 0
    fi

    # Total cost: 프로젝트별(모델별 단가 적용) 비용의 합
    total_cost=$(printf "%.2f" "$total_cost")

    echo -e "  ${G}Total Cost${R}"
    echo -e "    Estimated  : ${B}\$${total_cost}${R}"
    echo -e "    Sessions   : ${DIM}${total_sessions}${R}"
    echo -e "    Messages   : ${DIM}${total_messages}${R}"
    echo ""

    echo -e "  ${G}Token Usage${R}"
    echo -e "    Input      : $(format_tokens "$total_input")"
    echo -e "    Output     : $(format_tokens "$total_output")"
    echo -e "    Cache Write: $(format_tokens "$total_cache_write")"
    echo -e "    Cache Read : $(format_tokens "$total_cache_read")"
    echo ""

    # Per-project breakdown (sorted by cost)
    if [ -n "$project_data" ]; then
        echo -e "  ${G}By Project${R}"
        echo "$project_data" | sort -t'|' -k1 -rn | head -10 | while IFS='|' read -r cost name _ p_out _ _ _ sessions; do
            [ -z "$name" ] && continue
            echo -e "    ${B}${name}${R}: \$${cost} (${sessions} sessions, $(format_tokens "$p_out") output)"
        done
    fi

    echo ""
    echo -e "${DIM}──────────────────────────────────────${R}"
    echo -e "  ${DIM}단가(모델별, /1M in-out): opus \$5/\$25, sonnet 5 \$2/\$10, sonnet 4.6 \$3/\$15, haiku \$1/\$5, fable \$10/\$50, opus 5 fast \$10/\$50 (cache 추정)${R}"
    echo ""
}

# ─────────────────────────────────────────────
# Entrypoint
# ─────────────────────────────────────────────
case "${1:-week}" in
    sessions) show_sessions "${2:-all}" ;;
    *)        show_cost "${1:-week}" ;;
esac
