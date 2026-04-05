#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove — Work Logger Tests
# ────────────────────────────────────���────────

load test_helper

setup() {
    setup_test_env
    export MANGOLOVE_LOG_REPO="disabled"
}

teardown() {
    teardown_test_env
}

# ─────────────────────────────────────────────
# entrypoint
# ─────────────────────────────────────────────

@test "shows usage for unknown command" {
    run bash "$MANGOLOVE_DIR/lib/work-logger.sh" unknown
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "shows usage with no arguments" {
    run bash "$MANGOLOVE_DIR/lib/work-logger.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

# ─────────────────────────────────────────────
# init with disabled logging
# ─────────────────────────────────────────────

@test "init: reports disabled when MANGOLOVE_LOG_REPO=disabled" {
    run bash "$MANGOLOVE_DIR/lib/work-logger.sh" init
    [ "$status" -eq 0 ]
    [[ "$output" == *"disabled"* ]]
}

# ─────────────────────────────────────────────
# start with disabled logging
# ─────────────────────────────────────────────

@test "start: exits cleanly when logging disabled" {
    run bash "$MANGOLOVE_DIR/lib/work-logger.sh" start
    [ "$status" -eq 0 ]
}

@test "end: exits cleanly when logging disabled" {
    run bash "$MANGOLOVE_DIR/lib/work-logger.sh" end
    [ "$status" -eq 0 ]
}

# ─────────────────────────────────────────────
# search command
# ─────────────────────────────────────────────

@test "search: shows usage when no keyword given" {
    run bash "$MANGOLOVE_DIR/lib/work-logger.sh" search
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "search: reports no logs when directory is empty" {
    # Ensure log repo exists but is empty
    mkdir -p "$MANGOLOVE_DIR/logs/repo"
    run bash "$MANGOLOVE_DIR/lib/work-logger.sh" search "test"
    [[ "$output" == *"No logs found"* ]] || [ "$status" -eq 0 ]
}

# ─────────────────────────────────────────────
# recent command
# ─────────────────────────────────────────────

@test "recent: handles missing log repo gracefully" {
    mkdir -p "$MANGOLOVE_DIR/logs/repo"
    # recent requires get_repo_info which needs gh when MANGOLOVE_LOG_REPO is not set
    # With disabled, get_repo_info sets REPO_FULL but LOCAL_REPO/logs may not exist
    export MANGOLOVE_LOG_REPO="testuser/test-logs"
    run bash "$MANGOLOVE_DIR/lib/work-logger.sh" recent
    # Should either succeed or report no logs
    [[ "$status" -eq 0 ]] || [[ "$output" == *"No logs"* ]]
}
