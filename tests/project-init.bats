#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove — Project Init Tests
# ─────────────────────────────────────────────

load test_helper

setup() {
    setup_test_env
    cp "$BATS_TEST_DIRNAME/../lib/project-init.sh" "$MANGOLOVE_DIR/lib/"
}

teardown() {
    teardown_test_env
}

# ─────────────────────────────────────────────
# Basic init
# ─────────────────────────────────────────────

@test "init: generates CLAUDE.md for Java/Gradle project" {
    local proj=$(create_fake_project "java-init")
    cat > "$proj/build.gradle" << 'EOF'
plugins { id 'org.springframework.boot' version '3.2.0' }
dependencies { implementation 'org.springframework.boot:spring-boot-starter-web' }
EOF
    mkdir -p "$proj/src/main/java/com/example"
    touch "$proj/src/main/java/com/example/App.java"
    touch "$proj/gradlew"

    cd "$proj"
    run bash "$MANGOLOVE_DIR/lib/project-init.sh" init
    [ "$status" -eq 0 ]
    [ -f "$proj/CLAUDE.md" ]
    grep -q "Java" "$proj/CLAUDE.md"
    grep -q "Spring Boot" "$proj/CLAUDE.md"
    grep -q "gradlew build" "$proj/CLAUDE.md"
}

@test "init: generates .claude/commands/" {
    local proj=$(create_fake_project "cmd-init")
    echo '{"name":"app","scripts":{"build":"next build","test":"jest"}}' > "$proj/package.json"

    cd "$proj"
    run bash "$MANGOLOVE_DIR/lib/project-init.sh" init
    [ "$status" -eq 0 ]
    [ -f "$proj/.claude/commands/test.md" ]
    [ -f "$proj/.claude/commands/build.md" ]
    [ -f "$proj/.claude/commands/review.md" ]
    [ -f "$proj/.claude/commands/check.md" ]
}

@test "init: generates .claude/settings.json" {
    local proj=$(create_fake_project "settings-init")
    echo '{"name":"app"}' > "$proj/package.json"

    cd "$proj"
    run bash "$MANGOLOVE_DIR/lib/project-init.sh" init
    [ "$status" -eq 0 ]
    [ -f "$proj/.claude/settings.json" ]
}

@test "init: refuses to overwrite existing CLAUDE.md" {
    local proj=$(create_fake_project "existing-init")
    echo '{"name":"app"}' > "$proj/package.json"
    echo "# Existing" > "$proj/CLAUDE.md"

    cd "$proj"
    run bash "$MANGOLOVE_DIR/lib/project-init.sh" init
    [ "$status" -eq 1 ]
    [[ "$output" == *"already exists"* ]]
    grep -q "Existing" "$proj/CLAUDE.md"
}

@test "init: --force overwrites existing CLAUDE.md" {
    local proj=$(create_fake_project "force-init")
    echo '{"name":"app","dependencies":{"react":"^18.0.0"}}' > "$proj/package.json"
    echo "# Old content" > "$proj/CLAUDE.md"

    cd "$proj"
    run bash "$MANGOLOVE_DIR/lib/project-init.sh" init --force
    [ "$status" -eq 0 ]
    grep -q "Node.js" "$proj/CLAUDE.md"
    ! grep -q "Old content" "$proj/CLAUDE.md"
}

@test "init: fails for unrecognized project" {
    local proj=$(create_fake_project "empty-init")
    echo "just a file" > "$proj/readme.txt"

    cd "$proj"
    run bash "$MANGOLOVE_DIR/lib/project-init.sh" init
    [ "$status" -eq 1 ]
    [[ "$output" == *"No recognized project"* ]]
}

# ─────────────────────────────────────────────
# Tech stack detection
# ─────────────────────────────────────────────

@test "init: detects Node.js + TypeScript + React" {
    local proj=$(create_fake_project "react-init")
    echo '{"name":"app","dependencies":{"react":"^18.0.0"}}' > "$proj/package.json"
    echo '{}' > "$proj/tsconfig.json"

    cd "$proj"
    bash "$MANGOLOVE_DIR/lib/project-init.sh" init
    grep -q "Node.js" "$proj/CLAUDE.md"
    grep -q "TypeScript" "$proj/CLAUDE.md"
    grep -q "React" "$proj/CLAUDE.md"
}

@test "init: detects Python + FastAPI" {
    local proj=$(create_fake_project "python-init")
    echo "fastapi==0.100.0" > "$proj/requirements.txt"

    cd "$proj"
    bash "$MANGOLOVE_DIR/lib/project-init.sh" init
    grep -q "Python" "$proj/CLAUDE.md"
    grep -q "FastAPI" "$proj/CLAUDE.md"
    grep -q "pytest" "$proj/CLAUDE.md"
}

@test "init: detects Go project" {
    local proj=$(create_fake_project "go-init")
    echo "module example.com/app" > "$proj/go.mod"

    cd "$proj"
    bash "$MANGOLOVE_DIR/lib/project-init.sh" init
    grep -q "Go" "$proj/CLAUDE.md"
    grep -q "go build" "$proj/CLAUDE.md"
}

@test "init: detects Docker and GitHub Actions" {
    local proj=$(create_fake_project "infra-init")
    echo "FROM node:18" > "$proj/Dockerfile"
    mkdir -p "$proj/.github/workflows"
    echo "name: CI" > "$proj/.github/workflows/ci.yml"
    echo '{"name":"app"}' > "$proj/package.json"

    cd "$proj"
    bash "$MANGOLOVE_DIR/lib/project-init.sh" init
    grep -q "Docker" "$proj/CLAUDE.md"
    grep -q "GitHub Actions" "$proj/CLAUDE.md"
}

@test "init: detects database dependencies" {
    local proj=$(create_fake_project "db-init")
    cat > "$proj/build.gradle" << 'EOF'
dependencies {
    runtimeOnly 'mysql:mysql-connector-java'
    implementation 'org.springframework.boot:spring-boot-starter-data-redis'
}
EOF
    mkdir -p "$proj/src/main/java"
    touch "$proj/src/main/java/App.java"

    cd "$proj"
    bash "$MANGOLOVE_DIR/lib/project-init.sh" init
    grep -q "MySQL" "$proj/CLAUDE.md"
    grep -q "Redis" "$proj/CLAUDE.md"
}

# ─────────────────────────────────────────────
# Strict mode
# ─────────────────────────────────────────────

@test "init: --strict adds quality rules to CLAUDE.md" {
    local proj=$(create_fake_project "strict-init")
    echo '{"name":"app","scripts":{"test":"jest"}}' > "$proj/package.json"

    cd "$proj"
    run bash "$MANGOLOVE_DIR/lib/project-init.sh" init --strict
    [ "$status" -eq 0 ]
    grep -q "Quality Rules" "$proj/CLAUDE.md"
    grep -q "EVERY code change" "$proj/CLAUDE.md"
}

# ─────────────────────────────────────────────
# Conventions based on stack
# ─────────────────────────────────────────────

@test "init: adds Java conventions for Java project" {
    local proj=$(create_fake_project "java-conv")
    echo 'apply plugin: "java"' > "$proj/build.gradle"
    mkdir -p "$proj/src/main/java"
    touch "$proj/src/main/java/App.java"

    cd "$proj"
    bash "$MANGOLOVE_DIR/lib/project-init.sh" init
    grep -q "Google Java Style Guide" "$proj/CLAUDE.md"
    grep -q "Conventional Commits" "$proj/CLAUDE.md"
}

@test "init: adds TypeScript conventions for TS project" {
    local proj=$(create_fake_project "ts-conv")
    echo '{"name":"app"}' > "$proj/package.json"
    echo '{}' > "$proj/tsconfig.json"

    cd "$proj"
    bash "$MANGOLOVE_DIR/lib/project-init.sh" init
    grep -q "Code style:" "$proj/CLAUDE.md"
    grep -q "any" "$proj/CLAUDE.md"
}

@test "init: generates framework-specific commands for Spring Boot" {
    local proj=$(create_fake_project "spring-cmd")
    cat > "$proj/build.gradle" << 'EOF'
plugins { id 'org.springframework.boot' version '3.2.0' }
EOF
    mkdir -p "$proj/src/main/java"
    touch "$proj/src/main/java/App.java"
    touch "$proj/gradlew"

    cd "$proj"
    bash "$MANGOLOVE_DIR/lib/project-init.sh" init
    [ -f "$proj/.claude/commands/entity.md" ]
    [ -f "$proj/.claude/commands/api.md" ]
    [ -f "$proj/.claude/commands/migration.md" ]
}

@test "init: updates .gitignore with .claude/" {
    local proj=$(create_fake_project "gitignore-test")
    echo '{"name":"app"}' > "$proj/package.json"
    echo "node_modules/" > "$proj/.gitignore"

    cd "$proj"
    bash "$MANGOLOVE_DIR/lib/project-init.sh" init
    grep -q ".claude/" "$proj/.gitignore"
}

@test "init: skips .gitignore if .claude/ already present" {
    local proj=$(create_fake_project "gitignore-skip")
    echo '{"name":"app"}' > "$proj/package.json"
    printf "node_modules/\n.claude/\n" > "$proj/.gitignore"

    cd "$proj"
    bash "$MANGOLOVE_DIR/lib/project-init.sh" init
    local count=$(grep -c ".claude/" "$proj/.gitignore")
    [ "$count" -eq 1 ]
}

@test "init: detects Spring Boot controllers and endpoints" {
    local proj=$(create_fake_project "spring-deep")
    cat > "$proj/build.gradle" << 'EOF'
plugins { id 'org.springframework.boot' version '3.2.0' }
EOF
    mkdir -p "$proj/src/main/java/com/example/controller"
    cat > "$proj/src/main/java/com/example/controller/UserController.java" << 'JAVA'
@RestController
@RequestMapping("/v1/users")
public class UserController {
    @GetMapping
    public List<User> list() {}
    @PostMapping
    public User create() {}
}
JAVA
    touch "$proj/gradlew"

    cd "$proj"
    bash "$MANGOLOVE_DIR/lib/project-init.sh" init
    grep -q "Controllers: 1" "$proj/CLAUDE.md"
    grep -q "/v1/users" "$proj/CLAUDE.md"
    grep -q "GET:1" "$proj/CLAUDE.md"
}

@test "init: detects eslint config" {
    local proj=$(create_fake_project "eslint-init")
    echo '{"name":"app","scripts":{"lint":"eslint ."}}' > "$proj/package.json"
    echo '{}' > "$proj/.eslintrc.json"

    cd "$proj"
    bash "$MANGOLOVE_DIR/lib/project-init.sh" init
    grep -q "Lint" "$proj/CLAUDE.md"
    [ -f "$proj/.claude/commands/lint.md" ]
}
