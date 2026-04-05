#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove — Profile Manager Tests
# ─────────────────────────────────────────────

load test_helper

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

# ──────────────────────��──────────────────────
# list command
# ─────────────────────────────────────────────

@test "list: shows empty state when no profiles exist" {
    run bash "$MANGOLOVE_DIR/lib/profile-manager.sh" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"No profiles yet"* ]]
}

@test "list: shows profiles when they exist" {
    cat > "$MANGOLOVE_DIR/projects/test-project.md" << EOF
---
name: Test Project
path: /tmp/test
tech_stack: [Java, Spring Boot]
build_cmd: ./gradlew build
test_cmd: ./gradlew test
---
EOF
    run bash "$MANGOLOVE_DIR/lib/profile-manager.sh" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"Test Project"* ]]
}

@test "list: skips README.md in projects directory" {
    echo "# README" > "$MANGOLOVE_DIR/projects/README.md"
    run bash "$MANGOLOVE_DIR/lib/profile-manager.sh" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"No profiles yet"* ]]
}

# ─────────────────────────────────────────────
# remove command
# ─────────────────────────────────────────────

@test "remove: deletes existing profile" {
    echo "test" > "$MANGOLOVE_DIR/projects/my-app.md"
    run bash "$MANGOLOVE_DIR/lib/profile-manager.sh" remove "my-app"
    [ "$status" -eq 0 ]
    [ ! -f "$MANGOLOVE_DIR/projects/my-app.md" ]
}

@test "remove: fails for non-existent profile" {
    run bash "$MANGOLOVE_DIR/lib/profile-manager.sh" remove "nonexistent"
    [ "$status" -eq 0 ]
    [[ "$output" == *"not found"* ]]
}

@test "remove: shows usage when no name given" {
    run bash "$MANGOLOVE_DIR/lib/profile-manager.sh" remove
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

# ─────────────────────────────────────────────
# auto command — tech stack detection
# ─────────────────────────────────────────────

@test "auto: detects Gradle + Java project" {
    local proj=$(create_fake_project "java-app")
    echo 'apply plugin: "java"' > "$proj/build.gradle"
    mkdir -p "$proj/src/main/java"

    run bash "$MANGOLOVE_DIR/lib/profile-manager.sh" auto "$proj"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Java"* ]]
    [[ "$output" == *"gradlew build"* ]] || [[ "$output" == *"gradle build"* ]]
}

@test "auto: detects Gradle + Spring Boot project" {
    local proj=$(create_fake_project "spring-app")
    cat > "$proj/build.gradle" << 'EOF'
plugins {
    id 'org.springframework.boot' version '3.2.0'
}
dependencies {
    implementation 'org.springframework.boot:spring-boot-starter-web'
}
EOF
    mkdir -p "$proj/src/main/java"

    run bash "$MANGOLOVE_DIR/lib/profile-manager.sh" auto "$proj"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Spring Boot"* ]]
}

@test "auto: detects Kotlin + Gradle project" {
    local proj=$(create_fake_project "kotlin-app")
    echo 'kotlin("jvm")' > "$proj/build.gradle.kts"
    mkdir -p "$proj/src/main/kotlin"

    run bash "$MANGOLOVE_DIR/lib/profile-manager.sh" auto "$proj"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Kotlin"* ]]
}

@test "auto: detects Maven + Java project" {
    local proj=$(create_fake_project "maven-app")
    cat > "$proj/pom.xml" << 'EOF'
<project>
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.example</groupId>
    <artifactId>demo</artifactId>
</project>
EOF

    run bash "$MANGOLOVE_DIR/lib/profile-manager.sh" auto "$proj"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Java"* ]]
    [[ "$output" == *"mvn"* ]]
}

@test "auto: detects Node.js + React + TypeScript project" {
    local proj=$(create_fake_project "react-app")
    cat > "$proj/package.json" << 'EOF'
{
    "name": "react-app",
    "dependencies": { "react": "^18.0.0" },
    "scripts": { "build": "react-scripts build", "test": "jest" }
}
EOF
    echo '{}' > "$proj/tsconfig.json"

    run bash "$MANGOLOVE_DIR/lib/profile-manager.sh" auto "$proj"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Node.js"* ]]
    [[ "$output" == *"React"* ]]
    [[ "$output" == *"TypeScript"* ]]
}

@test "auto: detects Next.js project" {
    local proj=$(create_fake_project "next-app")
    cat > "$proj/package.json" << 'EOF'
{
    "name": "next-app",
    "dependencies": { "next": "^14.0.0", "react": "^18.0.0" }
}
EOF

    run bash "$MANGOLOVE_DIR/lib/profile-manager.sh" auto "$proj"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Next.js"* ]]
}

@test "auto: detects Python + FastAPI project" {
    local proj=$(create_fake_project "python-app")
    echo "fastapi==0.100.0" > "$proj/requirements.txt"

    run bash "$MANGOLOVE_DIR/lib/profile-manager.sh" auto "$proj"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Python"* ]]
    [[ "$output" == *"FastAPI"* ]]
    [[ "$output" == *"pytest"* ]]
}

@test "auto: detects Go project" {
    local proj=$(create_fake_project "go-app")
    echo "module github.com/example/go-app" > "$proj/go.mod"

    run bash "$MANGOLOVE_DIR/lib/profile-manager.sh" auto "$proj"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Go"* ]]
    [[ "$output" == *"go build"* ]]
}

@test "auto: detects Rust project" {
    local proj=$(create_fake_project "rust-app")
    cat > "$proj/Cargo.toml" << 'EOF'
[package]
name = "rust-app"
version = "0.1.0"
EOF

    run bash "$MANGOLOVE_DIR/lib/profile-manager.sh" auto "$proj"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Rust"* ]]
    [[ "$output" == *"cargo build"* ]]
}

@test "auto: detects Docker" {
    local proj=$(create_fake_project "docker-app")
    echo "FROM node:18" > "$proj/Dockerfile"
    echo '{"name":"app"}' > "$proj/package.json"

    run bash "$MANGOLOVE_DIR/lib/profile-manager.sh" auto "$proj"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Docker"* ]]
}

@test "auto: detects GitHub Actions" {
    local proj=$(create_fake_project "ci-app")
    mkdir -p "$proj/.github/workflows"
    echo "name: CI" > "$proj/.github/workflows/ci.yml"
    echo '{"name":"app"}' > "$proj/package.json"

    run bash "$MANGOLOVE_DIR/lib/profile-manager.sh" auto "$proj"
    [ "$status" -eq 0 ]
    [[ "$output" == *"GitHub Actions"* ]]
}

@test "auto: detects package manager — yarn" {
    local proj=$(create_fake_project "yarn-app")
    cat > "$proj/package.json" << 'EOF'
{"name":"app","scripts":{"build":"next build","test":"jest"}}
EOF
    touch "$proj/yarn.lock"

    run bash "$MANGOLOVE_DIR/lib/profile-manager.sh" auto "$proj"
    [ "$status" -eq 0 ]
    [[ "$output" == *"yarn"* ]]
}

@test "auto: detects package manager — pnpm" {
    local proj=$(create_fake_project "pnpm-app")
    cat > "$proj/package.json" << 'EOF'
{"name":"app","scripts":{"build":"next build","test":"jest"}}
EOF
    touch "$proj/pnpm-lock.yaml"

    run bash "$MANGOLOVE_DIR/lib/profile-manager.sh" auto "$proj"
    [ "$status" -eq 0 ]
    [[ "$output" == *"pnpm"* ]]
}

@test "auto: refuses duplicate profile" {
    local proj=$(create_fake_project "dup-app")
    echo '{"name":"app"}' > "$proj/package.json"

    # First run creates
    bash "$MANGOLOVE_DIR/lib/profile-manager.sh" auto "$proj"
    # Second run should fail
    run bash "$MANGOLOVE_DIR/lib/profile-manager.sh" auto "$proj"
    [ "$status" -eq 1 ]
    [[ "$output" == *"already exists"* ]]
}

@test "auto: fails for non-existent directory" {
    run bash "$MANGOLOVE_DIR/lib/profile-manager.sh" auto "/nonexistent/dir"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

@test "auto: creates valid profile file with YAML frontmatter" {
    local proj=$(create_fake_project "valid-app")
    echo '{"name":"app","dependencies":{"react":"^18.0.0"}}' > "$proj/package.json"

    bash "$MANGOLOVE_DIR/lib/profile-manager.sh" auto "$proj"

    local profile="$MANGOLOVE_DIR/projects/valid-app.md"
    [ -f "$profile" ]

    # Check YAML frontmatter structure
    head -1 "$profile" | grep -q "^---"
    grep -q "^name:" "$profile"
    grep -q "^path:" "$profile"
    grep -q "^tech_stack:" "$profile"
    grep -q "^build_cmd:" "$profile"
    grep -q "^test_cmd:" "$profile"
}

# ─────────────────────────────────────────────
# load command
# ─────────────────────────────────────────────

@test "load: returns profile for matching directory" {
    local proj=$(create_fake_project "load-test")
    cat > "$MANGOLOVE_DIR/projects/load-test.md" << EOF
---
name: Load Test
path: ${proj}
tech_stack: [Go]
build_cmd: go build
test_cmd: go test
---

## Notes
Test profile
EOF

    cd "$proj"
    run bash "$MANGOLOVE_DIR/lib/profile-manager.sh" load
    [ "$status" -eq 0 ]
    [[ "$output" == *"Load Test"* ]]
}

@test "load: returns profile for subdirectory" {
    local proj=$(create_fake_project "parent-proj")
    mkdir -p "$proj/sub/deep"
    cat > "$MANGOLOVE_DIR/projects/parent-proj.md" << EOF
---
name: Parent Project
path: ${proj}
tech_stack: [Java]
build_cmd: ./gradlew build
test_cmd: ./gradlew test
---
EOF

    cd "$proj/sub/deep"
    run bash "$MANGOLOVE_DIR/lib/profile-manager.sh" load
    [ "$status" -eq 0 ]
    [[ "$output" == *"Parent Project"* ]]
}

@test "load: fails when no profile matches" {
    cd /tmp
    run bash "$MANGOLOVE_DIR/lib/profile-manager.sh" load
    [ "$status" -eq 1 ]
}

@test "load: prefers .mangolove.md in project directory" {
    local proj=$(create_fake_project "team-proj")
    cat > "$proj/.mangolove.md" << EOF
---
name: Team Project
path: ${proj}
tech_stack: [Python]
---

## Team conventions
Use black for formatting
EOF

    cd "$proj"
    run bash "$MANGOLOVE_DIR/lib/profile-manager.sh" load
    [ "$status" -eq 0 ]
    [[ "$output" == *"Team Project"* ]]
    [[ "$output" == *"Team conventions"* ]]
}

# ─────────────────────────────────────────────
# export / import commands
# ─────────────────────────────────────────────

@test "export: creates .mangolove.md in target directory" {
    cat > "$MANGOLOVE_DIR/projects/exp-test.md" << 'EOF'
---
name: Export Test
path: /tmp
tech_stack: [Java]
---
EOF
    local out_dir=$(mktemp -d)

    run bash "$MANGOLOVE_DIR/lib/profile-manager.sh" export "exp-test" "$out_dir"
    [ "$status" -eq 0 ]
    [ -f "$out_dir/.mangolove.md" ]
    rm -rf "$out_dir"
}

@test "export: fails for non-existent profile" {
    run bash "$MANGOLOVE_DIR/lib/profile-manager.sh" export "nonexistent"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

@test "import: imports .mangolove.md to projects directory" {
    local src=$(mktemp -d)
    cat > "$src/.mangolove.md" << 'EOF'
---
name: Imported Project
path: /tmp/imported
tech_stack: [Rust]
---
EOF

    run bash "$MANGOLOVE_DIR/lib/profile-manager.sh" import "$src/.mangolove.md"
    [ "$status" -eq 0 ]
    [ -f "$MANGOLOVE_DIR/projects/imported-project.md" ]
    rm -rf "$src"
}

@test "import: fails for non-existent file" {
    run bash "$MANGOLOVE_DIR/lib/profile-manager.sh" import "/nonexistent/file.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

# ─────────────────────────────────────────────
# JPA, QueryDSL, database detection
# ─────────────────────────────────────────────

@test "auto: detects JPA and MySQL in Gradle project" {
    local proj=$(create_fake_project "jpa-app")
    cat > "$proj/build.gradle" << 'EOF'
plugins {
    id 'org.springframework.boot' version '3.2.0'
}
dependencies {
    implementation 'org.springframework.boot:spring-boot-starter-data-jpa'
    runtimeOnly 'mysql:mysql-connector-java'
}
EOF
    mkdir -p "$proj/src/main/java"

    run bash "$MANGOLOVE_DIR/lib/profile-manager.sh" auto "$proj"
    [ "$status" -eq 0 ]
    [[ "$output" == *"JPA"* ]]
    [[ "$output" == *"MySQL"* ]]
}

@test "auto: detects Redis and Kafka in Gradle project" {
    local proj=$(create_fake_project "messaging-app")
    cat > "$proj/build.gradle" << 'EOF'
dependencies {
    implementation 'org.springframework.boot:spring-boot-starter-data-redis'
    implementation 'org.springframework.kafka:spring-kafka'
}
EOF
    mkdir -p "$proj/src/main/java"

    run bash "$MANGOLOVE_DIR/lib/profile-manager.sh" auto "$proj"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Redis"* ]]
    [[ "$output" == *"Kafka"* ]]
}
