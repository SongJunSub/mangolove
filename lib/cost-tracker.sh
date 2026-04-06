#!/bin/bash
# ─────────────────────────────────────────────
# MangoLove — Cost Tracker
# Parse Claude Code session data for token usage and cost
# ─────────────────────────────────────────────

set -o pipefail

# Colors
R='\033[0m'
B='\033[1m'
DIM='\033[2m'
O='\033[38;5;208m'
G='\033[38;5;113m'
C='\033[38;5;117m'
Y='\033[38;5;220m'

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
parse_session_tokens() {
    local session_file="$1"
    # since_ts reserved for future timestamp filtering

    [ ! -f "$session_file" ] && return

    # Use python3 for reliable JSON parsing
    python3 << PYEOF 2>/dev/null
import json, sys

input_tokens = 0
output_tokens = 0
cache_write_tokens = 0
cache_read_tokens = 0
msg_count = 0

with open("${session_file}", "r") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            data = json.loads(line)
            usage = data.get("message", {}).get("usage", {})
            if usage:
                input_tokens += usage.get("input_tokens", 0)
                output_tokens += usage.get("output_tokens", 0)
                cache_write_tokens += usage.get("cache_creation_input_tokens", 0)
                cache_read_tokens += usage.get("cache_read_input_tokens", 0)
                msg_count += 1
        except (json.JSONDecodeError, KeyError):
            continue

print(f"{input_tokens},{output_tokens},{cache_write_tokens},{cache_read_tokens},{msg_count}")
PYEOF
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

    local total_input=0
    local total_output=0
    local total_cache_write=0
    local total_cache_read=0
    local total_messages=0
    local total_sessions=0

    # Per-project breakdown
    local project_data=""

    for project_dir in "$PROJECTS_DIR"/*/; do
        [ ! -d "$project_dir" ] && continue

        local proj_input=0 proj_output=0 proj_cw=0 proj_cr=0 proj_msgs=0 proj_sessions=0

        for session_file in "$project_dir"/*.jsonl; do
            [ ! -f "$session_file" ] && continue

            # Check file modification date
            local file_date
            file_date=$(stat -f "%Sm" -t "%Y-%m-%d" "$session_file" 2>/dev/null) || \
            file_date=$(stat -c "%y" "$session_file" 2>/dev/null | cut -d' ' -f1) || continue

            if [[ "$file_date" < "$since_date" ]]; then
                continue
            fi

            local result
            result=$(parse_session_tokens "$session_file") || continue
            [ -z "$result" ] && continue

            local s_input s_output s_cw s_cr s_msgs
            IFS=',' read -r s_input s_output s_cw s_cr s_msgs <<< "$result"

            [ "$s_msgs" -eq 0 ] 2>/dev/null && continue

            proj_input=$((proj_input + s_input))
            proj_output=$((proj_output + s_output))
            proj_cw=$((proj_cw + s_cw))
            proj_cr=$((proj_cr + s_cr))
            proj_msgs=$((proj_msgs + s_msgs))
            proj_sessions=$((proj_sessions + 1))
        done

        if [ "$proj_msgs" -gt 0 ]; then
            local proj_name
            proj_name=$(dir_to_project_name "$(basename "$project_dir")")
            local proj_cost
            proj_cost=$(calculate_cost "$proj_input" "$proj_output" "$proj_cw" "$proj_cr")

            project_data="${project_data}${proj_cost}|${proj_name}|${proj_input}|${proj_output}|${proj_cw}|${proj_cr}|${proj_msgs}|${proj_sessions}
"
            total_input=$((total_input + proj_input))
            total_output=$((total_output + proj_output))
            total_cache_write=$((total_cache_write + proj_cw))
            total_cache_read=$((total_cache_read + proj_cr))
            total_messages=$((total_messages + proj_msgs))
            total_sessions=$((total_sessions + proj_sessions))
        fi
    done

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
case "${1:-}" in
    today) show_cost "today" ;;
    week)  show_cost "week" ;;
    month) show_cost "month" ;;
    all)   show_cost "all" ;;
    *)     show_cost "${1:-week}" ;;
esac
