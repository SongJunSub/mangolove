#!/bin/bash
# ─────────────────────────────────────────────
# MangoLove — Cost Tracker
# Parse Claude Code session data for token usage and cost
# ─────────────────────────────────────────────

set -o pipefail

MANGOLOVE_DIR="${MANGOLOVE_DIR:-$HOME/.mangolove}"
# shellcheck source=colors.sh
source "${MANGOLOVE_DIR}/lib/colors.sh"

CLAUDE_DIR="$HOME/.claude"
PROJECTS_DIR="${MANGOLOVE_COST_PROJECTS_DIR:-$CLAUDE_DIR/projects}"

# 단가는 모델별로 다르다 — 세션 레코드의 message.model 에 따라 아래 batch_parse_sessions
# 의 PRICES 로 레코드 단위 적용한다. (과거엔 Opus 단가를 전 세션에 평면 적용해 경량 모델
# 비용을 과대 계상했다. 게다가 그 Opus 값($15/$75)마저 구형이라 현행 Opus($5/$25)의 3배였다.)
# cache write=input×1.25, cache read=input×0.1 (5분 ephemeral 기준)로 유도한다.

# ─────────────────────────────────────────────
# Parse a single session file and sum tokens
# ─────────────────────────────────────────────
# ─────────────────────────────────────────────
# Batch-process all session files with a single python3 call
# Input: list of "project_name:file_path" on stdin
# Output: "project_name,input,output,cache_write,cache_read,msgs" per project
# ─────────────────────────────────────────────
batch_parse_sessions() {
    local input_data
    input_data=$(cat)
    python3 -c "
import json, os
from collections import defaultdict

# 모델별 (input, output) 달러/1M 토큰. cache write=input*1.25, read=input*0.1 로 유도.
PRICES = {
    'claude-opus-4-8': (5.0, 25.0),
    'claude-opus-4-7': (5.0, 25.0),
    'claude-opus-4-6': (5.0, 25.0),
    'claude-opus-4-5': (5.0, 25.0),
    'claude-sonnet-5': (3.0, 15.0),
    'claude-sonnet-4-6': (3.0, 15.0),
    'claude-sonnet-4-5': (3.0, 15.0),
    'claude-haiku-4-5': (1.0, 5.0),
    'claude-fable-5': (10.0, 50.0),
    'claude-mythos-5': (10.0, 50.0),
}
DEFAULT = PRICES['claude-opus-4-8']  # 미상 모델 → 현행 Opus 단가로 추정

def price_for(model):
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

# [input, output, cache_write, cache_read, msgs, sessions, cost]
projects = defaultdict(lambda: [0, 0, 0, 0, 0, 0, 0.0])
file_list = '''${input_data}'''

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
                    i = usage.get('input_tokens', 0) or 0
                    o = usage.get('output_tokens', 0) or 0
                    cw = usage.get('cache_creation_input_tokens', 0) or 0
                    cr = usage.get('cache_read_input_tokens', 0) or 0
                    p_in, p_out = price_for(msg.get('model'))
                    cost = (i * p_in + o * p_out + cw * (p_in * 1.25) + cr * (p_in * 0.1)) / 1_000_000
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
    local since_date=""

    case "$period" in
        today) since_date=$(date -v-0d '+%Y-%m-%d') ;;
        week)  since_date=$(date -v-7d '+%Y-%m-%d') ;;
        month) since_date=$(date -v-1m '+%Y-%m-%d') ;;
        all)   since_date="2020-01-01" ;;
        *)     since_date=$(date -v-7d '+%Y-%m-%d') ;;
    esac

    if ! command -v python3 &>/dev/null; then
        echo -e "  ${Y}python3 required for cost tracking.${R}"
        return 1
    fi

    echo ""
    echo -e "${O}${B}MangoLove — Cost Tracker${R}"
    echo -e "${DIM}──────────────────────────────────────${R}"
    echo -e "  Period: ${C}${period}${R} (since ${since_date})"
    echo ""

    # Collect all session files matching the date range
    local file_list=""
    for project_dir in "$PROJECTS_DIR"/*/; do
        [ ! -d "$project_dir" ] && continue
        local proj_name
        proj_name=$(dir_to_project_name "$(basename "$project_dir")")

        for session_file in "$project_dir"/*.jsonl; do
            [ ! -f "$session_file" ] && continue
            local file_date
            file_date=$(stat -f "%Sm" -t "%Y-%m-%d" "$session_file" 2>/dev/null) || \
            file_date=$(stat -c "%y" "$session_file" 2>/dev/null | cut -d' ' -f1) || continue
            if [[ ! "$file_date" < "$since_date" ]]; then
                file_list="${file_list}${proj_name}:${session_file}
"
            fi
        done
    done

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

    # Total cost — 프로젝트별(모델별 단가 적용) 비용의 합
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
            echo -e "    ${B}${name}${R} — \$${cost} (${sessions} sessions, $(format_tokens "$p_out") output)"
        done
    fi

    echo ""
    echo -e "${DIM}──────────────────────────────────────${R}"
    echo -e "  ${DIM}단가(모델별, /1M in·out): opus \$5/\$25 · sonnet \$3/\$15 · haiku \$1/\$5 · fable \$10/\$50 (cache 추정)${R}"
    echo ""
}

# ─────────────────────────────────────────────
# Entrypoint
# ─────────────────────────────────────────────
show_cost "${1:-week}"
