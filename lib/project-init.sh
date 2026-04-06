#!/bin/bash
# ─────────────────────────────────────────────
# MangoLove — Project Initializer
# Generates CLAUDE.md, .claude/commands/, and hooks
# for optimal Claude Code experience
# ─────────────────────────────────────────────

set -o pipefail

MANGOLOVE_DIR="${MANGOLOVE_DIR:-$HOME/.mangolove}"

# Colors
R='\033[0m'
B='\033[1m'
DIM='\033[2m'
O='\033[38;5;208m'
G='\033[38;5;113m'
C='\033[38;5;117m'
RED='\033[38;5;203m'
Y='\033[38;5;220m'

# ─────────────────────────────────────────────
# Project scanner — detect everything about the project
# ─────────────────────────────────────────────
scan_project() {
    local dir="$1"

    # Results stored in global variables
    PROJ_NAME=$(basename "$dir")
    PROJ_TECH=()
    PROJ_BUILD=""
    PROJ_TEST=""
    PROJ_LINT=""
    PROJ_TYPECHECK=""
    PROJ_MODULES=""
    PROJ_PKG_MGR=""
    export PROJ_FRAMEWORK=""
    PROJ_DB=()
    PROJ_INFRA=()
    export PROJ_STRUCTURE=""

    # --- Gradle (Java/Kotlin) ---
    if [ -f "$dir/build.gradle" ] || [ -f "$dir/build.gradle.kts" ]; then
        [ -f "$dir/build.gradle.kts" ] && PROJ_TECH+=("Kotlin")

        if [ -d "$dir/src/main/java" ] || find "$dir" -maxdepth 6 -name "*.java" -print -quit 2>/dev/null | grep -q .; then
            [[ ! " ${PROJ_TECH[*]} " =~ " Java " ]] && PROJ_TECH+=("Java")
        fi
        if [ -d "$dir/src/main/kotlin" ] || find "$dir" -maxdepth 6 -name "*.kt" -print -quit 2>/dev/null | grep -q .; then
            [[ ! " ${PROJ_TECH[*]} " =~ " Kotlin " ]] && PROJ_TECH+=("Kotlin")
        fi

        # Frameworks
        if grep -rq "org.springframework.boot" "$dir/build.gradle"* 2>/dev/null; then
            # Spring Boot implies Java at minimum
            [[ ! " ${PROJ_TECH[*]} " =~ " Java " ]] && PROJ_TECH+=("Java")
            PROJ_TECH+=("Spring Boot")
            PROJ_FRAMEWORK="Spring Boot"
        fi
        grep -rq "spring-boot-starter-data-jpa\|jakarta.persistence" "$dir/build.gradle"* 2>/dev/null && PROJ_TECH+=("JPA")
        grep -rq "querydsl" "$dir/build.gradle"* 2>/dev/null && PROJ_TECH+=("QueryDSL")
        grep -rq "spring-boot-starter-webflux\|spring-webflux" "$dir/build.gradle"* 2>/dev/null && PROJ_TECH+=("WebFlux")

        # Databases
        grep -rq "mysql" "$dir/build.gradle"* 2>/dev/null && PROJ_DB+=("MySQL")
        grep -rq "postgresql\|postgres" "$dir/build.gradle"* 2>/dev/null && PROJ_DB+=("PostgreSQL")
        grep -rq "mongodb\|mongo" "$dir/build.gradle"* 2>/dev/null && PROJ_DB+=("MongoDB")
        grep -rq "redis\|lettuce\|jedis" "$dir/build.gradle"* 2>/dev/null && PROJ_DB+=("Redis")
        grep -rq "elasticsearch\|opensearch" "$dir/build.gradle"* 2>/dev/null && PROJ_DB+=("ElasticSearch")

        # Messaging
        grep -rq "kafka" "$dir/build.gradle"* 2>/dev/null && PROJ_INFRA+=("Kafka")
        grep -rq "rabbitmq\|amqp" "$dir/build.gradle"* 2>/dev/null && PROJ_INFRA+=("RabbitMQ")

        # Commands
        if [ -f "$dir/gradlew" ]; then
            PROJ_BUILD="./gradlew build"
            PROJ_TEST="./gradlew test"
            PROJ_LINT="./gradlew check"
        else
            PROJ_BUILD="gradle build"
            PROJ_TEST="gradle test"
            PROJ_LINT="gradle check"
        fi

        # Detect spotless/checkstyle
        if grep -rq "spotless" "$dir/build.gradle"* 2>/dev/null; then
            PROJ_LINT="./gradlew spotlessCheck"
        fi

        # Multi-module
        if [ -f "$dir/settings.gradle" ] || [ -f "$dir/settings.gradle.kts" ]; then
            local settings_file="$dir/settings.gradle"
            [ -f "$dir/settings.gradle.kts" ] && settings_file="$dir/settings.gradle.kts"
            PROJ_MODULES=$(grep "include" "$settings_file" 2>/dev/null | sed "s/.*include//;s/[\"'()]//g;s/://g" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | grep -v '^$' | tr '\n' ', ' | sed 's/,$//')
        fi

        # Detect package structure
        local base_pkg=""
        base_pkg=$(find "$dir/src/main" -type f \( -name "*.java" -o -name "*.kt" \) -print -quit 2>/dev/null | sed 's|.*/src/main/[^/]*/||;s|/[^/]*$||;s|/|.|g')
        [ -n "$base_pkg" ] && PROJ_STRUCTURE="$base_pkg"
    fi

    # --- Maven ---
    if [ -f "$dir/pom.xml" ]; then
        [[ ! " ${PROJ_TECH[*]} " =~ " Java " ]] && PROJ_TECH+=("Java")
        grep -q "spring-boot" "$dir/pom.xml" 2>/dev/null && { [[ ! " ${PROJ_TECH[*]} " =~ " Spring Boot " ]] && PROJ_TECH+=("Spring Boot"); PROJ_FRAMEWORK="Spring Boot"; }
        grep -q "spring-boot-starter-data-jpa" "$dir/pom.xml" 2>/dev/null && { [[ ! " ${PROJ_TECH[*]} " =~ " JPA " ]] && PROJ_TECH+=("JPA"); }

        if [ -f "$dir/mvnw" ]; then
            PROJ_BUILD="./mvnw package"
            PROJ_TEST="./mvnw test"
        else
            PROJ_BUILD="mvn package"
            PROJ_TEST="mvn test"
        fi
    fi

    # --- Node.js ---
    if [ -f "$dir/package.json" ]; then
        PROJ_TECH+=("Node.js")
        [ -f "$dir/tsconfig.json" ] && PROJ_TECH+=("TypeScript")

        grep -q '"react"' "$dir/package.json" 2>/dev/null && { PROJ_TECH+=("React"); PROJ_FRAMEWORK="React"; }
        grep -q '"next"' "$dir/package.json" 2>/dev/null && { PROJ_TECH+=("Next.js"); PROJ_FRAMEWORK="Next.js"; }
        grep -q '"vue"' "$dir/package.json" 2>/dev/null && { PROJ_TECH+=("Vue"); PROJ_FRAMEWORK="Vue"; }
        grep -q '"express"' "$dir/package.json" 2>/dev/null && { PROJ_TECH+=("Express"); PROJ_FRAMEWORK="Express"; }
        grep -qE '"@nestjs"' "$dir/package.json" 2>/dev/null && { PROJ_TECH+=("NestJS"); PROJ_FRAMEWORK="NestJS"; }

        # Package manager
        PROJ_PKG_MGR="npm"
        [ -f "$dir/yarn.lock" ] && PROJ_PKG_MGR="yarn"
        [ -f "$dir/pnpm-lock.yaml" ] && PROJ_PKG_MGR="pnpm"
        [ -f "$dir/bun.lockb" ] && PROJ_PKG_MGR="bun"

        PROJ_BUILD="${PROJ_PKG_MGR} run build"
        PROJ_TEST="${PROJ_PKG_MGR} run test"

        # Detect linter
        if [ -f "$dir/.eslintrc.js" ] || [ -f "$dir/.eslintrc.json" ] || [ -f "$dir/.eslintrc.yml" ] || [ -f "$dir/eslint.config.js" ] || [ -f "$dir/eslint.config.mjs" ]; then
            PROJ_LINT="${PROJ_PKG_MGR} run lint"
        fi

        # TypeScript type check
        [ -f "$dir/tsconfig.json" ] && PROJ_TYPECHECK="npx tsc --noEmit"
    fi

    # --- Python ---
    if [ -f "$dir/pyproject.toml" ] || [ -f "$dir/setup.py" ] || [ -f "$dir/requirements.txt" ]; then
        PROJ_TECH+=("Python")
        grep -rq "django" "$dir/requirements.txt" "$dir/pyproject.toml" 2>/dev/null && { PROJ_TECH+=("Django"); PROJ_FRAMEWORK="Django"; }
        grep -rq "fastapi" "$dir/requirements.txt" "$dir/pyproject.toml" 2>/dev/null && { PROJ_TECH+=("FastAPI"); PROJ_FRAMEWORK="FastAPI"; }
        grep -rq "flask" "$dir/requirements.txt" "$dir/pyproject.toml" 2>/dev/null && { PROJ_TECH+=("Flask"); PROJ_FRAMEWORK="Flask"; }
        [ -z "$PROJ_TEST" ] && PROJ_TEST="pytest"
        # Detect linter
        if grep -rq "ruff" "$dir/pyproject.toml" 2>/dev/null; then
            PROJ_LINT="ruff check ."
        elif [ -f "$dir/.flake8" ] || grep -rq "flake8" "$dir/pyproject.toml" 2>/dev/null; then
            PROJ_LINT="flake8"
        fi
        grep -rq "mypy" "$dir/pyproject.toml" 2>/dev/null && PROJ_TYPECHECK="mypy ."
    fi

    # --- Go ---
    if [ -f "$dir/go.mod" ]; then
        PROJ_TECH+=("Go")
        [ -z "$PROJ_BUILD" ] && PROJ_BUILD="go build ./..."
        [ -z "$PROJ_TEST" ] && PROJ_TEST="go test ./..."
        PROJ_LINT="golangci-lint run"
    fi

    # --- Rust ---
    if [ -f "$dir/Cargo.toml" ]; then
        PROJ_TECH+=("Rust")
        [ -z "$PROJ_BUILD" ] && PROJ_BUILD="cargo build"
        [ -z "$PROJ_TEST" ] && PROJ_TEST="cargo test"
        PROJ_LINT="cargo clippy"
    fi

    # --- Infrastructure ---
    [ -f "$dir/Dockerfile" ] || [ -f "$dir/docker-compose.yml" ] || [ -f "$dir/docker-compose.yaml" ] && PROJ_INFRA+=("Docker")
    { [ -d "$dir/k8s" ] || [ -d "$dir/kubernetes" ]; } && PROJ_INFRA+=("Kubernetes")
    [ -d "$dir/.github/workflows" ] && PROJ_INFRA+=("GitHub Actions")
    [ -f "$dir/Jenkinsfile" ] && PROJ_INFRA+=("Jenkins")
    [ -d "$dir/terraform" ] || [ -f "$dir/main.tf" ] && PROJ_INFRA+=("Terraform")
}

# ─────────────────────────────────────────────
# Detect directory structure (top 2 levels of src)
# ─────────────────────────────────────────────
detect_directories() {
    local dir="$1"
    local result=""

    # For Java/Kotlin projects
    if [ -d "$dir/src/main" ]; then
        result=$(find "$dir/src/main" -type d -maxdepth 4 -mindepth 2 2>/dev/null | \
            sed "s|$dir/||" | sort | head -30)
    fi

    # For Node.js projects
    if [ -d "$dir/src" ] && [ -f "$dir/package.json" ]; then
        result=$(find "$dir/src" -type d -maxdepth 3 2>/dev/null | \
            sed "s|$dir/||" | sort | head -30)
    fi

    # For Python projects
    if [ -f "$dir/pyproject.toml" ] || [ -f "$dir/setup.py" ]; then
        result=$(find "$dir" -type d -maxdepth 3 -not -path '*/\.*' -not -path '*/node_modules/*' -not -path '*/__pycache__/*' -not -path '*/venv/*' 2>/dev/null | \
            sed "s|$dir/||" | grep -v "^$" | sort | head -30)
    fi

    echo "$result"
}

# ─────────────────────────────────────────────
# Generate CLAUDE.md
# ─────────────────────────────────────────────
generate_claude_md() {
    local dir="$1"
    local strict="$2"

    local tech_str db_str infra_str
    tech_str=$(printf '%s, ' "${PROJ_TECH[@]}" | sed 's/, $//')
    db_str=$(printf '%s, ' "${PROJ_DB[@]}" | sed 's/, $//')
    infra_str=$(printf '%s, ' "${PROJ_INFRA[@]}" | sed 's/, $//')

    local content="# ${PROJ_NAME}

## Tech Stack
- ${tech_str}
$([ ${#PROJ_DB[@]} -gt 0 ] && echo "- Database: ${db_str}")
$([ ${#PROJ_INFRA[@]} -gt 0 ] && echo "- Infrastructure: ${infra_str}")

## Commands
- Build: \`${PROJ_BUILD}\`
- Test: \`${PROJ_TEST}\`"

    [ -n "$PROJ_LINT" ] && content="${content}
- Lint: \`${PROJ_LINT}\`"

    [ -n "$PROJ_TYPECHECK" ] && content="${content}
- Type Check: \`${PROJ_TYPECHECK}\`"

    [ -n "$PROJ_MODULES" ] && content="${content}

## Modules
$(echo "$PROJ_MODULES" | tr ',' '\n' | sed 's/^ */- /')"

    # Detect and list key directories
    local dirs
    dirs=$(detect_directories "$dir")
    if [ -n "$dirs" ]; then
        content="${content}

## Project Structure
\`\`\`
$(echo "$dirs" | head -20)
\`\`\`"
    fi

    # Add conventions based on detected stack
    content="${content}

## Conventions"

    # shellcheck disable=SC2076
    if [[ " ${PROJ_TECH[*]} " =~ " Java " ]] || [[ " ${PROJ_TECH[*]} " =~ " Kotlin " ]]; then
        content="${content}
- Follow Google Java Style Guide (4-space indent, 100-char line limit)
- Use Conventional Commits for commit messages
- All public APIs must have Javadoc/KDoc"
    fi

    # shellcheck disable=SC2076
    if [[ " ${PROJ_TECH[*]} " =~ " TypeScript " ]] || [[ " ${PROJ_TECH[*]} " =~ " Node.js " ]]; then
        content="${content}
- Follow Google TypeScript Style Guide (2-space indent, single quotes)
- Use Conventional Commits for commit messages
- No \`any\` type — use \`unknown\` or specific types"
    fi

    # shellcheck disable=SC2076
    if [[ " ${PROJ_TECH[*]} " =~ " Python " ]]; then
        content="${content}
- Follow PEP 8 style guide
- Use type hints for all function signatures
- Use Conventional Commits for commit messages"
    fi

    # shellcheck disable=SC2076
    if [[ " ${PROJ_TECH[*]} " =~ " Go " ]]; then
        content="${content}
- Follow Effective Go conventions
- Run \`gofmt\` before committing
- Use Conventional Commits for commit messages"
    fi

    # shellcheck disable=SC2076
    if [[ " ${PROJ_TECH[*]} " =~ " Rust " ]]; then
        content="${content}
- Follow Rust API guidelines
- Run \`cargo fmt\` before committing
- Use Conventional Commits for commit messages"
    fi

    # Strict mode additions
    if [ "$strict" = "true" ]; then
        content="${content}

## Quality Rules
- NEVER skip tests. Run \`${PROJ_TEST}\` after every code change.
- NEVER commit without passing lint. Run \`${PROJ_LINT:-echo 'no linter configured'}\` first.
- Write tests for all new functions and bug fixes.
- All PRs must include test coverage for changed code."
    fi

    echo "$content"
}

# ─────────────────────────────────────────────
# Generate .claude/commands/
# ─────────────────────────────────────────────
generate_commands() {
    local dir="$1"
    local cmd_dir="$dir/.claude/commands"
    mkdir -p "$cmd_dir"

    # /test command
    if [ -n "$PROJ_TEST" ]; then
        cat > "$cmd_dir/test.md" << EOF
Run the project test suite and report results.

\`\`\`bash
${PROJ_TEST}
\`\`\`

If tests fail, analyze the failures and suggest fixes.
EOF
    fi

    # /build command
    if [ -n "$PROJ_BUILD" ]; then
        cat > "$cmd_dir/build.md" << EOF
Build the project and report any errors.

\`\`\`bash
${PROJ_BUILD}
\`\`\`

If the build fails, analyze the error and fix it.
EOF
    fi

    # /lint command
    if [ -n "$PROJ_LINT" ]; then
        cat > "$cmd_dir/lint.md" << EOF
Run the linter and fix all issues found.

\`\`\`bash
${PROJ_LINT}
\`\`\`

Fix all warnings and errors. Do not suppress warnings without justification.
EOF
    fi

    # /review command
    cat > "$cmd_dir/review.md" << EOF
Review the staged changes (or recent commits if nothing staged) for:

1. Correctness — logic errors, edge cases, null safety
2. Security — injection, auth gaps, data exposure
3. Performance — N+1 queries, unnecessary allocations
4. Style — naming, readability, consistency with codebase

Report each issue with file path, line number, severity, and suggested fix.
EOF

    # /check command — run full validation pipeline
    local check_steps="echo '--- Build ---' && ${PROJ_BUILD}"
    [ -n "$PROJ_LINT" ] && check_steps="${check_steps} && echo '--- Lint ---' && ${PROJ_LINT}"
    [ -n "$PROJ_TYPECHECK" ] && check_steps="${check_steps} && echo '--- Type Check ---' && ${PROJ_TYPECHECK}"
    check_steps="${check_steps} && echo '--- Test ---' && ${PROJ_TEST}"

    cat > "$cmd_dir/check.md" << EOF
Run the full validation pipeline: build, lint, type check, and test.

\`\`\`bash
${check_steps}
\`\`\`

Report the result of each step. If any step fails, fix the issue before proceeding.
EOF
}

# ─────────────────────────────────────────────
# Generate .claude/settings.json with hooks
# ─────────────────────────────────────────────
generate_settings() {
    local dir="$1"
    local strict="$2"
    local settings_dir="$dir/.claude"
    mkdir -p "$settings_dir"

    local settings_file="$settings_dir/settings.json"

    # Don't overwrite existing settings
    if [ -f "$settings_file" ]; then
        echo -e "  ${Y}Skipped:${R} .claude/settings.json already exists"
        return 0
    fi

    if [ "$strict" = "true" ] && [ -n "$PROJ_TEST" ]; then
        cat > "$settings_file" << SETTINGSEOF
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "echo 'Remember: run tests after code changes'"
          }
        ]
      }
    ]
  }
}
SETTINGSEOF
    else
        cat > "$settings_file" << 'SETTINGSEOF'
{
  "hooks": {}
}
SETTINGSEOF
    fi
}

# ─────────────────────────────────────────────
# Main: mangolove init
# ─────────────────────────────────────────────
do_init() {
    local target_dir
    target_dir=$(pwd)
    local strict="false"
    local force="false"

    # Parse flags
    while [ $# -gt 0 ]; do
        case "$1" in
            --strict) strict="true"; shift ;;
            --force)  force="true"; shift ;;
            *)        target_dir="$1"; shift ;;
        esac
    done

    if ! target_dir=$(cd "$target_dir" 2>/dev/null && pwd); then
        echo -e "  ${RED}Directory not found:${R} ${1}"
        return 1
    fi

    echo ""
    echo -e "${O}${B}MangoLove Init${R}"
    echo -e "${DIM}──────────────────────────────────────${R}"
    echo -e "  Scanning: ${B}${target_dir}${R}"
    [ "$strict" = "true" ] && echo -e "  Mode: ${Y}strict${R} (quality gates enabled)"
    echo ""

    # Check if CLAUDE.md already exists
    if [ -f "$target_dir/CLAUDE.md" ] && [ "$force" != "true" ]; then
        echo -e "  ${Y}CLAUDE.md already exists.${R}"
        echo -e "  Use ${B}mangolove init --force${R} to regenerate."
        echo ""
        return 1
    fi

    # Scan project
    scan_project "$target_dir"

    if [ ${#PROJ_TECH[@]} -eq 0 ]; then
        echo -e "  ${Y}No recognized project structure found.${R}"
        echo -e "  ${DIM}Supported: Java/Kotlin (Gradle/Maven), Node.js, Python, Go, Rust${R}"
        echo ""
        return 1
    fi

    # Report detection
    echo -e "  ${G}Detected:${R}"
    echo -e "    Tech Stack : ${C}$(IFS=', '; echo "${PROJ_TECH[*]}")${R}"
    [ ${#PROJ_DB[@]} -gt 0 ] && echo -e "    Database   : ${C}$(IFS=', '; echo "${PROJ_DB[*]}")${R}"
    [ ${#PROJ_INFRA[@]} -gt 0 ] && echo -e "    Infra      : ${C}$(IFS=', '; echo "${PROJ_INFRA[*]}")${R}"
    echo -e "    Build      : ${DIM}${PROJ_BUILD}${R}"
    echo -e "    Test       : ${DIM}${PROJ_TEST}${R}"
    [ -n "$PROJ_LINT" ] && echo -e "    Lint       : ${DIM}${PROJ_LINT}${R}"
    [ -n "$PROJ_MODULES" ] && echo -e "    Modules    : ${DIM}${PROJ_MODULES}${R}"
    echo ""

    # Generate files
    echo -e "  ${G}Generating:${R}"

    # 1. CLAUDE.md
    local claude_md
    claude_md=$(generate_claude_md "$target_dir" "$strict")
    echo "$claude_md" > "$target_dir/CLAUDE.md"
    echo -e "    ${G}+${R} CLAUDE.md"

    # 2. .claude/commands/
    generate_commands "$target_dir"
    local cmd_count
    cmd_count=$(find "$target_dir/.claude/commands" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
    echo -e "    ${G}+${R} .claude/commands/ (${cmd_count} commands)"

    # 3. .claude/settings.json
    generate_settings "$target_dir" "$strict"
    echo -e "    ${G}+${R} .claude/settings.json"

    echo ""
    echo -e "${DIM}──────────────────────────────────────${R}"
    echo -e "  ${G}Done.${R} Your project is now optimized for Claude Code."
    echo ""
    echo -e "  ${DIM}Next steps:${R}"
    echo -e "    1. Review and edit CLAUDE.md to add project-specific details"
    echo -e "    2. Run ${B}claude${R} in this directory"
    echo -e "    3. Try ${B}/test${R}, ${B}/build${R}, ${B}/lint${R}, ${B}/review${R}, ${B}/check${R} commands"
    echo ""

    if [ "$strict" = "true" ]; then
        echo -e "  ${Y}Strict mode active:${R} Quality rules added to CLAUDE.md"
        echo ""
    fi
}

# ─────────────────────────────────────────────
# Entrypoint
# ─────────────────────────────────────────────
case "${1:-}" in
    init) shift; do_init "$@" ;;
    *)    do_init "$@" ;;
esac
