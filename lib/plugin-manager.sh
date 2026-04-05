#!/bin/bash
# ─────────────────────────────────────────────
# 🥭 MangoLove — Plugin & Hook Manager
# ─────────────────────────────────────────────

MANGOLOVE_DIR="${MANGOLOVE_DIR:-$HOME/.mangolove}"
PLUGINS_DIR="$MANGOLOVE_DIR/plugins"

# Colors
R='\033[0m'
B='\033[1m'
DIM='\033[2m'
Y='\033[38;5;220m'
O='\033[38;5;208m'
G='\033[38;5;113m'
C='\033[38;5;117m'
RED='\033[38;5;203m'

# ─────────────────────────────────────────────
# Hook System
# Supported hooks:
#   on_session_start  — runs before Claude Code launches
#   on_session_end    — runs after Claude Code exits
#   on_prompt_build   — can append text to system prompt (stdout)
#   on_profile_load   — runs when a project profile is loaded
# ─────────────────────────────────────────────

# Execute all plugins that implement a given hook
run_hook() {
    local hook_name="$1"
    shift
    local hook_args=("$@")

    [ ! -d "$PLUGINS_DIR" ] && return 0

    for plugin_dir in "$PLUGINS_DIR"/*/; do
        [ ! -d "$plugin_dir" ] && continue

        local plugin_script="${plugin_dir}plugin.sh"
        [ ! -f "$plugin_script" ] && continue

        # Check if plugin is enabled
        local config_file="${plugin_dir}config"
        if [ -f "$config_file" ] && grep -q "^enabled=false" "$config_file" 2>/dev/null; then
            continue
        fi

        # Source plugin and call hook if defined
        (
            source "$plugin_script"
            if type "$hook_name" &>/dev/null; then
                "$hook_name" "${hook_args[@]}"
            fi
        )
    done
}

# Collect prompt additions from plugins
collect_prompt_additions() {
    local additions=""

    [ ! -d "$PLUGINS_DIR" ] && return 0

    for plugin_dir in "$PLUGINS_DIR"/*/; do
        [ ! -d "$plugin_dir" ] && continue

        local plugin_script="${plugin_dir}plugin.sh"
        [ ! -f "$plugin_script" ] && continue

        # Check if plugin is enabled
        local config_file="${plugin_dir}config"
        if [ -f "$config_file" ] && grep -q "^enabled=false" "$config_file" 2>/dev/null; then
            continue
        fi

        local result=""
        result=$(
            source "$plugin_script"
            if type "on_prompt_build" &>/dev/null; then
                on_prompt_build
            fi
        )

        if [ -n "$result" ]; then
            additions="${additions}

${result}"
        fi
    done

    echo "$additions"
}

# List installed plugins
list_plugins() {
    echo ""
    echo -e "${O}${B}🥭 MangoLove — Plugins${R}"
    echo -e "${DIM}──────────────────────────────────────${R}"

    local count=0
    for plugin_dir in "$PLUGINS_DIR"/*/; do
        [ ! -d "$plugin_dir" ] && continue

        local plugin_name=$(basename "$plugin_dir")
        local plugin_script="${plugin_dir}plugin.sh"
        [ ! -f "$plugin_script" ] && continue

        # Read plugin metadata
        local description=""
        local version=""
        description=$(grep "^# Description:" "$plugin_script" 2>/dev/null | sed 's/^# Description: *//')
        version=$(grep "^# Version:" "$plugin_script" 2>/dev/null | sed 's/^# Version: *//')

        # Check enabled status
        local config_file="${plugin_dir}config"
        local status="${G}enabled${R}"
        if [ -f "$config_file" ] && grep -q "^enabled=false" "$config_file" 2>/dev/null; then
            status="${DIM}disabled${R}"
        fi

        # Detect implemented hooks
        local hooks=""
        hooks=$(grep -oP '^(on_session_start|on_session_end|on_prompt_build|on_profile_load)\s*\(' "$plugin_script" 2>/dev/null | tr -d '(' | tr '\n' ', ' | sed 's/,$//')

        echo -e "  ${G}▸${R} ${B}${plugin_name}${R} ${DIM}${version}${R} [${status}]"
        [ -n "$description" ] && echo -e "    ${DIM}${description}${R}"
        [ -n "$hooks" ] && echo -e "    ${C}Hooks:${R} ${hooks}"
        echo ""
        count=$((count + 1))
    done

    if [ $count -eq 0 ]; then
        echo -e "  ${DIM}No plugins installed.${R}"
        echo -e "  ${DIM}Add plugins to: ${PLUGINS_DIR}/<name>/plugin.sh${R}"
        echo ""
    fi

    echo -e "${DIM}──────────────────────────────────────${R}"
    echo -e "  ${DIM}Plugins directory: ${PLUGINS_DIR}/${R}"
    echo ""
}

# Enable/disable a plugin
toggle_plugin() {
    local plugin_name="$1"
    local action="$2"  # enable or disable

    if [ -z "$plugin_name" ]; then
        echo "Usage: mangolove plugin [enable|disable] <name>"
        return 1
    fi

    local plugin_dir="$PLUGINS_DIR/$plugin_name"
    if [ ! -d "$plugin_dir" ]; then
        echo -e "  ${RED}✗ Plugin not found:${R} ${plugin_name}"
        return 1
    fi

    local config_file="${plugin_dir}/config"

    case "$action" in
        enable)
            if [ -f "$config_file" ]; then
                sed -i '' 's/^enabled=false/enabled=true/' "$config_file" 2>/dev/null || \
                    sed -i 's/^enabled=false/enabled=true/' "$config_file" 2>/dev/null
            fi
            echo -e "  ${G}✅ Plugin enabled:${R} ${plugin_name}"
            ;;
        disable)
            mkdir -p "$plugin_dir"
            if [ -f "$config_file" ]; then
                sed -i '' 's/^enabled=true/enabled=false/' "$config_file" 2>/dev/null || \
                    sed -i 's/^enabled=true/enabled=false/' "$config_file" 2>/dev/null
            else
                echo "enabled=false" > "$config_file"
            fi
            echo -e "  ${G}✅ Plugin disabled:${R} ${plugin_name}"
            ;;
    esac
}

# Create a new plugin from template
create_plugin() {
    local plugin_name="$1"
    if [ -z "$plugin_name" ]; then
        echo "Usage: mangolove plugin create <name>"
        return 1
    fi

    local plugin_dir="$PLUGINS_DIR/$plugin_name"
    if [ -d "$plugin_dir" ]; then
        echo -e "  ${Y}⚠️  Plugin already exists:${R} ${plugin_name}"
        return 1
    fi

    mkdir -p "$plugin_dir"
    cat > "${plugin_dir}/plugin.sh" << 'TEMPLATE'
#!/bin/bash
# Description: My custom plugin
# Version: 1.0.0

# Called before Claude Code launches
# on_session_start() {
#     echo "Plugin: session starting..."
# }

# Called after Claude Code exits
# on_session_end() {
#     echo "Plugin: session ended"
# }

# Return text to append to system prompt (stdout)
# on_prompt_build() {
#     echo "## Plugin Instructions"
#     echo "Additional instructions from plugin."
# }

# Called when a project profile is loaded
# on_profile_load() {
#     echo "Plugin: profile loaded"
# }
TEMPLATE

    echo "enabled=true" > "${plugin_dir}/config"

    echo -e "  ${G}✅ Plugin created:${R} ${plugin_dir}/plugin.sh"
    echo -e "  ${DIM}Edit the file to implement your hooks.${R}"
}

# Entrypoint
case "${1:-}" in
    list)       list_plugins ;;
    enable)     toggle_plugin "$2" "enable" ;;
    disable)    toggle_plugin "$2" "disable" ;;
    create)     create_plugin "$2" ;;
    hook)       run_hook "$2" "${@:3}" ;;
    prompts)    collect_prompt_additions ;;
    *)          list_plugins ;;
esac
