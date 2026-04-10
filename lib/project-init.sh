#!/bin/bash
# ─────────────────────────────────────────────
# MangoLove — Project Initializer
# Generates CLAUDE.md, .claude/commands/, and hooks
# for optimal Claude Code experience
# ─────────────────────────────────────────────

set -o pipefail

MANGOLOVE_DIR="${MANGOLOVE_DIR:-$HOME/.mangolove}"

# shellcheck source=colors.sh
source "${MANGOLOVE_DIR}/lib/colors.sh"

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
    PROJ_DB=()
    PROJ_INFRA=()
    PROJ_VERSIONS=()

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
            : # framework: Spring Boot
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

        # Detect versions
        local java_ver=""
        java_ver=$(grep -h "sourceCompatibility\|JavaVersion\.\|jvmTarget" "$dir/build.gradle"* 2>/dev/null | grep -oE '[0-9]+' | head -1) || true
        [ -n "$java_ver" ] && PROJ_VERSIONS+=("Java ${java_ver}")

        local spring_ver=""
        spring_ver=$(grep -h "springBootVersion\|org.springframework.boot.*version" "$dir/build.gradle"* 2>/dev/null | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | head -1) || true
        [ -n "$spring_ver" ] && PROJ_VERSIONS+=("Spring Boot ${spring_ver}")

        # Multi-module
        if [ -f "$dir/settings.gradle" ] || [ -f "$dir/settings.gradle.kts" ]; then
            local settings_file="$dir/settings.gradle"
            [ -f "$dir/settings.gradle.kts" ] && settings_file="$dir/settings.gradle.kts"
            PROJ_MODULES=$(grep "include" "$settings_file" 2>/dev/null | sed "s/.*include//;s/[\"'()]//g;s/://g" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | grep -v '^$' | tr '\n' ', ' | sed 's/,$//')
        fi

    fi

    # --- Maven ---
    if [ -f "$dir/pom.xml" ]; then
        [[ ! " ${PROJ_TECH[*]} " =~ " Java " ]] && PROJ_TECH+=("Java")
        grep -q "spring-boot" "$dir/pom.xml" 2>/dev/null && { [[ ! " ${PROJ_TECH[*]} " =~ " Spring Boot " ]] && PROJ_TECH+=("Spring Boot"); }
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

        grep -q '"react"' "$dir/package.json" 2>/dev/null && { PROJ_TECH+=("React"); }
        grep -q '"next"' "$dir/package.json" 2>/dev/null && { PROJ_TECH+=("Next.js"); }
        grep -q '"vue"' "$dir/package.json" 2>/dev/null && { PROJ_TECH+=("Vue"); }
        grep -q '"express"' "$dir/package.json" 2>/dev/null && { PROJ_TECH+=("Express"); }
        grep -qE '"@nestjs"' "$dir/package.json" 2>/dev/null && { PROJ_TECH+=("NestJS"); }

        # Detect versions from package.json
        local react_ver="" next_ver="" ts_ver="" node_ver=""
        react_ver=$(grep '"react"' "$dir/package.json" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1) || true
        next_ver=$(grep '"next"' "$dir/package.json" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1) || true
        ts_ver=$(grep '"typescript"' "$dir/package.json" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1) || true
        [ -n "$react_ver" ] && PROJ_VERSIONS+=("React ${react_ver}")
        [ -n "$next_ver" ] && PROJ_VERSIONS+=("Next.js ${next_ver}")
        [ -n "$ts_ver" ] && PROJ_VERSIONS+=("TypeScript ${ts_ver}")
        if [ -f "$dir/.node-version" ]; then
            node_ver=$(cat "$dir/.node-version" 2>/dev/null | tr -d '[:space:]') || true
            [ -n "$node_ver" ] && PROJ_VERSIONS+=("Node.js ${node_ver}")
        elif [ -f "$dir/.nvmrc" ]; then
            node_ver=$(cat "$dir/.nvmrc" 2>/dev/null | tr -d '[:space:]') || true
            [ -n "$node_ver" ] && PROJ_VERSIONS+=("Node.js ${node_ver}")
        fi

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
        grep -rq "django" "$dir/requirements.txt" "$dir/pyproject.toml" 2>/dev/null && { PROJ_TECH+=("Django"); }
        grep -rq "fastapi" "$dir/requirements.txt" "$dir/pyproject.toml" 2>/dev/null && { PROJ_TECH+=("FastAPI"); }
        grep -rq "flask" "$dir/requirements.txt" "$dir/pyproject.toml" 2>/dev/null && { PROJ_TECH+=("Flask"); }
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

    local tech_str db_str infra_str ver_str
    tech_str=$(printf '%s, ' "${PROJ_TECH[@]}" | sed 's/, $//')
    db_str=$(printf '%s, ' "${PROJ_DB[@]}" | sed 's/, $//')
    infra_str=$(printf '%s, ' "${PROJ_INFRA[@]}" | sed 's/, $//')
    ver_str=$(printf '%s, ' "${PROJ_VERSIONS[@]}" | sed 's/, $//')

    local content="# ${PROJ_NAME}

<!-- mangolove:auto-start -->
## 기술 스택
- ${tech_str}
$([ ${#PROJ_DB[@]} -gt 0 ] && echo "- 데이터베이스: ${db_str}")
$([ ${#PROJ_INFRA[@]} -gt 0 ] && echo "- 인프라: ${infra_str}")
$([ -n "$ver_str" ] && echo "- 버전: ${ver_str}")

## 명령어
- 빌드: \`${PROJ_BUILD}\`
- 테스트: \`${PROJ_TEST}\`"

    [ -n "$PROJ_LINT" ] && content="${content}
- 린트: \`${PROJ_LINT}\`"

    [ -n "$PROJ_TYPECHECK" ] && content="${content}
- 타입 체크: \`${PROJ_TYPECHECK}\`"

    [ -n "$PROJ_MODULES" ] && content="${content}

## 모듈
$(echo "$PROJ_MODULES" | tr ',' '\n' | sed 's/^ */- /')"

    content="${content}
<!-- mangolove:auto-end -->

## 코드 컨벤션"

    # shellcheck disable=SC2076
    if [[ " ${PROJ_TECH[*]} " =~ " Java " ]] || [[ " ${PROJ_TECH[*]} " =~ " Kotlin " ]]; then
        content="${content}
- Google Java Style Guide 준수 (들여쓰기 4칸, 줄 길이 최대 100자)
- Conventional Commits 형식으로 커밋 메시지 작성
- 모든 public API에 Javadoc/KDoc 작성"
    fi

    # shellcheck disable=SC2076
    if [[ " ${PROJ_TECH[*]} " =~ " TypeScript " ]] || [[ " ${PROJ_TECH[*]} " =~ " Node.js " ]]; then
        local ts_style="들여쓰기 2칸"
        [ -n "${PROJ_INDENT:-}" ] && ts_style="들여쓰기 ${PROJ_INDENT}칸"
        [ -n "${PROJ_QUOTE_STYLE:-}" ] && ts_style="${ts_style}, ${PROJ_QUOTE_STYLE}"
        [ -n "${PROJ_SEMICOLONS:-}" ] && ts_style="${ts_style}, ${PROJ_SEMICOLONS}"
        content="${content}
- 코드 스타일: ${ts_style}
- Conventional Commits 형식으로 커밋 메시지 작성
- \`any\` 타입 사용 금지 — \`unknown\` 또는 구체적 타입 사용"
    fi

    # shellcheck disable=SC2076
    if [[ " ${PROJ_TECH[*]} " =~ " Python " ]]; then
        content="${content}
- PEP 8 스타일 가이드 준수
- 모든 함수에 타입 힌트 명시
- Conventional Commits 형식으로 커밋 메시지 작성"
    fi

    # shellcheck disable=SC2076
    if [[ " ${PROJ_TECH[*]} " =~ " Go " ]]; then
        content="${content}
- Effective Go 컨벤션 준수
- 커밋 전 \`gofmt\` 실행
- Conventional Commits 형식으로 커밋 메시지 작성"
    fi

    # shellcheck disable=SC2076
    if [[ " ${PROJ_TECH[*]} " =~ " Rust " ]]; then
        content="${content}
- Rust API 가이드라인 준수
- 커밋 전 \`cargo fmt\` 실행
- Conventional Commits 형식으로 커밋 메시지 작성"
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

    # Helper: only write if file doesn't exist (never overwrite user commands)
    _write_cmd() {
        local file="$1"
        if [ -f "$file" ]; then
            return 0
        fi
        cat > "$file"
    }

    # /test
    if [ -n "$PROJ_TEST" ]; then
        _write_cmd "$cmd_dir/test.md" << EOF
프로젝트 테스트를 실행하고 결과를 보고한다.

\`\`\`bash
${PROJ_TEST}
\`\`\`

테스트 실패 시 원인을 분석하고 수정을 제안한다.
EOF
    fi

    # /build
    if [ -n "$PROJ_BUILD" ]; then
        _write_cmd "$cmd_dir/build.md" << EOF
프로젝트를 빌드하고 에러가 있으면 보고한다.

\`\`\`bash
${PROJ_BUILD}
\`\`\`

빌드 실패 시 에러를 분석하고 수정한다.
EOF
    fi

    # /lint
    if [ -n "$PROJ_LINT" ]; then
        _write_cmd "$cmd_dir/lint.md" << EOF
린터를 실행하고 발견된 모든 문제를 수정한다.

\`\`\`bash
${PROJ_LINT}
\`\`\`

모든 경고와 에러를 수정한다. 정당한 사유 없이 경고를 무시하지 않는다.
EOF
    fi

    # /review
    _write_cmd "$cmd_dir/review.md" << EOF
스테이징된 변경 사항 (없으면 최근 커밋)을 다음 관점에서 리뷰한다:

1. 정확성 — 로직 에러, 엣지 케이스, null safety
2. 보안 — 인젝션, 인증 누락, 데이터 노출
3. 성능 — N+1 쿼리, 불필요한 메모리 할당
4. 스타일 — 네이밍, 가독성, 코드베이스와의 일관성

각 이슈를 파일 경로, 줄 번호, 심각도, 수정 제안과 함께 보고한다.
EOF

    # /check — 전체 검증 파이프라인
    local check_steps="echo '--- 빌드 ---' && ${PROJ_BUILD}"
    [ -n "$PROJ_LINT" ] && check_steps="${check_steps} && echo '--- 린트 ---' && ${PROJ_LINT}"
    [ -n "$PROJ_TYPECHECK" ] && check_steps="${check_steps} && echo '--- 타입 체크 ---' && ${PROJ_TYPECHECK}"
    check_steps="${check_steps} && echo '--- 테스트 ---' && ${PROJ_TEST}"

    _write_cmd "$cmd_dir/check.md" << EOF
전체 검증 파이프라인을 실행한다: 빌드, 린트, 타입 체크, 테스트.

\`\`\`bash
${check_steps}
\`\`\`

각 단계의 결과를 보고한다. 실패 시 다음 단계로 넘어가지 않고 문제를 수정한다.
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

    # Sync script path
    local mangolove_dir="${MANGOLOVE_DIR:-$HOME/.mangolove}"
    local sync_cmd="bash '${mangolove_dir}/lib/project-init.sh' sync --quiet 2>/dev/null; exit 0"

    if [ "$strict" = "true" ] && [ -n "$PROJ_LINT" ]; then
        local lint_cmd="${PROJ_LINT} 2>&1 | tail -30; exit 0"

        cat > "$settings_file" << SETTINGSEOF
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${sync_cmd}"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "${lint_cmd}"
          }
        ]
      }
    ]
  }
}
SETTINGSEOF
    else
        cat > "$settings_file" << SETTINGSEOF
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${sync_cmd}"
          }
        ]
      }
    ]
  }
}
SETTINGSEOF
    fi
}

# ─────────────────────────────────────────────
# Main: mangolove init
# ─────────────────────────────────────────────
# ─────────────────────────────────────────────
# Export: generate .mangolove.md for team sharing
# ─────────────────────────────────────────────
do_export() {
    local target_dir="$1"
    if ! target_dir=$(cd "$target_dir" 2>/dev/null && pwd); then
        echo -e "  ${RED}Directory not found${R}"
        return 1
    fi

    echo ""
    echo -e "${O}${B}MangoLove Export${R}"
    echo -e "${DIM}──────────────────────────────────────${R}"

    # Scan project
    scan_project "$target_dir"

    if [ ${#PROJ_TECH[@]} -eq 0 ]; then
        echo -e "  ${Y}No recognized project structure.${R}"
        return 1
    fi

    detect_conventions "$target_dir"

    # Generate .mangolove.md with full project context
    local export_file="$target_dir/.mangolove.md"
    local tech_str db_str infra_str
    tech_str=$(printf '%s, ' "${PROJ_TECH[@]}" | sed 's/, $//')
    db_str=$(printf '%s, ' "${PROJ_DB[@]}" | sed 's/, $//')
    infra_str=$(printf '%s, ' "${PROJ_INFRA[@]}" | sed 's/, $//')

    cat > "$export_file" << EXPORTEOF
---
name: ${PROJ_NAME}
tech_stack: [${tech_str}]
database: [${db_str}]
infrastructure: [${infra_str}]
build_cmd: ${PROJ_BUILD}
test_cmd: ${PROJ_TEST}
lint_cmd: ${PROJ_LINT}
typecheck_cmd: ${PROJ_TYPECHECK}
modules: ${PROJ_MODULES}
exported: $(date '+%Y-%m-%d')
---

# ${PROJ_NAME} — Team Configuration

This file is auto-generated by MangoLove for team sharing.
New team members can run \`mangolove init --from-team\` to set up their Claude Code environment.

## Tech Stack
- ${tech_str}
$([ ${#PROJ_DB[@]} -gt 0 ] && echo "- Database: ${db_str}")
$([ ${#PROJ_INFRA[@]} -gt 0 ] && echo "- Infrastructure: ${infra_str}")

## Commands
- Build: \`${PROJ_BUILD}\`
- Test: \`${PROJ_TEST}\`
$([ -n "$PROJ_LINT" ] && echo "- Lint: \`${PROJ_LINT}\`")
$([ -n "$PROJ_TYPECHECK" ] && echo "- Type Check: \`${PROJ_TYPECHECK}\`")
EXPORTEOF

    # Append conventions section for team to customize
    cat >> "$export_file" << 'CONVEOF'

## Team Conventions
<!-- Add your team's coding conventions here -->
<!-- These will be included in every team member's CLAUDE.md -->

## Onboarding Notes
<!-- Add notes for new team members here -->
CONVEOF

    echo -e "  ${G}Exported:${R} .mangolove.md"
    echo -e "  ${DIM}Commit this file to share with your team.${R}"
    echo -e "  ${DIM}Team members run: mangolove init --from-team${R}"
    echo ""
}

# ─────────────────────────────────────────────
# From-team: import .mangolove.md and generate config
# ─────────────────────────────────────────────
do_from_team() {
    local target_dir="$1"
    local strict="$2"

    if ! target_dir=$(cd "$target_dir" 2>/dev/null && pwd); then
        echo -e "  ${RED}Directory not found${R}"
        return 1
    fi

    # Look for .mangolove.md in project tree
    local team_file=""
    local check_dir="$target_dir"
    while [ "$check_dir" != "/" ]; do
        if [ -f "$check_dir/.mangolove.md" ]; then
            team_file="$check_dir/.mangolove.md"
            break
        fi
        check_dir=$(dirname "$check_dir")
    done

    if [ -z "$team_file" ]; then
        echo -e "  ${RED}No .mangolove.md found.${R}"
        echo -e "  ${DIM}Ask your team lead to run: mangolove init --export${R}"
        return 1
    fi

    echo ""
    echo -e "${O}${B}MangoLove — Team Setup${R}"
    echo -e "${DIM}──────────────────────────────────────${R}"
    echo -e "  Team config: ${B}${team_file}${R}"
    echo ""

    # Parse team file for commands
    local team_build team_test team_lint team_typecheck
    team_build=$(grep "^build_cmd:" "$team_file" 2>/dev/null | sed 's/^build_cmd: *//') || true
    team_test=$(grep "^test_cmd:" "$team_file" 2>/dev/null | sed 's/^test_cmd: *//') || true
    team_lint=$(grep "^lint_cmd:" "$team_file" 2>/dev/null | sed 's/^lint_cmd: *//') || true
    team_typecheck=$(grep "^typecheck_cmd:" "$team_file" 2>/dev/null | sed 's/^typecheck_cmd: *//') || true

    # Generate CLAUDE.md from team file + fresh scan
    scan_project "$target_dir"

    # Override with team values if present
    [ -n "$team_build" ] && PROJ_BUILD="$team_build"
    [ -n "$team_test" ] && PROJ_TEST="$team_test"
    [ -n "$team_lint" ] && PROJ_LINT="$team_lint"
    [ -n "$team_typecheck" ] && PROJ_TYPECHECK="$team_typecheck"

    detect_conventions "$target_dir"

    # Generate CLAUDE.md
    local claude_md
    claude_md=$(generate_claude_md "$target_dir")

    # Append team conventions from .mangolove.md
    local team_conventions
    team_conventions=$(awk '/^## Team Conventions/,/^## [^O]/' "$team_file" 2>/dev/null | head -n -1) || true
    local team_onboarding
    team_onboarding=$(awk '/^## Onboarding Notes/,0' "$team_file" 2>/dev/null) || true

    if [ -n "$team_conventions" ]; then
        claude_md="${claude_md}

${team_conventions}"
    fi

    if [ -n "$team_onboarding" ]; then
        claude_md="${claude_md}

${team_onboarding}"
    fi

    echo "$claude_md" > "$target_dir/CLAUDE.md"
    echo -e "  ${G}+${R} CLAUDE.md (from team config)"

    # Generate commands and settings
    generate_commands "$target_dir"
    local cmd_count
    cmd_count=$(find "$target_dir/.claude/commands" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
    echo -e "  ${G}+${R} .claude/commands/ (${cmd_count} commands)"

    generate_settings "$target_dir" "$strict"
    echo -e "  ${G}+${R} .claude/settings.json"

    update_gitignore "$target_dir"

    echo ""
    echo -e "${DIM}──────────────────────────────────────${R}"
    echo -e "  ${G}Done.${R} Team configuration applied."
    echo -e "  ${DIM}Run ${B}claude${R}${DIM} to start with full team context.${R}"
    echo ""
}

do_init() {
    local target_dir
    target_dir=$(pwd)
    local strict="false"
    local force="false"

    local export_mode="false"
    local from_team="false"

    # Parse flags
    while [ $# -gt 0 ]; do
        case "$1" in
            --strict)    strict="true"; shift ;;
            --force)     force="true"; shift ;;
            --export)    export_mode="true"; shift ;;
            --from-team) from_team="true"; shift ;;
            *)           target_dir="$1"; shift ;;
        esac
    done

    # Handle --export: generate .mangolove.md for team sharing
    if [ "$export_mode" = "true" ]; then
        do_export "$target_dir"
        return $?
    fi

    # Handle --from-team: import .mangolove.md and generate Claude Code config
    if [ "$from_team" = "true" ]; then
        do_from_team "$target_dir" "$strict"
        return $?
    fi

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
    [ ${#PROJ_VERSIONS[@]} -gt 0 ] && echo -e "    Versions   : ${DIM}$(printf '%s, ' "${PROJ_VERSIONS[@]}" | sed 's/, $//')${R}"
    echo ""

    # Generate files
    echo -e "  ${G}Generating:${R}"

    # 1. CLAUDE.md
    local claude_md
    claude_md=$(generate_claude_md "$target_dir")
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

    # 4. Create learnings file
    local learnings_file="$target_dir/.claude/learnings.md"
    if [ ! -f "$learnings_file" ]; then
        mkdir -p "$target_dir/.claude"
        cat > "$learnings_file" << 'LEARNINGS'
# 프로젝트 학습 기록

이 파일은 AI 에이전트가 작업 중 배운 교훈을 기록합니다.
세션 시작 시 자동으로 읽혀 같은 실수를 반복하지 않습니다.

---

LEARNINGS
        echo -e "    ${G}+${R} .claude/learnings.md"
    fi

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
# Main: mangolove sync
# Update CLAUDE.md with current project state
# without overwriting user-added content
# ─────────────────────────────────────────────
do_sync() {
    local target_dir
    target_dir=$(pwd)
    local quiet="false"

    # Parse flags
    [ "${1:-}" = "--quiet" ] && quiet="true"

    if ! target_dir=$(cd "$target_dir" 2>/dev/null && pwd); then
        [ "$quiet" = "false" ] && echo -e "  ${RED}Directory not found${R}"
        return 1
    fi

    if [ ! -f "$target_dir/CLAUDE.md" ]; then
        [ "$quiet" = "false" ] && echo -e "  ${Y}No CLAUDE.md found.${R} Run ${B}mangolove init${R} first."
        return 1
    fi

    if [ "$quiet" = "false" ]; then
        echo ""
        echo -e "${O}${B}MangoLove Sync${R}"
        echo -e "${DIM}──────────────────────────────────────${R}"
        echo -e "  Scanning: ${B}${target_dir}${R}"
        echo ""
    fi

    # Scan current project
    scan_project "$target_dir"

    if [ ${#PROJ_TECH[@]} -eq 0 ]; then
        [ "$quiet" = "false" ] && echo -e "  ${Y}No recognized project structure.${R}"
        return 1
    fi

    detect_conventions "$target_dir"

    # Update only the auto-generated sections of CLAUDE.md
    # Strategy: replace sections between markers, preserve everything else
    local claude_md="$target_dir/CLAUDE.md"
    local temp_file
    temp_file=$(mktemp)

    # Read existing CLAUDE.md and update specific sections

    # Generate fresh auto-content
    local ver_str
    ver_str=$(printf '%s, ' "${PROJ_VERSIONS[@]}" | sed 's/, $//')

    local auto_content=""
    auto_content="<!-- mangolove:auto-start -->
## 기술 스택
- $(printf '%s, ' "${PROJ_TECH[@]}" | sed 's/, $//')
$([ ${#PROJ_DB[@]} -gt 0 ] && echo "- 데이터베이스: $(printf '%s, ' "${PROJ_DB[@]}" | sed 's/, $//')")
$([ ${#PROJ_INFRA[@]} -gt 0 ] && echo "- 인프라: $(printf '%s, ' "${PROJ_INFRA[@]}" | sed 's/, $//')")
$([ -n "$ver_str" ] && echo "- 버전: ${ver_str}")

## 명령어
- 빌드: \`${PROJ_BUILD}\`
- 테스트: \`${PROJ_TEST}\`$([ -n "$PROJ_LINT" ] && echo "
- 린트: \`${PROJ_LINT}\`")$([ -n "$PROJ_TYPECHECK" ] && echo "
- 타입 체크: \`${PROJ_TYPECHECK}\`")$([ -n "$PROJ_MODULES" ] && echo "

## 모듈
$(echo "$PROJ_MODULES" | tr ',' '\n' | sed 's/^ */- /')")"

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

    # Report
    local cmd_count
    cmd_count=$(find "$target_dir/.claude/commands" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')

    if [ "$quiet" = "false" ]; then
        echo -e "  ${G}Synced:${R}"
        echo -e "    CLAUDE.md : updated"
        echo -e "    Commands  : ${cmd_count}"
        echo ""
        echo -e "${DIM}──────────────────────────────────────${R}"
        echo ""
    fi
}

# ─────────────────────────────────────────────
# Entrypoint
# ─────────────────────────────────────────────
case "${1:-}" in
    init) shift; do_init "$@" ;;
    sync) shift; do_sync "$@" ;;
    *)    do_init "$@" ;;
esac
