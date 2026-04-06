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
# Deep source code analysis
# ─────────────────────────────────────────────
analyze_spring_boot() {
    local dir="$1"

    PROJ_CONTROLLERS=0
    PROJ_SERVICES=0
    PROJ_REPOSITORIES=0
    PROJ_ENTITIES=0
    PROJ_ENDPOINTS=""
    PROJ_API_PATHS=""
    PROJ_BASE_PACKAGE=""

    # Find all Java/Kotlin source files (exclude build/generated)
    local src_files
    src_files=$(find "$dir" -path "*/src/main/*" \( -name "*.java" -o -name "*.kt" \) \
        -not -path "*/build/*" -not -path "*/target/*" 2>/dev/null)

    [ -z "$src_files" ] && return

    # Count components
    PROJ_CONTROLLERS=$(echo "$src_files" | xargs grep -l "@RestController\|@Controller" 2>/dev/null | wc -l | tr -d ' ')
    PROJ_SERVICES=$(echo "$src_files" | xargs grep -l "@Service" 2>/dev/null | wc -l | tr -d ' ')
    PROJ_REPOSITORIES=$(echo "$src_files" | xargs grep -l "@Repository\|extends.*Repository" 2>/dev/null | wc -l | tr -d ' ')
    PROJ_ENTITIES=$(echo "$src_files" | xargs grep -l "@Entity" 2>/dev/null | wc -l | tr -d ' ')

    # Extract API paths from @RequestMapping
    PROJ_API_PATHS=$(echo "$src_files" | xargs grep -h '@RequestMapping.*"' 2>/dev/null | \
        sed 's/.*"\(\/[^"]*\)".*/\1/' | sort -u | head -25)

    # Count endpoints by method
    local get_count post_count put_count delete_count
    get_count=$(echo "$src_files" | xargs grep -h "@GetMapping" 2>/dev/null | wc -l | tr -d ' ')
    post_count=$(echo "$src_files" | xargs grep -h "@PostMapping" 2>/dev/null | wc -l | tr -d ' ')
    put_count=$(echo "$src_files" | xargs grep -h "@PutMapping" 2>/dev/null | wc -l | tr -d ' ')
    delete_count=$(echo "$src_files" | xargs grep -h "@DeleteMapping" 2>/dev/null | wc -l | tr -d ' ')
    PROJ_ENDPOINTS="GET:${get_count} POST:${post_count} PUT:${put_count} DELETE:${delete_count}"

    # Detect base package
    PROJ_BASE_PACKAGE=$(echo "$src_files" | head -1 | sed 's|.*/src/main/[^/]*/||;s|/[^/]*$||;s|/|.|g' | \
        awk -F. '{print $1"."$2"."$3}')
}

analyze_node_project() {
    local dir="$1"

    PROJ_COMPONENTS=0
    PROJ_PAGES=0
    PROJ_API_ROUTES=0
    PROJ_HOOKS=0

    # React/Next.js components
    if [ -d "$dir/src/components" ] || [ -d "$dir/components" ]; then
        PROJ_COMPONENTS=$(find "$dir" -path "*/components/*" \( -name "*.tsx" -o -name "*.jsx" -o -name "*.vue" \) \
            -not -path "*/node_modules/*" 2>/dev/null | wc -l | tr -d ' ')
    fi

    # Next.js pages/app routes
    if [ -d "$dir/src/app" ] || [ -d "$dir/app" ]; then
        PROJ_PAGES=$(find "$dir" -path "*/app/*" -name "page.tsx" -o -name "page.jsx" \
            -not -path "*/node_modules/*" 2>/dev/null | wc -l | tr -d ' ')
    elif [ -d "$dir/src/pages" ] || [ -d "$dir/pages" ]; then
        PROJ_PAGES=$(find "$dir" -path "*/pages/*" \( -name "*.tsx" -o -name "*.jsx" \) \
            -not -path "*/node_modules/*" -not -name "_*" 2>/dev/null | wc -l | tr -d ' ')
    fi

    # API routes
    if [ -d "$dir/src/app/api" ] || [ -d "$dir/app/api" ] || [ -d "$dir/pages/api" ]; then
        PROJ_API_ROUTES=$(find "$dir" -path "*/api/*" -name "route.ts" -o -name "route.js" -o -name "*.ts" -path "*/pages/api/*" \
            -not -path "*/node_modules/*" 2>/dev/null | wc -l | tr -d ' ')
    fi

    # Custom hooks
    PROJ_HOOKS=$(find "$dir" -path "*/hooks/*" -o -name "use*.ts" -o -name "use*.tsx" \
        -not -path "*/node_modules/*" 2>/dev/null | wc -l | tr -d ' ')
}

analyze_python_project() {
    local dir="$1"

    PROJ_PY_MODELS=0
    PROJ_PY_VIEWS=0
    PROJ_PY_ROUTES=0

    # Django models
    PROJ_PY_MODELS=$(find "$dir" -name "models.py" -not -path "*/venv/*" -not -path "*/.venv/*" 2>/dev/null | \
        xargs grep -c "class.*Model" 2>/dev/null | awk -F: '{s+=$2}END{print s+0}')

    # Django views / FastAPI routes
    PROJ_PY_VIEWS=$(find "$dir" -name "views.py" -not -path "*/venv/*" 2>/dev/null | \
        xargs grep -c "def " 2>/dev/null | awk -F: '{s+=$2}END{print s+0}')

    # FastAPI/Flask routes
    PROJ_PY_ROUTES=$(find "$dir" \( -name "*.py" \) -not -path "*/venv/*" -not -path "*/.venv/*" 2>/dev/null | \
        xargs grep -c "@app\.\(get\|post\|put\|delete\)\|@router\.\(get\|post\|put\|delete\)" 2>/dev/null | \
        awk -F: '{s+=$2}END{print s+0}')
}

# ─────────────────────────────────────────────
# Detect naming conventions from existing code
# ─────────────────────────────────────────────
detect_conventions() {
    local dir="$1"

    PROJ_INDENT=""
    PROJ_QUOTE_STYLE=""
    PROJ_SEMICOLONS=""

    # For TypeScript/JavaScript
    if [ -f "$dir/package.json" ]; then
        # Check .editorconfig
        if [ -f "$dir/.editorconfig" ]; then
            local indent
            indent=$(grep "indent_size" "$dir/.editorconfig" 2>/dev/null | head -1 | sed 's/.*= *//') || true
            [ -n "$indent" ] && PROJ_INDENT="${indent}-space"
        fi

        # Check prettier config
        if [ -f "$dir/.prettierrc" ] || [ -f "$dir/.prettierrc.json" ]; then
            local prettier_file="$dir/.prettierrc"
            [ -f "$dir/.prettierrc.json" ] && prettier_file="$dir/.prettierrc.json"
            grep -q "singleQuote.*true" "$prettier_file" 2>/dev/null && PROJ_QUOTE_STYLE="single quotes"
            grep -q "singleQuote.*false" "$prettier_file" 2>/dev/null && PROJ_QUOTE_STYLE="double quotes"
            grep -q "semi.*false" "$prettier_file" 2>/dev/null && PROJ_SEMICOLONS="no semicolons"
            grep -q "semi.*true" "$prettier_file" 2>/dev/null && PROJ_SEMICOLONS="semicolons required"
        fi
    fi
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

<!-- mangolove:auto-start -->
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

    # Add deep analysis results for Spring Boot
    if [ "${PROJ_CONTROLLERS:-0}" -gt 0 ] 2>/dev/null; then
        content="${content}

## Architecture Overview
- Base package: \`${PROJ_BASE_PACKAGE}\`
- Controllers: ${PROJ_CONTROLLERS}
- Services: ${PROJ_SERVICES}
- Repositories: ${PROJ_REPOSITORIES}
- Entities: ${PROJ_ENTITIES}
- Endpoints: ${PROJ_ENDPOINTS}"

        if [ -n "$PROJ_API_PATHS" ]; then
            content="${content}

## API Endpoints
\`\`\`
$(echo "$PROJ_API_PATHS")
\`\`\`"
        fi
    fi

    # Add deep analysis results for Node.js
    if [ "${PROJ_COMPONENTS:-0}" -gt 0 ] || [ "${PROJ_PAGES:-0}" -gt 0 ] 2>/dev/null; then
        content="${content}

## Architecture Overview"
        [ "${PROJ_COMPONENTS:-0}" -gt 0 ] && content="${content}
- Components: ${PROJ_COMPONENTS}"
        [ "${PROJ_PAGES:-0}" -gt 0 ] && content="${content}
- Pages/Routes: ${PROJ_PAGES}"
        [ "${PROJ_API_ROUTES:-0}" -gt 0 ] && content="${content}
- API Routes: ${PROJ_API_ROUTES}"
        [ "${PROJ_HOOKS:-0}" -gt 0 ] && content="${content}
- Custom Hooks: ${PROJ_HOOKS}"
    fi

    # Add deep analysis results for Python
    if [ "${PROJ_PY_MODELS:-0}" -gt 0 ] || [ "${PROJ_PY_ROUTES:-0}" -gt 0 ] 2>/dev/null; then
        content="${content}

## Architecture Overview"
        [ "${PROJ_PY_MODELS:-0}" -gt 0 ] && content="${content}
- Models: ${PROJ_PY_MODELS}"
        [ "${PROJ_PY_VIEWS:-0}" -gt 0 ] && content="${content}
- Views: ${PROJ_PY_VIEWS}"
        [ "${PROJ_PY_ROUTES:-0}" -gt 0 ] && content="${content}
- API Routes: ${PROJ_PY_ROUTES}"
    fi

    content="${content}
<!-- mangolove:auto-end -->

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
        local ts_style="2-space indent"
        [ -n "${PROJ_INDENT:-}" ] && ts_style="${PROJ_INDENT} indent"
        [ -n "${PROJ_QUOTE_STYLE:-}" ] && ts_style="${ts_style}, ${PROJ_QUOTE_STYLE}"
        [ -n "${PROJ_SEMICOLONS:-}" ] && ts_style="${ts_style}, ${PROJ_SEMICOLONS}"
        content="${content}
- Code style: ${ts_style}
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

    if [ "$strict" = "true" ]; then
        content="${content}

## Quality Rules (Strict Mode)
- After EVERY code change, run: \`${PROJ_TEST}\`
- Before EVERY commit, run: \`${PROJ_LINT:-echo 'no linter configured'}\`$([ -n "$PROJ_TYPECHECK" ] && echo "
- Type check: \`${PROJ_TYPECHECK}\`")
- Write tests for all new functions and bug fixes.
- If tests fail, fix them before writing more code.
- Use \`/check\` to run the full validation pipeline.
- NEVER mark a task as done without all checks passing."
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
        # Build lint command for hook
        local lint_hook=""
        if [ -n "$PROJ_LINT" ]; then
            lint_hook=",
      {
        \"matcher\": \"Write|Edit\",
        \"hooks\": [
          {
            \"type\": \"command\",
            \"command\": \"${PROJ_LINT} 2>&1 | tail -20 || echo 'LINT FAILED: fix before continuing'\"
          }
        ]
      }"
        fi

        cat > "$settings_file" << SETTINGSEOF
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "echo ''"
          }
        ]
      }${lint_hook}
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "echo ''"
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

    # Deep analysis based on detected stack
    echo -e "  ${DIM}Analyzing source code...${R}"
    # shellcheck disable=SC2076
    if [[ " ${PROJ_TECH[*]} " =~ " Spring Boot " ]] || [[ " ${PROJ_TECH[*]} " =~ " Java " ]]; then
        analyze_spring_boot "$target_dir"
    fi
    # shellcheck disable=SC2076
    if [[ " ${PROJ_TECH[*]} " =~ " Node.js " ]]; then
        analyze_node_project "$target_dir"
    fi
    # shellcheck disable=SC2076
    if [[ " ${PROJ_TECH[*]} " =~ " Python " ]]; then
        analyze_python_project "$target_dir"
    fi
    detect_conventions "$target_dir"

    # Report detection
    local tech_display
    tech_display=$(printf '%s, ' "${PROJ_TECH[@]}" | sed 's/, $//')
    echo -e "  ${G}Detected:${R}"
    echo -e "    Tech Stack : ${C}${tech_display}${R}"
    [ ${#PROJ_DB[@]} -gt 0 ] && echo -e "    Database   : ${C}$(printf '%s, ' "${PROJ_DB[@]}" | sed 's/, $//')${R}"
    [ ${#PROJ_INFRA[@]} -gt 0 ] && echo -e "    Infra      : ${C}$(printf '%s, ' "${PROJ_INFRA[@]}" | sed 's/, $//')${R}"
    echo -e "    Build      : ${DIM}${PROJ_BUILD}${R}"
    echo -e "    Test       : ${DIM}${PROJ_TEST}${R}"
    [ -n "$PROJ_LINT" ] && echo -e "    Lint       : ${DIM}${PROJ_LINT}${R}"
    [ -n "$PROJ_MODULES" ] && echo -e "    Modules    : ${DIM}${PROJ_MODULES}${R}"

    # Show deep analysis results
    if [ "${PROJ_CONTROLLERS:-0}" -gt 0 ] 2>/dev/null; then
        echo -e "    Controllers: ${DIM}${PROJ_CONTROLLERS}${R}"
        echo -e "    Services   : ${DIM}${PROJ_SERVICES}${R}"
        echo -e "    Entities   : ${DIM}${PROJ_ENTITIES}${R}"
        echo -e "    Endpoints  : ${DIM}${PROJ_ENDPOINTS}${R}"
    fi
    if [ "${PROJ_COMPONENTS:-0}" -gt 0 ] 2>/dev/null; then
        echo -e "    Components : ${DIM}${PROJ_COMPONENTS}${R}"
        [ "${PROJ_PAGES:-0}" -gt 0 ] && echo -e "    Pages      : ${DIM}${PROJ_PAGES}${R}"
    fi
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
    generate_framework_commands "$target_dir"
    local cmd_count
    cmd_count=$(find "$target_dir/.claude/commands" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
    echo -e "    ${G}+${R} .claude/commands/ (${cmd_count} commands)"

    # 3. .claude/settings.json
    generate_settings "$target_dir" "$strict"
    echo -e "    ${G}+${R} .claude/settings.json"

    # 4. Save snapshot for future sync
    local snapshot_file="$target_dir/.claude/.mangolove_snapshot"
    mkdir -p "$target_dir/.claude"
    cat > "$snapshot_file" << SNAPSHOT
tech=$(printf '%s, ' "${PROJ_TECH[@]}" | sed 's/, $//')
db=$(printf '%s, ' "${PROJ_DB[@]}" | sed 's/, $//')
infra=$(printf '%s, ' "${PROJ_INFRA[@]}" | sed 's/, $//')
build=${PROJ_BUILD}
test=${PROJ_TEST}
lint=${PROJ_LINT}
modules=${PROJ_MODULES}
controllers=${PROJ_CONTROLLERS:-0}
services=${PROJ_SERVICES:-0}
repositories=${PROJ_REPOSITORIES:-0}
entities=${PROJ_ENTITIES:-0}
endpoints=${PROJ_ENDPOINTS:-}
components=${PROJ_COMPONENTS:-0}
pages=${PROJ_PAGES:-0}
api_routes=${PROJ_API_ROUTES:-0}
SNAPSHOT

    # 5. Update .gitignore
    update_gitignore "$target_dir"

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
# Update .gitignore to include .claude/
# ─────────────────────────────────────────────
update_gitignore() {
    local dir="$1"
    local gitignore="$dir/.gitignore"

    if [ ! -f "$gitignore" ]; then
        return 0
    fi

    # Check if .claude/ is already in .gitignore
    if grep -q "^\.claude/" "$gitignore" 2>/dev/null || grep -q "^\.claude$" "$gitignore" 2>/dev/null; then
        return 0
    fi

    # Append .claude/ to .gitignore
    echo "" >> "$gitignore"
    echo "# Claude Code local settings" >> "$gitignore"
    echo ".claude/" >> "$gitignore"
    echo -e "    ${G}+${R} .gitignore (added .claude/)"
}

# ─────────────────────────────────────────────
# Generate framework-specific commands
# ─────────────────────────────────────────────
generate_framework_commands() {
    local dir="$1"
    local cmd_dir="$dir/.claude/commands"

    # Spring Boot specific commands
    # shellcheck disable=SC2076
    if [[ " ${PROJ_TECH[*]} " =~ " Spring Boot " ]]; then
        cat > "$cmd_dir/entity.md" << 'EOF'
Create a new JPA entity class. Ask for:
1. Entity name
2. Table name
3. Fields (name, type, constraints)

Follow the project's existing entity patterns:
- Extend base entity class if one exists
- Add proper JPA annotations (@Entity, @Table, @Column)
- Add audit fields if the project uses auditing
- Create the corresponding Repository interface
- Place in the correct package following project structure
EOF

        cat > "$cmd_dir/api.md" << 'EOF'
Create a new REST API endpoint. Ask for:
1. Resource name
2. HTTP method and path
3. Request/response DTOs

Follow the project's existing patterns:
- Controller -> Service -> Repository layering
- Consistent naming: {Resource}Controller, {Resource}Service
- Use existing DTO conventions (RequestDto, ResponseDto)
- Add proper validation annotations
- Follow the project's API versioning pattern
EOF

        cat > "$cmd_dir/migration.md" << 'EOF'
Analyze the current JPA entities and generate a database migration.

1. Compare entity definitions with the current schema
2. Generate the appropriate migration script (SQL or Flyway/Liquibase)
3. Include both UP and DOWN migrations
4. Flag any destructive changes (column drops, type changes)
EOF
    fi

    # Next.js specific commands
    # shellcheck disable=SC2076
    if [[ " ${PROJ_TECH[*]} " =~ " Next.js " ]]; then
        cat > "$cmd_dir/page.md" << 'EOF'
Create a new Next.js page/route. Ask for:
1. Route path
2. Whether it needs server-side data fetching
3. Whether it needs client-side interactivity

Follow the project's existing patterns for:
- File-based routing structure (app/ or pages/)
- Layout usage
- Data fetching patterns (Server Components vs Client)
- Styling approach
EOF

        cat > "$cmd_dir/component.md" << 'EOF'
Create a new React component. Ask for:
1. Component name
2. Props interface
3. Whether it's a server or client component

Follow the project's existing patterns for:
- Component file structure
- Props typing
- Styling approach (CSS modules, Tailwind, styled-components)
- Test file co-location
EOF
    fi

    # Django specific commands
    # shellcheck disable=SC2076
    if [[ " ${PROJ_TECH[*]} " =~ " Django " ]]; then
        cat > "$cmd_dir/model.md" << 'EOF'
Create a new Django model. Ask for:
1. Model name
2. Fields (name, type, constraints)
3. Which app it belongs to

Follow the project's existing patterns:
- Model naming and field conventions
- Meta class configuration
- Generate and apply migration
- Register in admin if admin is used
EOF
    fi

    # FastAPI specific commands
    # shellcheck disable=SC2076
    if [[ " ${PROJ_TECH[*]} " =~ " FastAPI " ]]; then
        cat > "$cmd_dir/endpoint.md" << 'EOF'
Create a new FastAPI endpoint. Ask for:
1. Path and HTTP method
2. Request/response schemas (Pydantic models)
3. Dependencies

Follow the project's existing patterns:
- Router organization
- Pydantic model conventions
- Dependency injection patterns
- Error handling approach
EOF
    fi
}

# ─────────────────────────────────────────────
# Main: mangolove sync
# Update CLAUDE.md with current project state
# without overwriting user-added content
# ─────────────────────────────────────────────
do_sync() {
    local target_dir
    target_dir=$(pwd)

    if ! target_dir=$(cd "$target_dir" 2>/dev/null && pwd); then
        echo -e "  ${RED}Directory not found${R}"
        return 1
    fi

    if [ ! -f "$target_dir/CLAUDE.md" ]; then
        echo -e "  ${Y}No CLAUDE.md found.${R} Run ${B}mangolove init${R} first."
        return 1
    fi

    echo ""
    echo -e "${O}${B}MangoLove Sync${R}"
    echo -e "${DIM}──────────────────────────────────────${R}"
    echo -e "  Scanning: ${B}${target_dir}${R}"
    echo ""

    # Save snapshot of previous state for comparison
    local prev_file="$target_dir/.claude/.mangolove_snapshot"
    mkdir -p "$target_dir/.claude"

    # Scan current project
    scan_project "$target_dir"

    if [ ${#PROJ_TECH[@]} -eq 0 ]; then
        echo -e "  ${Y}No recognized project structure.${R}"
        return 1
    fi

    # Deep analysis
    # shellcheck disable=SC2076
    if [[ " ${PROJ_TECH[*]} " =~ " Spring Boot " ]] || [[ " ${PROJ_TECH[*]} " =~ " Java " ]]; then
        analyze_spring_boot "$target_dir"
    fi
    # shellcheck disable=SC2076
    if [[ " ${PROJ_TECH[*]} " =~ " Node.js " ]]; then
        analyze_node_project "$target_dir"
    fi
    # shellcheck disable=SC2076
    if [[ " ${PROJ_TECH[*]} " =~ " Python " ]]; then
        analyze_python_project "$target_dir"
    fi
    detect_conventions "$target_dir"

    # Build current snapshot for diff
    local current_snapshot=""
    current_snapshot="tech=$(printf '%s, ' "${PROJ_TECH[@]}" | sed 's/, $//')
db=$(printf '%s, ' "${PROJ_DB[@]}" | sed 's/, $//')
infra=$(printf '%s, ' "${PROJ_INFRA[@]}" | sed 's/, $//')
build=${PROJ_BUILD}
test=${PROJ_TEST}
lint=${PROJ_LINT}
modules=${PROJ_MODULES}
controllers=${PROJ_CONTROLLERS:-0}
services=${PROJ_SERVICES:-0}
repositories=${PROJ_REPOSITORIES:-0}
entities=${PROJ_ENTITIES:-0}
endpoints=${PROJ_ENDPOINTS:-}
components=${PROJ_COMPONENTS:-0}
pages=${PROJ_PAGES:-0}
api_routes=${PROJ_API_ROUTES:-0}"

    # Compare with previous snapshot
    local changes=()
    if [ -f "$prev_file" ]; then
        local prev_controllers prev_services prev_entities prev_endpoints prev_components prev_pages
        prev_controllers=$(grep "^controllers=" "$prev_file" 2>/dev/null | cut -d= -f2) || true
        prev_services=$(grep "^services=" "$prev_file" 2>/dev/null | cut -d= -f2) || true
        prev_entities=$(grep "^entities=" "$prev_file" 2>/dev/null | cut -d= -f2) || true
        prev_endpoints=$(grep "^endpoints=" "$prev_file" 2>/dev/null | cut -d= -f2) || true
        prev_components=$(grep "^components=" "$prev_file" 2>/dev/null | cut -d= -f2) || true
        prev_pages=$(grep "^pages=" "$prev_file" 2>/dev/null | cut -d= -f2) || true

        # Detect changes
        local curr_c="${PROJ_CONTROLLERS:-0}" curr_s="${PROJ_SERVICES:-0}" curr_e="${PROJ_ENTITIES:-0}"
        local curr_comp="${PROJ_COMPONENTS:-0}" curr_p="${PROJ_PAGES:-0}"

        [ "${prev_controllers:-0}" != "$curr_c" ] && changes+=("Controllers: ${prev_controllers:-0} -> ${curr_c}")
        [ "${prev_services:-0}" != "$curr_s" ] && changes+=("Services: ${prev_services:-0} -> ${curr_s}")
        [ "${prev_entities:-0}" != "$curr_e" ] && changes+=("Entities: ${prev_entities:-0} -> ${curr_e}")
        [ "${prev_endpoints:-}" != "${PROJ_ENDPOINTS:-}" ] && [ -n "${PROJ_ENDPOINTS:-}" ] && changes+=("Endpoints: ${prev_endpoints:-N/A} -> ${PROJ_ENDPOINTS}")
        [ "${prev_components:-0}" != "$curr_comp" ] && [ "$curr_comp" -gt 0 ] && changes+=("Components: ${prev_components:-0} -> ${curr_comp}")
        [ "${prev_pages:-0}" != "$curr_p" ] && [ "$curr_p" -gt 0 ] && changes+=("Pages: ${prev_pages:-0} -> ${curr_p}")
    else
        changes+=("First sync — full snapshot created")
    fi

    # Save new snapshot
    echo "$current_snapshot" > "$prev_file"

    # Update only the auto-generated sections of CLAUDE.md
    # Strategy: replace sections between markers, preserve everything else
    local claude_md="$target_dir/CLAUDE.md"
    local temp_file
    temp_file=$(mktemp)

    # Read existing CLAUDE.md and update specific sections

    # Generate fresh auto-content
    local auto_content=""
    auto_content="<!-- mangolove:auto-start -->
## Tech Stack
- $(printf '%s, ' "${PROJ_TECH[@]}" | sed 's/, $//')
$([ ${#PROJ_DB[@]} -gt 0 ] && echo "- Database: $(printf '%s, ' "${PROJ_DB[@]}" | sed 's/, $//')")
$([ ${#PROJ_INFRA[@]} -gt 0 ] && echo "- Infrastructure: $(printf '%s, ' "${PROJ_INFRA[@]}" | sed 's/, $//')")

## Commands
- Build: \`${PROJ_BUILD}\`
- Test: \`${PROJ_TEST}\`$([ -n "$PROJ_LINT" ] && echo "
- Lint: \`${PROJ_LINT}\`")$([ -n "$PROJ_TYPECHECK" ] && echo "
- Type Check: \`${PROJ_TYPECHECK}\`")$([ -n "$PROJ_MODULES" ] && echo "

## Modules
$(echo "$PROJ_MODULES" | tr ',' '\n' | sed 's/^ */- /')")"

    # Add architecture overview
    if [ "${PROJ_CONTROLLERS:-0}" -gt 0 ] 2>/dev/null; then
        auto_content="${auto_content}

## Architecture Overview
- Base package: \`${PROJ_BASE_PACKAGE}\`
- Controllers: ${PROJ_CONTROLLERS}
- Services: ${PROJ_SERVICES}
- Repositories: ${PROJ_REPOSITORIES}
- Entities: ${PROJ_ENTITIES}
- Endpoints: ${PROJ_ENDPOINTS}"

        if [ -n "$PROJ_API_PATHS" ]; then
            auto_content="${auto_content}

## API Endpoints
\`\`\`
$(echo "$PROJ_API_PATHS")
\`\`\`"
        fi
    fi

    if [ "${PROJ_COMPONENTS:-0}" -gt 0 ] || [ "${PROJ_PAGES:-0}" -gt 0 ] 2>/dev/null; then
        auto_content="${auto_content}

## Architecture Overview"
        [ "${PROJ_COMPONENTS:-0}" -gt 0 ] && auto_content="${auto_content}
- Components: ${PROJ_COMPONENTS}"
        [ "${PROJ_PAGES:-0}" -gt 0 ] && auto_content="${auto_content}
- Pages/Routes: ${PROJ_PAGES}"
        [ "${PROJ_API_ROUTES:-0}" -gt 0 ] && auto_content="${auto_content}
- API Routes: ${PROJ_API_ROUTES}"
    fi

    auto_content="${auto_content}
<!-- mangolove:auto-end -->"

    # Check if CLAUDE.md has markers
    if grep -q "mangolove:auto-start" "$claude_md" 2>/dev/null; then
        # Replace content between markers
        awk '
            /<!-- mangolove:auto-start -->/ { skip=1; next }
            /<!-- mangolove:auto-end -->/ { skip=0; next }
            !skip { print }
        ' "$claude_md" > "$temp_file"

        # Find where to insert (after title line)
        local title_line
        title_line=$(head -1 "$claude_md")

        {
            echo "$title_line"
            echo ""
            echo "$auto_content"
            tail -n +2 "$temp_file" | sed '/^$/{ N; /^\n$/d; }'
        } > "$claude_md"
        : # updated
    else
        # No markers — add them. Preserve title + any user content after conventions
        local title_line
        title_line=$(head -1 "$claude_md")

        # Extract user-added content (everything after ## Conventions section)
        local user_content=""
        user_content=$(awk '/^## Conventions/,0' "$claude_md") || true

        {
            echo "$title_line"
            echo ""
            echo "$auto_content"
            echo ""
            [ -n "$user_content" ] && echo "$user_content"
        } > "$claude_md"
        : # updated
    fi

    rm -f "$temp_file"

    # Also update commands if new frameworks detected
    generate_commands "$target_dir"
    generate_framework_commands "$target_dir"

    # Report
    local cmd_count
    cmd_count=$(find "$target_dir/.claude/commands" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')

    echo -e "  ${G}Synced:${R}"
    echo -e "    CLAUDE.md   : updated"
    echo -e "    Commands    : ${cmd_count}"

    if [ ${#changes[@]} -gt 0 ]; then
        echo ""
        echo -e "  ${C}Changes detected:${R}"
        for change in "${changes[@]}"; do
            echo -e "    - ${change}"
        done
    else
        echo ""
        echo -e "  ${DIM}No changes since last sync.${R}"
    fi

    echo ""
    echo -e "${DIM}──────────────────────────────────────${R}"
    echo ""
}

# ─────────────────────────────────────────────
# Entrypoint
# ─────────────────────────────────────────────
case "${1:-}" in
    init) shift; do_init "$@" ;;
    sync) shift; do_sync "$@" ;;
    *)    do_init "$@" ;;
esac
