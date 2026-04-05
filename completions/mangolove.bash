#!/bin/bash
# ─────────────────────────────────────────────
# 🥭 MangoLove — Bash Completion
# ─────────────────────────────────────────────

_mangolove_completions() {
    local cur prev
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    local commands="help projects profile log update doctor --version -v --help -h --mode -m --model --effort -c --continue -r --resume -p"
    local profile_cmds="add auto remove"
    local log_cmds="init view search recent"
    local modes=""
    local models="opus sonnet haiku"
    local efforts="low medium high max auto"

    # Dynamically load available modes
    local modes_dir="${MANGOLOVE_DIR:-$HOME/.mangolove}/prompts/modes"
    if [ -d "$modes_dir" ]; then
        for f in "$modes_dir"/*.md; do
            [ -f "$f" ] && modes="$modes $(basename "$f" .md)"
        done
    fi

    case "${COMP_WORDS[1]}" in
        profile)
            case "$prev" in
                profile)
                    COMPREPLY=($(compgen -W "$profile_cmds" -- "$cur"))
                    ;;
                remove)
                    local profiles=""
                    local projects_dir="${MANGOLOVE_DIR:-$HOME/.mangolove}/projects"
                    if [ -d "$projects_dir" ]; then
                        for f in "$projects_dir"/*.md; do
                            [ "$(basename "$f")" = "README.md" ] && continue
                            [ -f "$f" ] && profiles="$profiles $(basename "$f" .md)"
                        done
                    fi
                    COMPREPLY=($(compgen -W "$profiles" -- "$cur"))
                    ;;
                auto)
                    COMPREPLY=($(compgen -d -- "$cur"))
                    ;;
            esac
            return
            ;;
        log)
            if [ "$prev" = "log" ]; then
                COMPREPLY=($(compgen -W "$log_cmds" -- "$cur"))
            fi
            return
            ;;
        --mode|-m)
            if [ "$prev" = "--mode" ] || [ "$prev" = "-m" ]; then
                COMPREPLY=($(compgen -W "$modes" -- "$cur"))
            fi
            return
            ;;
        --model)
            if [ "$prev" = "--model" ]; then
                COMPREPLY=($(compgen -W "$models" -- "$cur"))
            fi
            return
            ;;
        --effort)
            if [ "$prev" = "--effort" ]; then
                COMPREPLY=($(compgen -W "$efforts" -- "$cur"))
            fi
            return
            ;;
    esac

    if [ $COMP_CWORD -eq 1 ]; then
        COMPREPLY=($(compgen -W "$commands" -- "$cur"))
    fi
}

complete -F _mangolove_completions mangolove
