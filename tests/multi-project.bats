#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove — Multi-project root detection
# bin/mangolove: detect_multi_project_root / _ml_has_build_marker
# ─────────────────────────────────────────────

load test_helper

setup() {
    setup_test_env
    cp "$BATS_TEST_DIRNAME/../bin/mangolove" "$MANGOLOVE_DIR/bin/mangolove"
    chmod +x "$MANGOLOVE_DIR/bin/mangolove"
    # Scratch root in which each test builds a directory scenario.
    SCENARIO="$TEST_DIR/scenario"
    mkdir -p "$SCENARIO"
}

teardown() {
    teardown_test_env
}

# Make $SCENARIO/<name> a standalone git project carrying the given build marker.
mk_subproject() {
    local name="$1" marker="$2"
    mkdir -p "$SCENARIO/$name/.git"
    touch "$SCENARIO/$name/$marker"
}

# Source the binary (its BASH_SOURCE guard keeps main() from running), cd into $SCENARIO,
# and print the picker list. HOME is forced to $1 so the $HOME guard can be exercised.
run_detect() {
    HOME="$1" bash -c '
        source "$1/bin/mangolove" >/dev/null 2>&1
        cd "$2" || exit 1
        detect_multi_project_root
    ' _ "$MANGOLOVE_DIR" "$SCENARIO"
}

# ─────────────────────────────────────────────
# Positive: a genuine multi-project root
# ─────────────────────────────────────────────

@test "multi-project: lists sub-projects when CWD is a multi-project root" {
    mk_subproject alpha build.gradle
    mk_subproject beta package.json
    run run_detect "$TEST_DIR/not-home"
    [ "$status" -eq 0 ]
    [[ "$output" == *"alpha"* ]]
    [[ "$output" == *"beta"* ]]
}

# ─────────────────────────────────────────────
# Guard: never at $HOME (the false-positive this change fixes)
# ─────────────────────────────────────────────

@test "multi-project: no picker at \$HOME even with sub-projects" {
    mk_subproject alpha build.gradle
    mk_subproject beta package.json
    run run_detect "$SCENARIO"   # HOME == CWD
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─────────────────────────────────────────────
# Guard: CWD is itself a project — unified 7-marker set (go.mod used to slip through)
# ─────────────────────────────────────────────

@test "multi-project: no picker when CWD is itself a Go project (go.mod)" {
    mk_subproject alpha build.gradle
    mk_subproject beta package.json
    touch "$SCENARIO/go.mod"
    run run_detect "$TEST_DIR/not-home"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "multi-project: no picker when CWD is itself a project (build.gradle)" {
    mk_subproject alpha build.gradle
    mk_subproject beta package.json
    touch "$SCENARIO/build.gradle"
    run run_detect "$TEST_DIR/not-home"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─────────────────────────────────────────────
# Guard: needs >=2 qualifying sub-projects
# ─────────────────────────────────────────────

@test "multi-project: no picker with only one sub-project" {
    mk_subproject alpha build.gradle
    run run_detect "$TEST_DIR/not-home"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "multi-project: sub-dir with .git but no build marker is not counted" {
    mkdir -p "$SCENARIO/alpha/.git"
    mkdir -p "$SCENARIO/beta/.git"
    run run_detect "$TEST_DIR/not-home"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
