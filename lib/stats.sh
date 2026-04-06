#!/bin/bash
# ─────────────────────────────────────────────
# MangoLove — Productivity Stats
# Analyze git history and report metrics
# ─────────────────────────────────────────────

set -o pipefail

MANGOLOVE_DIR="${MANGOLOVE_DIR:-$HOME/.mangolove}"
# shellcheck source=colors.sh
source "${MANGOLOVE_DIR}/lib/colors.sh"

# ─────────────────────────────���───────────────
# Show stats for current project
# ───────────────────────────────���─────────────
show_stats() {
    local period="${1:-week}"
    local since=""

    case "$period" in
        today)   since="midnight" ;;
        week)    since="1 week ago" ;;
        month)   since="1 month ago" ;;
        *)       since="$period" ;;
    esac

    if [ ! -d ".git" ]; then
        echo -e "  ${Y}Not a git repository.${R}"
        return 1
    fi

    local project_name
    project_name=$(basename "$(pwd)")

    echo ""
    echo -e "${O}${B}MangoLove — Productivity Stats${R}"
    echo -e "${DIM}──────────────────────────────────────${R}"
    echo -e "  Project : ${B}${project_name}${R}"
    echo -e "  Period  : ${C}${period}${R} (since ${since})"
    echo ""

    # --- Commit stats (single git log call) ---
    local commit_log
    commit_log=$(git log --since="$since" --oneline --no-merges 2>/dev/null) || true

    local total_commits
    total_commits=$(echo "$commit_log" | grep -c . || true)

    local authors
    authors=$(git log --since="$since" --format="%aN" --no-merges 2>/dev/null | sort -u | wc -l | tr -d ' ') || true

    echo -e "  ${G}Commits${R}"
    echo -e "    Total     : ${B}${total_commits}${R}"
    echo -e "    Authors   : ${DIM}${authors}${R}"

    # Commits by type (from cached log)
    local feat_count fix_count refactor_count test_count docs_count chore_count
    feat_count=$(echo "$commit_log" | grep -c "^[a-f0-9]* feat" || true)
    fix_count=$(echo "$commit_log" | grep -c "^[a-f0-9]* fix" || true)
    refactor_count=$(echo "$commit_log" | grep -c "^[a-f0-9]* refactor" || true)
    test_count=$(echo "$commit_log" | grep -c "^[a-f0-9]* test" || true)
    docs_count=$(echo "$commit_log" | grep -c "^[a-f0-9]* docs" || true)
    chore_count=$(echo "$commit_log" | grep -c "^[a-f0-9]* chore" || true)

    if [ "$total_commits" -gt 0 ]; then
        echo ""
        echo -e "  ${G}By Type${R}"
        [ "$feat_count" -gt 0 ] && echo -e "    feat      : ${feat_count}"
        [ "$fix_count" -gt 0 ] && echo -e "    fix       : ${fix_count}"
        [ "$refactor_count" -gt 0 ] && echo -e "    refactor  : ${refactor_count}"
        [ "$test_count" -gt 0 ] && echo -e "    test      : ${test_count}"
        [ "$docs_count" -gt 0 ] && echo -e "    docs      : ${docs_count}"
        [ "$chore_count" -gt 0 ] && echo -e "    chore     : ${chore_count}"
    fi

    # --- File stats (single git log call for file names) ---
    local file_log
    file_log=$(git log --since="$since" --no-merges --format="" --name-only 2>/dev/null) || true

    echo ""
    echo -e "  ${G}Files Changed${R}"

    local files_changed
    files_changed=$(echo "$file_log" | sort -u | grep -c . || true)
    echo -e "    Unique files : ${B}${files_changed}${R}"

    # Insertions/deletions
    local diff_stats
    diff_stats=$(git log --since="$since" --no-merges --format="" --shortstat 2>/dev/null) || true

    local total_insertions=0
    local total_deletions=0
    while IFS= read -r line; do
        local ins
        ins=$(echo "$line" | grep -o '[0-9]* insertion' | grep -o '[0-9]*') || true
        local del
        del=$(echo "$line" | grep -o '[0-9]* deletion' | grep -o '[0-9]*') || true
        [ -n "$ins" ] && total_insertions=$((total_insertions + ins))
        [ -n "$del" ] && total_deletions=$((total_deletions + del))
    done <<< "$diff_stats"

    echo -e "    Insertions   : ${G}+${total_insertions}${R}"
    echo -e "    Deletions    : ${Y}-${total_deletions}${R}"
    local net=$((total_insertions - total_deletions))
    if [ $net -ge 0 ]; then
        echo -e "    Net          : ${G}+${net}${R}"
    else
        echo -e "    Net          : ${Y}${net}${R}"
    fi

    # --- Most active files (from cached file log) ---
    if [ "$total_commits" -gt 0 ]; then
        echo ""
        echo -e "  ${G}Most Active Files${R}"
        echo "$file_log" | grep -v '^$' | \
            sort | uniq -c | sort -rn | head -5 | \
            while IFS= read -r line; do
                local count file
                count=$(echo "$line" | awk '{print $1}')
                file=$(echo "$line" | awk '{print $2}')
                echo -e "    ${DIM}${count}x${R} ${file}"
            done
    fi

    # --- Branch info ---
    echo ""
    echo -e "  ${G}Branches${R}"
    local branch_count
    branch_count=$(git branch 2>/dev/null | wc -l | tr -d ' ') || true
    local current_branch
    current_branch=$(git branch --show-current 2>/dev/null) || true
    echo -e "    Current  : ${B}${current_branch:-detached}${R}"
    echo -e "    Total    : ${DIM}${branch_count}${R}"

    echo ""
    echo -e "${DIM}──────────────────────────────────────${R}"
    echo ""
}

# ─────────────────────────────────────────────
# Entrypoint
# ─────────────────────────────────────────────
show_stats "${1:-week}"
