#!/bin/bash
# ─────────────────────────────────────────────
# 🥭 MangoLove — Project Profile Manager
# ─────────────────────────────────────────────

MANGOLOVE_DIR="${MANGOLOVE_DIR:-$HOME/.mangolove}"
PROJECTS_DIR="$MANGOLOVE_DIR/projects"

# shellcheck source=colors.sh
source "${MANGOLOVE_DIR}/lib/colors.sh"

list_profiles() {
    echo ""
    echo -e "${O}${B}🥭 MangoLove — Project Profiles${R}"
    echo -e "${DIM}──────────────────────────────────────${R}"

    local count=0
    for profile in "$PROJECTS_DIR"/*.md; do
        [ "$(basename "$profile")" = "README.md" ] && continue
        [ ! -f "$profile" ] && continue

        local name=$(grep "^name:" "$profile" 2>/dev/null | sed 's/^name: *//')
        local path=$(grep "^path:" "$profile" 2>/dev/null | sed 's/^path: *//')
        local stack=$(grep "^tech_stack:" "$profile" 2>/dev/null | sed 's/^tech_stack: *//')

        # Check if path exists
        local status="${G}✓${R}"
        [ ! -d "$path" ] && status="${RED}✗ path not found${R}"

        echo -e "  ${G}▸${R} ${B}${name}${R} ${status}"
        echo -e "    ${DIM}Path :${R} ${path}"
        echo -e "    ${DIM}Stack:${R} ${stack}"
        echo ""
        count=$((count + 1))
    done

    if [ $count -eq 0 ]; then
        echo -e "  ${DIM}No profiles yet.${R}"
        echo -e "  ${DIM}Start mangolove in a project directory to auto-create one.${R}"
        echo ""
    fi

    echo -e "${DIM}──────────────────────────────────────${R}"
    echo -e "  ${DIM}Profiles directory: ${PROJECTS_DIR}/${R}"
    echo ""
}

add_profile() {
    echo ""
    echo -e "${O}${B}🥭 MangoLove — Add Project Profile${R}"
    echo -e "${DIM}──────────────────────────────────────${R}"
    echo ""

    read -rp "  Project name: " proj_name
    read -rp "  Project path [$(pwd)]: " proj_path
    proj_path="${proj_path:-$(pwd)}"
    read -rp "  Tech stack (comma-separated): " proj_stack
    read -rp "  Build command [./gradlew build]: " proj_build
    proj_build="${proj_build:-./gradlew build}"
    read -rp "  Test command [./gradlew test]: " proj_test
    proj_test="${proj_test:-./gradlew test}"

    local filename=$(echo "$proj_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9-]//g')

    mkdir -p "$PROJECTS_DIR"
    cat > "$PROJECTS_DIR/${filename}.md" << EOF
---
name: ${proj_name}
path: ${proj_path}
tech_stack: [${proj_stack}]
build_cmd: ${proj_build}
test_cmd: ${proj_test}
---

## Architecture
<!-- Describe the project architecture -->

## Conventions
<!-- Describe coding conventions -->

## Notes
<!-- Any important notes for the agent -->
EOF

    echo ""
    echo -e "  ${G}✅ Profile created:${R} ${PROJECTS_DIR}/${filename}.md"
    echo -e "  ${DIM}Edit the file to add architecture and convention details.${R}"
    echo ""
}

remove_profile() {
    local name="$1"
    if [ -z "$name" ]; then
        echo "Usage: mangolove profile remove <name>"
        return 1
    fi

    local file="$PROJECTS_DIR/${name}.md"
    if [ -f "$file" ]; then
        rm "$file"
        echo -e "  ${G}✅ Profile removed:${R} ${name}"
    else
        echo -e "  ${RED}✗ Profile not found:${R} ${name}"
    fi
}

# Auto-generate a project profile by scanning the directory
auto_generate_profile() {
    local target_dir="${1:-$(pwd)}"
    # Resolve absolute path safely
    if ! target_dir=$(cd "$target_dir" 2>/dev/null && pwd); then
        echo -e "  ${RED}✗ Directory not found:${R} ${1}"
        return 1
    fi

    echo ""
    echo -e "${O}${B}🥭 MangoLove — Auto-Generate Profile${R}"
    echo -e "${DIM}──────────────────────────────────────${R}"
    echo -e "  ${DIM}Scanning:${R} ${target_dir}"
    echo ""

    # Detect project name
    local proj_name=$(basename "$target_dir")

    # Detect tech stack and build tools
    local tech_stack=()
    local build_cmd=""
    local test_cmd=""
    local modules=""

    # --- Gradle (Java/Kotlin) ---
    if [ -f "$target_dir/build.gradle" ] || [ -f "$target_dir/build.gradle.kts" ]; then
        if [ -f "$target_dir/build.gradle.kts" ]; then
            tech_stack+=("Kotlin")
        fi

        # Check for Java/Kotlin source
        if [ -d "$target_dir/src/main/java" ] || find "$target_dir" -maxdepth 3 -name "*.java" -print -quit 2>/dev/null | grep -q .; then
            # Avoid duplicates
            [[ ! " ${tech_stack[*]} " =~ " Java " ]] && tech_stack+=("Java")
        fi
        if [ -d "$target_dir/src/main/kotlin" ] || find "$target_dir" -maxdepth 3 -name "*.kt" -print -quit 2>/dev/null | grep -q .; then
            [[ ! " ${tech_stack[*]} " =~ " Kotlin " ]] && tech_stack+=("Kotlin")
        fi

        # Detect Spring Boot
        if grep -rq "org.springframework.boot" "$target_dir/build.gradle"* 2>/dev/null; then
            tech_stack+=("Spring Boot")
        fi

        # Detect JPA
        if grep -rq "spring-boot-starter-data-jpa\|jakarta.persistence\|javax.persistence" "$target_dir/build.gradle"* 2>/dev/null; then
            tech_stack+=("JPA")
        fi

        # Detect QueryDSL
        if grep -rq "querydsl" "$target_dir/build.gradle"* 2>/dev/null; then
            tech_stack+=("QueryDSL")
        fi

        # Detect databases from dependencies
        if grep -rq "mysql" "$target_dir/build.gradle"* 2>/dev/null; then
            tech_stack+=("MySQL")
        fi
        if grep -rq "postgresql\|postgres" "$target_dir/build.gradle"* 2>/dev/null; then
            tech_stack+=("PostgreSQL")
        fi
        if grep -rq "mongodb\|mongo" "$target_dir/build.gradle"* 2>/dev/null; then
            tech_stack+=("MongoDB")
        fi
        if grep -rq "redis\|lettuce\|jedis" "$target_dir/build.gradle"* 2>/dev/null; then
            tech_stack+=("Redis")
        fi

        # Detect messaging
        if grep -rq "kafka" "$target_dir/build.gradle"* 2>/dev/null; then
            tech_stack+=("Kafka")
        fi
        if grep -rq "rabbitmq\|amqp" "$target_dir/build.gradle"* 2>/dev/null; then
            tech_stack+=("RabbitMQ")
        fi

        # Build/test commands
        if [ -f "$target_dir/gradlew" ]; then
            build_cmd="./gradlew build"
            test_cmd="./gradlew test"
        else
            build_cmd="gradle build"
            test_cmd="gradle test"
        fi

        # Detect multi-module
        if [ -f "$target_dir/settings.gradle" ] || [ -f "$target_dir/settings.gradle.kts" ]; then
            local settings_file="$target_dir/settings.gradle"
            [ -f "$target_dir/settings.gradle.kts" ] && settings_file="$target_dir/settings.gradle.kts"
            modules=$(grep "include" "$settings_file" 2>/dev/null | sed "s/.*include//;s/[\"'()]//g;s/://g" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | grep -v '^$' | tr '\n' ', ' | sed 's/,$//')
        fi
    fi

    # --- Maven (Java) ---
    if [ -f "$target_dir/pom.xml" ]; then
        [[ ! " ${tech_stack[*]} " =~ " Java " ]] && tech_stack+=("Java")

        if grep -q "spring-boot" "$target_dir/pom.xml" 2>/dev/null; then
            [[ ! " ${tech_stack[*]} " =~ " Spring Boot " ]] && tech_stack+=("Spring Boot")
        fi
        if grep -q "spring-boot-starter-data-jpa\|jakarta.persistence" "$target_dir/pom.xml" 2>/dev/null; then
            [[ ! " ${tech_stack[*]} " =~ " JPA " ]] && tech_stack+=("JPA")
        fi

        if [ -f "$target_dir/mvnw" ]; then
            build_cmd="./mvnw package"
            test_cmd="./mvnw test"
        else
            build_cmd="mvn package"
            test_cmd="mvn test"
        fi
    fi

    # --- Node.js (package.json) ---
    if [ -f "$target_dir/package.json" ]; then
        tech_stack+=("Node.js")

        # Detect TypeScript
        if [ -f "$target_dir/tsconfig.json" ]; then
            tech_stack+=("TypeScript")
        fi

        # Detect frameworks from package.json
        if grep -q '"react"' "$target_dir/package.json" 2>/dev/null; then
            tech_stack+=("React")
        fi
        if grep -q '"next"' "$target_dir/package.json" 2>/dev/null; then
            tech_stack+=("Next.js")
        fi
        if grep -q '"vue"' "$target_dir/package.json" 2>/dev/null; then
            tech_stack+=("Vue")
        fi
        if grep -q '"express"' "$target_dir/package.json" 2>/dev/null; then
            tech_stack+=("Express")
        fi
        if grep -qE '"nestjs"|"@nestjs"' "$target_dir/package.json" 2>/dev/null; then
            tech_stack+=("NestJS")
        fi

        # Build/test commands from scripts
        local pkg_build=$(grep '"build"' "$target_dir/package.json" 2>/dev/null | sed 's/.*"build"[[:space:]]*:[[:space:]]*"//;s/".*//')
        local pkg_test=$(grep '"test"' "$target_dir/package.json" 2>/dev/null | sed 's/.*"test"[[:space:]]*:[[:space:]]*"//;s/".*//')

        # Detect package manager
        local pkg_mgr="npm"
        [ -f "$target_dir/yarn.lock" ] && pkg_mgr="yarn"
        [ -f "$target_dir/pnpm-lock.yaml" ] && pkg_mgr="pnpm"
        [ -f "$target_dir/bun.lockb" ] && pkg_mgr="bun"

        [ -n "$pkg_build" ] && build_cmd="${pkg_mgr} run build"
        [ -n "$pkg_test" ] && test_cmd="${pkg_mgr} run test"
        [ -z "$build_cmd" ] && build_cmd="${pkg_mgr} run build"
        [ -z "$test_cmd" ] && test_cmd="${pkg_mgr} test"
    fi

    # --- Python ---
    if [ -f "$target_dir/pyproject.toml" ] || [ -f "$target_dir/setup.py" ] || [ -f "$target_dir/requirements.txt" ]; then
        tech_stack+=("Python")

        if grep -rq "django" "$target_dir/requirements.txt" "$target_dir/pyproject.toml" 2>/dev/null; then
            tech_stack+=("Django")
        fi
        if grep -rq "fastapi" "$target_dir/requirements.txt" "$target_dir/pyproject.toml" 2>/dev/null; then
            tech_stack+=("FastAPI")
        fi
        if grep -rq "flask" "$target_dir/requirements.txt" "$target_dir/pyproject.toml" 2>/dev/null; then
            tech_stack+=("Flask")
        fi

        [ -z "$test_cmd" ] && test_cmd="pytest"
    fi

    # --- Go ---
    if [ -f "$target_dir/go.mod" ]; then
        tech_stack+=("Go")
        [ -z "$build_cmd" ] && build_cmd="go build ./..."
        [ -z "$test_cmd" ] && test_cmd="go test ./..."
    fi

    # --- Rust ---
    if [ -f "$target_dir/Cargo.toml" ]; then
        tech_stack+=("Rust")
        [ -z "$build_cmd" ] && build_cmd="cargo build"
        [ -z "$test_cmd" ] && test_cmd="cargo test"
    fi

    # --- Docker ---
    if [ -f "$target_dir/Dockerfile" ] || [ -f "$target_dir/docker-compose.yml" ] || [ -f "$target_dir/docker-compose.yaml" ]; then
        tech_stack+=("Docker")
    fi

    # --- Kubernetes ---
    if [ -d "$target_dir/k8s" ] || [ -d "$target_dir/kubernetes" ] || find "$target_dir" -maxdepth 2 -name "*.yaml" -exec grep -l "kind: Deployment\|kind: Service" {} + 2>/dev/null | grep -q .; then
        tech_stack+=("Kubernetes")
    fi

    # --- CI/CD ---
    if [ -d "$target_dir/.github/workflows" ]; then
        tech_stack+=("GitHub Actions")
    fi

    # Fallback defaults
    [ -z "$build_cmd" ] && build_cmd="echo 'No build command detected'"
    [ -z "$test_cmd" ] && test_cmd="echo 'No test command detected'"

    # Build tech stack string
    local stack_str=""
    if [ ${#tech_stack[@]} -gt 0 ]; then
        stack_str=$(IFS=', '; echo "${tech_stack[*]}")
    else
        stack_str="Unknown"
    fi

    # Generate filename
    local filename=$(echo "$proj_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9-]//g')

    # Check if profile already exists
    if [ -f "$PROJECTS_DIR/${filename}.md" ]; then
        echo -e "  ${Y}⚠️  Profile already exists:${R} ${PROJECTS_DIR}/${filename}.md"
        echo -e "  ${DIM}Use 'mangolove profile remove ${filename}' to recreate.${R}"
        echo ""
        return 1
    fi

    # Generate profile
    mkdir -p "$PROJECTS_DIR"
    local profile_content="---
name: ${proj_name}
path: ${target_dir}
tech_stack: [${stack_str}]
build_cmd: ${build_cmd}
test_cmd: ${test_cmd}
---"

    # Add modules if detected
    if [ -n "$modules" ]; then
        profile_content="${profile_content}

## Modules
$(echo "$modules" | tr ',' '\n' | sed 's/^ *//' | sed 's/^/- /')"
    fi

    profile_content="${profile_content}

## Architecture
<!-- Describe the project architecture -->

## Conventions
<!-- Describe coding conventions -->

## Notes
<!-- Any important notes for the agent -->"

    echo "$profile_content" > "$PROJECTS_DIR/${filename}.md"

    echo -e "  ${G}✅ Profile auto-generated:${R} ${PROJECTS_DIR}/${filename}.md"
    echo ""
    echo -e "  ${DIM}Detected:${R}"
    echo -e "    ${C}Tech Stack${R} : ${stack_str}"
    echo -e "    ${C}Build${R}      : ${build_cmd}"
    echo -e "    ${C}Test${R}       : ${test_cmd}"
    [ -n "$modules" ] && echo -e "    ${C}Modules${R}    : ${modules}"
    echo ""
    echo -e "  ${DIM}Edit the profile to add architecture and convention details.${R}"
    echo ""
}

# Load project context for current directory
load_project_context() {
    local current_dir=$(pwd)
    local context=""

    # First: check for .mangolove.md in current or parent directories (team shared config)
    local check_dir="$current_dir"
    while [ "$check_dir" != "/" ]; do
        if [ -f "$check_dir/.mangolove.md" ]; then
            context=$(cat "$check_dir/.mangolove.md")
            echo "$context"

            # Also append personal profile if exists
            for profile in "$PROJECTS_DIR"/*.md; do
                [ "$(basename "$profile")" = "README.md" ] && continue
                [ ! -f "$profile" ] && continue
                local profile_path=$(grep "^path:" "$profile" 2>/dev/null | sed 's/^path: *//')
                if [ -n "$profile_path" ] && [[ "$current_dir" == "$profile_path" || "$current_dir" == "$profile_path"/* ]]; then
                    echo ""
                    echo "---"
                    echo "## Personal Profile Additions"
                    cat "$profile"
                    break
                fi
            done
            return 0
        fi
        check_dir=$(dirname "$check_dir")
    done

    # Fallback: check personal profiles
    for profile in "$PROJECTS_DIR"/*.md; do
        [ "$(basename "$profile")" = "README.md" ] && continue
        [ ! -f "$profile" ] && continue

        local profile_path=$(grep "^path:" "$profile" 2>/dev/null | sed 's/^path: *//')
        if [ -n "$profile_path" ] && [[ "$current_dir" == "$profile_path" || "$current_dir" == "$profile_path"/* ]]; then
            cat "$profile"
            return 0
        fi
    done

    return 1
}

# Export a profile as a .mangolove.md for team sharing
export_profile() {
    local profile_name="$1"
    local output_dir="${2:-$(pwd)}"

    if [ -z "$profile_name" ]; then
        echo "Usage: mangolove profile export <name> [output-dir]"
        return 1
    fi

    local profile_file="$PROJECTS_DIR/${profile_name}.md"
    if [ ! -f "$profile_file" ]; then
        echo -e "  ${RED}✗ Profile not found:${R} ${profile_name}"
        return 1
    fi

    cp "$profile_file" "$output_dir/.mangolove.md"
    echo -e "  ${G}✅ Exported:${R} ${output_dir}/.mangolove.md"
    echo -e "  ${DIM}Commit this file to share with your team.${R}"
}

# Import a .mangolove.md from a project directory
import_profile() {
    local source_file="${1:-.mangolove.md}"

    if [ ! -f "$source_file" ]; then
        echo -e "  ${RED}✗ File not found:${R} ${source_file}"
        return 1
    fi

    local proj_name=$(grep "^name:" "$source_file" 2>/dev/null | sed 's/^name: *//')
    [ -z "$proj_name" ] && proj_name=$(basename "$(pwd)")

    local filename=$(echo "$proj_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9-]//g')

    mkdir -p "$PROJECTS_DIR"
    cp "$source_file" "$PROJECTS_DIR/${filename}.md"
    echo -e "  ${G}✅ Imported:${R} ${PROJECTS_DIR}/${filename}.md"
}

# Entrypoint
case "${1:-}" in
    list)    list_profiles ;;
    add)     add_profile ;;
    remove)  remove_profile "$2" ;;
    load)    load_project_context ;;
    auto)    auto_generate_profile "${2:-}" ;;
    export)  export_profile "$2" "${3:-}" ;;
    import)  import_profile "${2:-}" ;;
    *)       list_profiles ;;
esac
