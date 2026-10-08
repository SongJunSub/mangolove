#!/bin/bash
# ─────────────────────────────────────────────
# MangoLove: Test Helper
# Shared setup/teardown for all BATS tests
# ─────────────────────────────────────────────

# Create isolated test environment
setup_test_env() {
    export TEST_DIR=$(mktemp -d)
    export MANGOLOVE_DIR="$TEST_DIR/.mangolove"

    mkdir -p "$MANGOLOVE_DIR"/{bin,lib,prompts/modes,projects,plugins,logs,completions}

    # Copy lib scripts (colors.sh must come first as other scripts source it)
    cp "$BATS_TEST_DIRNAME/../lib/"*.sh "$MANGOLOVE_DIR/lib/"

    # Copy prompts
    cp "$BATS_TEST_DIRNAME/../prompts/system-prompt.md" "$MANGOLOVE_DIR/prompts/"
    cp "$BATS_TEST_DIRNAME/../prompts/modes/"*.md "$MANGOLOVE_DIR/prompts/modes/"

    # Create minimal config
    cat > "$MANGOLOVE_DIR/config.sh" << 'EOF'
MANGOLOVE_AUTO_LOG=false
MANGOLOVE_SHOW_BANNER=false
MANGOLOVE_EXTRA_PROMPT=""
MANGOLOVE_MODEL=""
MANGOLOVE_EFFORT=""
MANGOLOVE_LOG_REPO="disabled"
EOF
}

# PATH 앞에 둘 가짜 claude 를 만든다. 스크립트 본문(셔뱅 제외)은 stdin 으로 받는다.
# 쓰는 쪽: run env PATH="$TEST_DIR/fakebin:$PATH" ...
install_fake_claude() {
    mkdir -p "$TEST_DIR/fakebin"
    { echo '#!/bin/bash'; cat; } > "$TEST_DIR/fakebin/claude"
    chmod +x "$TEST_DIR/fakebin/claude"
}

# Cleanup test environment
teardown_test_env() {
    [ -d "$TEST_DIR" ] && rm -rf "$TEST_DIR"
}

# Create a fake project directory with specified build files
create_fake_project() {
    local project_dir="$TEST_DIR/projects/$1"
    mkdir -p "$project_dir"
    echo "$project_dir"
}
