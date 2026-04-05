#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove — Plugin Manager Tests
# ─────────────────────────────────────────────

load test_helper

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

# ─────────────────────────────────────────────
# list command
# ─────────────────────────────────────────────

@test "list: shows empty state when no plugins installed" {
    run bash "$MANGOLOVE_DIR/lib/plugin-manager.sh" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"No plugins installed"* ]]
}

@test "list: shows installed plugin" {
    mkdir -p "$MANGOLOVE_DIR/plugins/test-plugin"
    cat > "$MANGOLOVE_DIR/plugins/test-plugin/plugin.sh" << 'EOF'
#!/bin/bash
# Description: A test plugin
# Version: 1.0.0

on_session_start() {
    echo "test started"
}
EOF
    echo "enabled=true" > "$MANGOLOVE_DIR/plugins/test-plugin/config"

    run bash "$MANGOLOVE_DIR/lib/plugin-manager.sh" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-plugin"* ]]
    [[ "$output" == *"A test plugin"* ]]
    [[ "$output" == *"1.0.0"* ]]
    [[ "$output" == *"enabled"* ]]
}

@test "list: shows disabled plugin status" {
    mkdir -p "$MANGOLOVE_DIR/plugins/disabled-plugin"
    cat > "$MANGOLOVE_DIR/plugins/disabled-plugin/plugin.sh" << 'EOF'
#!/bin/bash
# Description: Disabled plugin
# Version: 0.1.0
EOF
    echo "enabled=false" > "$MANGOLOVE_DIR/plugins/disabled-plugin/config"

    run bash "$MANGOLOVE_DIR/lib/plugin-manager.sh" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"disabled"* ]]
}

@test "list: detects implemented hooks" {
    mkdir -p "$MANGOLOVE_DIR/plugins/hooks-plugin"
    cat > "$MANGOLOVE_DIR/plugins/hooks-plugin/plugin.sh" << 'EOF'
#!/bin/bash
# Description: Plugin with hooks
# Version: 1.0.0

on_session_start() { echo "start"; }
on_session_end() { echo "end"; }
on_prompt_build() { echo "prompt addition"; }
EOF

    run bash "$MANGOLOVE_DIR/lib/plugin-manager.sh" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"on_session_start"* ]]
    [[ "$output" == *"on_session_end"* ]]
    [[ "$output" == *"on_prompt_build"* ]]
}

# ─────────────────────────────────────────────
# enable / disable commands
# ─────────────────────────────────────────────

@test "enable: enables a disabled plugin" {
    mkdir -p "$MANGOLOVE_DIR/plugins/my-plugin"
    echo '#!/bin/bash' > "$MANGOLOVE_DIR/plugins/my-plugin/plugin.sh"
    echo "enabled=false" > "$MANGOLOVE_DIR/plugins/my-plugin/config"

    run bash "$MANGOLOVE_DIR/lib/plugin-manager.sh" enable "my-plugin"
    [ "$status" -eq 0 ]
    grep -q "enabled=true" "$MANGOLOVE_DIR/plugins/my-plugin/config"
}

@test "disable: disables an enabled plugin" {
    mkdir -p "$MANGOLOVE_DIR/plugins/my-plugin"
    echo '#!/bin/bash' > "$MANGOLOVE_DIR/plugins/my-plugin/plugin.sh"
    echo "enabled=true" > "$MANGOLOVE_DIR/plugins/my-plugin/config"

    run bash "$MANGOLOVE_DIR/lib/plugin-manager.sh" disable "my-plugin"
    [ "$status" -eq 0 ]
    grep -q "enabled=false" "$MANGOLOVE_DIR/plugins/my-plugin/config"
}

@test "enable: fails for non-existent plugin" {
    run bash "$MANGOLOVE_DIR/lib/plugin-manager.sh" enable "nonexistent"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

@test "enable: shows usage when no name given" {
    run bash "$MANGOLOVE_DIR/lib/plugin-manager.sh" enable ""
    [ "$status" -eq 1 ]
}

# ─────────────────────────────────────────────
# create command
# ─────────────────────────────────────────────

@test "create: creates plugin from template" {
    run bash "$MANGOLOVE_DIR/lib/plugin-manager.sh" create "new-plugin"
    [ "$status" -eq 0 ]
    [ -f "$MANGOLOVE_DIR/plugins/new-plugin/plugin.sh" ]
    [ -f "$MANGOLOVE_DIR/plugins/new-plugin/config" ]
    grep -q "enabled=true" "$MANGOLOVE_DIR/plugins/new-plugin/config"
}

@test "create: template contains all hook examples" {
    bash "$MANGOLOVE_DIR/lib/plugin-manager.sh" create "hooks-check"

    local script="$MANGOLOVE_DIR/plugins/hooks-check/plugin.sh"
    grep -q "on_session_start" "$script"
    grep -q "on_session_end" "$script"
    grep -q "on_prompt_build" "$script"
    grep -q "on_profile_load" "$script"
}

@test "create: refuses duplicate plugin" {
    bash "$MANGOLOVE_DIR/lib/plugin-manager.sh" create "dup-plugin"
    run bash "$MANGOLOVE_DIR/lib/plugin-manager.sh" create "dup-plugin"
    [ "$status" -eq 1 ]
    [[ "$output" == *"already exists"* ]]
}

@test "create: shows usage when no name given" {
    run bash "$MANGOLOVE_DIR/lib/plugin-manager.sh" create ""
    [ "$status" -eq 1 ]
}

# ─────────────────────────────────────────────
# hook execution
# ─────────────────────────────────────────────

@test "hook: executes enabled plugin hooks" {
    mkdir -p "$MANGOLOVE_DIR/plugins/active"
    cat > "$MANGOLOVE_DIR/plugins/active/plugin.sh" << 'EOF'
#!/bin/bash
on_session_start() {
    echo "HOOK_EXECUTED"
}
EOF
    echo "enabled=true" > "$MANGOLOVE_DIR/plugins/active/config"

    run bash "$MANGOLOVE_DIR/lib/plugin-manager.sh" hook "on_session_start"
    [ "$status" -eq 0 ]
    [[ "$output" == *"HOOK_EXECUTED"* ]]
}

@test "hook: skips disabled plugin hooks" {
    mkdir -p "$MANGOLOVE_DIR/plugins/inactive"
    cat > "$MANGOLOVE_DIR/plugins/inactive/plugin.sh" << 'EOF'
#!/bin/bash
on_session_start() {
    echo "SHOULD_NOT_APPEAR"
}
EOF
    echo "enabled=false" > "$MANGOLOVE_DIR/plugins/inactive/config"

    run bash "$MANGOLOVE_DIR/lib/plugin-manager.sh" hook "on_session_start"
    [ "$status" -eq 0 ]
    [[ "$output" != *"SHOULD_NOT_APPEAR"* ]]
}

@test "hook: runs multiple plugins in order" {
    mkdir -p "$MANGOLOVE_DIR/plugins/alpha"
    cat > "$MANGOLOVE_DIR/plugins/alpha/plugin.sh" << 'EOF'
#!/bin/bash
on_session_start() { echo "ALPHA"; }
EOF

    mkdir -p "$MANGOLOVE_DIR/plugins/beta"
    cat > "$MANGOLOVE_DIR/plugins/beta/plugin.sh" << 'EOF'
#!/bin/bash
on_session_start() { echo "BETA"; }
EOF

    run bash "$MANGOLOVE_DIR/lib/plugin-manager.sh" hook "on_session_start"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALPHA"* ]]
    [[ "$output" == *"BETA"* ]]
}

@test "hook: no error when no plugins exist" {
    run bash "$MANGOLOVE_DIR/lib/plugin-manager.sh" hook "on_session_start"
    [ "$status" -eq 0 ]
}

# ─────────────────────────────────────────────
# prompt additions
# ─────────────────────────────────────────────

@test "prompts: collects prompt additions from plugins" {
    mkdir -p "$MANGOLOVE_DIR/plugins/prompt-plugin"
    cat > "$MANGOLOVE_DIR/plugins/prompt-plugin/plugin.sh" << 'EOF'
#!/bin/bash
on_prompt_build() {
    echo "## Extra Instructions"
    echo "Always use TypeScript strict mode."
}
EOF

    run bash "$MANGOLOVE_DIR/lib/plugin-manager.sh" prompts
    [ "$status" -eq 0 ]
    [[ "$output" == *"Extra Instructions"* ]]
    [[ "$output" == *"TypeScript strict mode"* ]]
}

@test "prompts: empty when no plugins have on_prompt_build" {
    mkdir -p "$MANGOLOVE_DIR/plugins/no-prompt"
    cat > "$MANGOLOVE_DIR/plugins/no-prompt/plugin.sh" << 'EOF'
#!/bin/bash
on_session_start() { echo "start"; }
EOF

    run bash "$MANGOLOVE_DIR/lib/plugin-manager.sh" prompts
    [ "$status" -eq 0 ]
}
