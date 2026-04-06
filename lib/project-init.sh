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
    local strict="$2"

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

    if [ "$strict" = "true" ]; then
        content="${content}

## 필수 워크플로우 (Strict Mode)

모든 작업에서 반드시 이 워크플로우를 따를 것. 예외 없음.

### 1단계: 분석 (항상 먼저)
사용자가 문제나 기능을 설명하면:
1. 응답 전에 관련 파일을 모두 읽을 것
2. 전체 호출 체인을 추적 (Controller -> Service -> Repository -> Entity -> DTO)
3. 영향 받는 모든 파일을 식별
4. 계획을 제시:
   - 근본 원인 / 요구사항 분석
   - 수정할 파일 목록과 구체적 변경 내용
   - 잠재적 위험과 엣지 케이스
   - 기존 테스트에 미치는 영향
5. 코드 작성 전 사용자 승인을 기다릴 것

### 2단계: 구현
사용자가 계획을 승인한 후:
1. 계획대로 정확히 구현
2. 코드를 작성할 때마다 다음을 검증:

**보안**
- SQL Injection 금지 (파라미터 바인딩 사용, 문자열 결합 금지)
- XSS 금지 (모든 사용자 입력을 이스케이프)
- 시크릿, 인증 정보, API 키 하드코딩 금지
- 모든 엔드포인트에 인증/인가 확인
- 모든 public API 파라미터에 입력 검증
- 로그나 에러 메시지에 민감한 데이터 포함 금지

**스타일 및 컨벤션**$([ -n "$PROJ_LINT" ] && echo "
- \`${PROJ_LINT}\` 실행 후 모든 경고 수정")
- 프로젝트의 기존 네이밍 패턴을 정확히 따를 것
- 주변 코드의 들여쓰기와 포맷을 맞출 것
- 사용하지 않는 import, 변수, 데드 코드 금지
- 주석 처리된 코드 블록 금지
- 메서드 길이: 30줄 이하 권장
- 클래스 길이: 300줄 이하 권장

**성능**
- N+1 쿼리 패턴 금지 (JOIN 또는 배치 조회 사용)
- 루프 내 불필요한 객체 생성 금지
- 비동기/리액티브 코드에서 블로킹 호출 금지
- 목록 조회 엔드포인트에 페이지네이션 적용
- 새로운 쿼리에 인덱스 활용 검토

**유지보수성 및 가독성**
- 단일 책임 원칙: 각 메서드는 하나의 일만 수행
- 명확하고 서술적인 네이밍 (\`tmp\`, \`val\`, \`x\` 같은 약어 금지)
- 복잡한 조건문은 이름 있는 boolean 메서드로 추출
- 매직 넘버나 매직 스트링 금지 — 상수 사용
- 에러 메시지는 구체적이고 조치 가능하게 작성

**Null Safety 및 에러 처리**
- 모든 nullable 값을 명시적으로 처리
- public 메서드에서 null 반환 금지 — Optional 또는 빈 컬렉션 사용
- 구체적 예외를 catch (Exception 같은 범용 예외 금지)
- 에러 메시지에 컨텍스트 포함 (무엇이 실패했고, 입력값은 무엇이었는지)

3. 모든 변경 완료 후 실행:
   \`\`\`
   ${PROJ_BUILD}$([ -n "$PROJ_LINT" ] && echo " && ${PROJ_LINT}")$([ -n "$PROJ_TYPECHECK" ] && echo " && ${PROJ_TYPECHECK}") && ${PROJ_TEST}
   \`\`\`
   실패 시 수정 후 재실행.

### 3단계: 셀프 리뷰 (필수)
구현 완료 및 모든 체크 통과 후, 비판적 셀프 리뷰 수행:

1. 변경된 모든 파일을 적대적 코드 리뷰어 관점에서 다시 읽을 것
2. 아래 항목을 점검 — 하나라도 실패하면 즉시 수정:
   - [ ] 보안 취약점 없음 (OWASP Top 10)
   - [ ] 성능 안티패턴 없음 (N+1, 불필요한 객체 할당)
   - [ ] 모든 public 메서드에 명확한 이름과 문서화
   - [ ] 에러 처리 완전 (삼켜진 예외 없음)
   - [ ] 코드 중복 없음
   - [ ] 기존 코드베이스 패턴과 일관성 유지
   - [ ] 새로운 코드 경로에 테스트 커버리지 확보
   - [ ] 설정 가능해야 할 값의 하드코딩 없음
   - [ ] 공유 상태에 대한 스레드 안전성 검토
   - [ ] API 응답이 기존 형식과 일관성 유지
3. 셀프 리뷰에서 문제 발견 시 수정 후 체크 재실행
4. 셀프 리뷰 결과를 사용자에게 보고

### 4단계: 완료 보고
셀프 리뷰 통과 후 보고:
\`\`\`
변경 사항:
  - [수정된 파일 목록과 변경 내용]

검증 결과:
  - 빌드: PASS
  - 린트: PASS$([ -n "$PROJ_TYPECHECK" ] && echo "
  - 타입 체크: PASS")
  - 테스트: PASS (N개 통과, N개 신규)

셀프 리뷰:
  - 보안: PASS
  - 성능: PASS
  - 스타일: PASS
  - 유지보수성: PASS
\`\`\`

## 자동 행동 전환

모든 응답 전에 사용자의 요청을 분석하고, 아래 조건에 해당하면 자동으로 해당 행동을 활성화할 것. 사용자가 별도 커맨드를 입력할 필요 없음.

| 감지 조건 | 자동 행동 |
|-----------|----------|
| 버그 리포트, 에러 로그, \"안 돼\", \"오류\" | 체계적 디버깅: 재현 -> 근본 원인 추적 -> 수정 -> 회귀 테스트 |
| 새 기능 요청, \"추가해줘\", \"만들어줘\" | 1단계 분석 먼저 시작, 설계 질문 3개 이상 |
| 리팩토링, \"정리\", \"개선\", \"구조 변경\" | 기존 테스트 확인 -> 동작 변경 없이 구조 개선 -> 테스트 통과 확인 |
| 코드 리뷰 요청, \"봐줘\", \"리뷰\" | 보안/성능/스타일/정확성 관점 리뷰, 파일:줄번호와 수정 제안 |
| 성능 문제, \"느려\", \"최적화\" | 프로파일링 먼저 -> 병목 식별 -> 측정 가능한 개선 |
| 테스트 작성 | RED-GREEN-REFACTOR: 실패 테스트 먼저 -> 최소 구현 -> 리팩토링 |
| DB 스키마 변경, 엔티티 수정 | 마이그레이션 영향 분석 먼저, 롤백 계획 포함 |
| PR 생성, \"PR 만들어\" | 전체 변경 사항 리뷰 -> 셀프 리뷰 -> PR 제목/본문 작성 |

잘 모르겠으면 분석 모드(1단계)로 시작할 것.

## Subagent 병렬 작업

작업이 2개 이상의 독립적인 파일/모듈에 걸칠 때:
1. 각 독립 작업을 Agent 도구로 병렬 수행
2. 모든 subagent 완료 후 통합 검증

### 2단계 리뷰 프로세스
구현 완료 후, 2개의 리뷰 에이전트를 **병렬로** 실행:

**리뷰어 1: 명세 준수 리뷰**
- 요구사항이 모두 반영됐는지 확인
- 누락된 엣지 케이스가 없는지 확인
- API 계약(요청/응답 형식)이 명세와 일치하는지 확인

**리뷰어 2: 코드 품질 리뷰**
- 보안 취약점 점검
- 성능 안티패턴 점검
- 스타일 가이드 준수 점검
- 테스트 커버리지 점검

두 리뷰어의 지적 사항을 모두 수정한 후에만 완료 보고.

## 학습 시스템

프로젝트 루트의 \`.claude/learnings.md\` 파일에 교훈을 축적한다.

**기록 시점:**
- 디버깅에서 근본 원인을 찾았을 때
- 코드 리뷰에서 반복되는 패턴을 발견했을 때
- 빌드/테스트 실패 후 해결했을 때
- 사용자가 수정을 요청했을 때 (내가 놓친 것)

**기록 형식:**
\`\`\`markdown
### YYYY-MM-DD: 제목
- 상황: 무엇이 있었는지
- 교훈: 무엇을 배웠는지
- 적용: 앞으로 어떻게 할지
\`\`\`

**사용:** 매 세션 시작 시 \`.claude/learnings.md\`를 읽고, 같은 실수를 반복하지 않을 것."
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
    claude_md=$(generate_claude_md "$target_dir" "$strict")

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
