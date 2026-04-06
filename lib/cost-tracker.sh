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
PROJECTS_DIR="$CLAUDE_DIR/projects"

# Pricing per million tokens (Claude Opus 4.6, 2026 rates)
PRICE_INPUT=15.00
PRICE_OUTPUT=75.00
PRICE_CACHE_WRITE=3.75
PRICE_CACHE_READ=0.30

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

projects = defaultdict(lambda: [0, 0, 0, 0, 0, 0])
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
                usage = data.get('message', {}).get('usage', {})
                if usage:
                    projects[proj_name][0] += usage.get('input_tokens', 0)
                    projects[proj_name][1] += usage.get('output_tokens', 0)
                    projects[proj_name][2] += usage.get('cache_creation_input_tokens', 0)
                    projects[proj_name][3] += usage.get('cache_read_input_tokens', 0)
                    projects[proj_name][4] += 1
                    session_msgs += 1
            except (json.JSONDecodeError, KeyError):
                continue
    if session_msgs > 0:
        projects[proj_name][5] += 1

for name, vals in projects.items():
    print(f'{name},{vals[0]},{vals[1]},{vals[2]},{vals[3]},{vals[4]},{vals[5]}')
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
# Calculate cost from token counts
# ─────────────────────────────────────────────
calculate_cost() {
    local input="$1"
    local output="$2"
    local cache_write="$3"
    local cache_read="$4"

    echo "scale=2; ($input * $PRICE_INPUT + $output * $PRICE_OUTPUT + $cache_write * $PRICE_CACHE_WRITE + $cache_read * $PRICE_CACHE_READ) / 1000000" | bc
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
    local project_data=""

    while IFS=',' read -r pname p_in p_out p_cw p_cr p_msgs p_sess; do
        [ -z "$pname" ] && continue
        local proj_cost
        proj_cost=$(calculate_cost "$p_in" "$p_out" "$p_cw" "$p_cr")
        project_data="${project_data}${proj_cost}|${pname}|${p_in}|${p_out}|${p_cw}|${p_cr}|${p_msgs}|${p_sess}
"
        total_input=$((total_input + p_in))
        total_output=$((total_output + p_out))
        total_cache_write=$((total_cache_write + p_cw))
        total_cache_read=$((total_cache_read + p_cr))
        total_messages=$((total_messages + p_msgs))
        total_sessions=$((total_sessions + p_sess))
    done <<< "$batch_result"

    if [ "$total_messages" -eq 0 ]; then
        echo -e "  ${DIM}No session data found for this period.${R}"
        echo ""
        return 0
    fi

    # Total cost
    local total_cost
    total_cost=$(calculate_cost "$total_input" "$total_output" "$total_cache_write" "$total_cache_read")

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
    echo -e "  ${DIM}Prices: input \$${PRICE_INPUT}/M, output \$${PRICE_OUTPUT}/M${R}"
    echo ""
}

# ─────────────────────────────────────────────
# Entrypoint
# ─────────────────────────────────────────────
show_cost "${1:-week}"
