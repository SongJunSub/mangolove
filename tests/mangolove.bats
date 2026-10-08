#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove: Main CLI Tests
# ─────────────────────────────────────────────

load test_helper

setup() {
    setup_test_env
    # Copy main executable
    cp "$BATS_TEST_DIRNAME/../bin/mangolove" "$MANGOLOVE_DIR/bin/mangolove"
    chmod +x "$MANGOLOVE_DIR/bin/mangolove"
}

teardown() {
    teardown_test_env
}

# ─────────────────────────────────────────────
# version
# ─────────────────────────────────────────────

@test "version: displays version string" {
    run bash "$MANGOLOVE_DIR/bin/mangolove" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"MangoLove"* ]]
    # 버전은 bin/mangolove 의 MANGOLOVE_VERSION 이 단일 출처: 하드코딩하면 릴리스마다 깨진다.
    local expected_version
    expected_version=$(grep -m1 '^MANGOLOVE_VERSION=' "$BATS_TEST_DIRNAME/../bin/mangolove" | cut -d'"' -f2)
    [ -n "$expected_version" ]
    [[ "$output" == *"$expected_version"* ]]
}

@test "version: -v shorthand works" {
    run bash "$MANGOLOVE_DIR/bin/mangolove" -v
    [ "$status" -eq 0 ]
    [[ "$output" == *"MangoLove"* ]]
}

# ─────────────────────────────────────────────
# help
# ─────────────────────────────────────────────

@test "help: displays usage information" {
    run bash "$MANGOLOVE_DIR/bin/mangolove" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"Commands"* ]]
    [[ "$output" == *"Modes"* ]]
    [[ "$output" == *"Options"* ]]
}

@test "help: --help flag works" {
    run bash "$MANGOLOVE_DIR/bin/mangolove" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "help: -h shorthand works" {
    run bash "$MANGOLOVE_DIR/bin/mangolove" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "help: lists all available modes" {
    run bash "$MANGOLOVE_DIR/bin/mangolove" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"review"* ]]
    [[ "$output" == *"debug"* ]]
    [[ "$output" == *"refactor"* ]]
    [[ "$output" == *"security"* ]]
    [[ "$output" == *"plan"* ]]
    [[ "$output" == *"pr"* ]]
}

@test "help: lists all subcommands" {
    run bash "$MANGOLOVE_DIR/bin/mangolove" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"projects"* ]]
    [[ "$output" == *"profile"* ]]
    [[ "$output" == *"plugin"* ]]
    [[ "$output" == *"log"* ]]
    [[ "$output" == *"update"* ]]
    [[ "$output" == *"doctor"* ]]
}

# ─────────────────────────────────────────────
# doctor
# ─────────────────────────────────────────────

@test "doctor: runs without error" {
    run bash "$MANGOLOVE_DIR/bin/mangolove" doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"Doctor"* ]]
}

@test "doctor: checks for Git" {
    run bash "$MANGOLOVE_DIR/bin/mangolove" doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"Git"* ]]
}

@test "doctor: reports MangoLove component status" {
    run bash "$MANGOLOVE_DIR/bin/mangolove" doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"System prompt"* ]]
    [[ "$output" == *"Banner"* ]]
    [[ "$output" == *"Work logger"* ]]
    [[ "$output" == *"Profile manager"* ]]
}

@test "doctor: reports profile and mode counts" {
    run bash "$MANGOLOVE_DIR/bin/mangolove" doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"Project profiles"* ]]
    [[ "$output" == *"Modes"* ]]
}

@test "doctor: reports installed project quality gate in cwd" {
    local proj="$TEST_DIR/doctor-gate"
    mkdir -p "$proj/.mangolove/hooks"
    cp "$MANGOLOVE_DIR/lib/quality-gate.sh" "$proj/.mangolove/hooks/quality-gate.sh"
    cd "$proj"
    run bash "$MANGOLOVE_DIR/bin/mangolove" doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"Project gate"* ]]
    [[ "$output" == *"Quality gate installed"* ]]
}

@test "doctor: reports a committed gate as version-controlled" {
    local proj="$TEST_DIR/doctor-gate-tracked"
    mkdir -p "$proj/.mangolove/hooks"
    cp "$MANGOLOVE_DIR/lib/quality-gate.sh" "$proj/.mangolove/hooks/quality-gate.sh"
    git -C "$proj" init -q
    git -C "$proj" -c user.email=t@t.com -c user.name=t add .mangolove
    git -C "$proj" -c user.email=t@t.com -c user.name=t commit -qm gate
    cd "$proj"
    run bash "$MANGOLOVE_DIR/bin/mangolove" doctor
    [[ "$output" == *"version-controlled"* ]]
}

@test "doctor: warns when the gate is not committed" {
    local proj="$TEST_DIR/doctor-gate-uncommitted"
    mkdir -p "$proj/.mangolove/hooks"
    cp "$MANGOLOVE_DIR/lib/quality-gate.sh" "$proj/.mangolove/hooks/quality-gate.sh"
    git -C "$proj" init -q
    cd "$proj"
    run bash "$MANGOLOVE_DIR/bin/mangolove" doctor
    [[ "$output" == *"not committed"* ]]
}

@test "doctor: warns when .mangolove is gitignored (silently disabled)" {
    local proj="$TEST_DIR/doctor-gate-ignored"
    mkdir -p "$proj/.mangolove/hooks"
    cp "$MANGOLOVE_DIR/lib/quality-gate.sh" "$proj/.mangolove/hooks/quality-gate.sh"
    git -C "$proj" init -q
    echo '.mangolove/' > "$proj/.gitignore"
    cd "$proj"
    run bash "$MANGOLOVE_DIR/bin/mangolove" doctor
    [[ "$output" == *"gitignored"* ]]
}

@test "doctor: reports session gates enabled" {
    cd "$TEST_DIR"
    run bash "$MANGOLOVE_DIR/bin/mangolove" doctor
    [[ "$output" == *"Session gates"* ]]
}

@test "session-settings: generate_session_settings writes valid JSON with both hooks" {
    command -v python3 >/dev/null 2>&1 || skip "needs python3"
    local out="$TEST_DIR/session-settings.json"
    run bash -c "source '$MANGOLOVE_DIR/bin/mangolove'; generate_session_settings '$out'"
    [ "$status" -eq 0 ]
    [ -f "$out" ]
    python3 -c "import json; json.load(open('$out'))"
    grep -q "PreToolUse" "$out"
    grep -q "irreversible-guard.sh" "$out"
    grep -q "quality-gate.sh" "$out"
}

# 컨텍스트가 커졌다는 이유로 턴을 붙잡아 "이어갈지 /compact 할지 /clear 할지"를 묻게 하던
# 세션 예산 훅은 사용자 결정으로 없앴다(끊을 시점은 사용자가 상태줄을 보고 판단한다).
# Stop 에 남는 것은 DoD 게이트뿐이어야 한다.
@test "session-settings: 컨텍스트 크기로 턴을 붙잡는 훅을 싣지 않는다" {
    local out="$TEST_DIR/session-settings.json"
    run bash -c "source '$MANGOLOVE_DIR/bin/mangolove'; generate_session_settings '$out'"
    [ "$status" -eq 0 ]
    ! grep -qi "budget" "$out"
}

# 제거 전에 뜬 세션은 설정에 남은 경로로 이 스크립트를 계속 부른다. 파일이 없으면 턴마다 훅
# 오류 알림이 뜨므로 빈 껍데기를 남긴다. 무엇이 들어와도 조용히 0 으로 끝나야 한다.
@test "session-budget: 남겨 둔 껍데기는 큰 컨텍스트 payload 에도 아무것도 하지 않는다" {
    local tr="$TEST_DIR/t.jsonl"
    printf '{"message":{"usage":{"input_tokens":900000,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' > "$tr"
    run bash -c "printf '{\"session_id\":\"s1\",\"transcript_path\":\"%s\",\"stop_hook_active\":false}' '$tr' | MANGOLOVE_SESSION_BUDGET_TOKENS=400000 bash '$MANGOLOVE_DIR/lib/session-budget.sh'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "session-settings: review gate injects PreToolUse+PostToolUse pair when on, nothing when off" {
    command -v python3 >/dev/null 2>&1 || skip "needs python3"
    local on="$TEST_DIR/on.json" off="$TEST_DIR/off.json"
    run bash -c "source '$MANGOLOVE_DIR/bin/mangolove'
      MANGOLOVE_REVIEW_GATE=on  generate_session_settings '$on'
      MANGOLOVE_REVIEW_GATE=off generate_session_settings '$off'"
    [ "$status" -eq 0 ]
    # 두 훅은 짝이어야 한다: record 없이 pretooluse 만 있으면 원장이 비어 항상 차단된다.
    python3 -c "import json; json.load(open('$on'))"
    grep -qF 'review-gate.sh\" pretooluse' "$on"
    grep -qF 'review-gate.sh\" record' "$on"
    grep -q '"matcher": "Skill"' "$on"
    python3 -c "import json; json.load(open('$off'))"
    ! grep -q "review-gate.sh" "$off"
    ! grep -q "PostToolUse" "$off"
}

@test "doctor: reports review gate state" {
    cd "$TEST_DIR"
    run bash "$MANGOLOVE_DIR/bin/mangolove" doctor
    [[ "$output" == *"Review gate"* ]]
}

# ─────────────────────────────────────────────
# mode validation
# ─────────────────────────────────────────────

@test "mode: rejects unknown mode" {
    run bash "$MANGOLOVE_DIR/bin/mangolove" --mode nonexistent
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown mode"* ]]
    [[ "$output" == *"Available modes"* ]]
}

@test "mode: shows usage when --mode has no argument" {
    run bash "$MANGOLOVE_DIR/bin/mangolove" --mode
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

# ─────────────────────────────────────────────
# projects subcommand
# ─────────────────────────────────────────────

@test "projects: delegates to profile-manager list" {
    run bash "$MANGOLOVE_DIR/bin/mangolove" projects
    [ "$status" -eq 0 ]
    [[ "$output" == *"Project Profiles"* ]]
}

# ─────────────────────────────────────────────
# log subcommand
# ─────────────────────────────────────────────

@test "log: shows usage with no arguments" {
    run bash "$MANGOLOVE_DIR/bin/mangolove" log
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

# ─────────────────────────────────────────────
# plugin subcommand
# ─────────────────────────────────────────────

@test "plugin: lists plugins with no arguments" {
    run bash "$MANGOLOVE_DIR/bin/mangolove" plugin
    [ "$status" -eq 0 ]
    [[ "$output" == *"Plugins"* ]]
}

@test "plugins: alias works" {
    run bash "$MANGOLOVE_DIR/bin/mangolove" plugins
    [ "$status" -eq 0 ]
    [[ "$output" == *"Plugins"* ]]
}

@test "defaults: 메서드러지 split + DoD 게이트 + 리뷰 게이트가 기본 on 이다" {
    # 이 세 기본값은 명시적 결정의 결과다(각각 컨텍스트 예산, 완료 검증, 리뷰 강제).
    # 우연히 되돌려지면 MangoLove 가 조용히 예전 동작으로 후퇴하므로 기본값 자체를 고정한다.
    local b="$MANGOLOVE_DIR/bin/mangolove"
    grep -qE '^MANGOLOVE_METHODOLOGY_MODE="?split"?$' "$b"
    grep -qE '^MANGOLOVE_DOD_GATE=on$' "$b"
    grep -qE '^MANGOLOVE_REVIEW_GATE=on$' "$b"
}

@test "doctor: split 기본에서 메서드러지 모드를 split 으로 보고한다" {
    cd "$TEST_DIR"
    run bash "$MANGOLOVE_DIR/bin/mangolove" doctor
    [[ "$output" == *"Methodology mode: split"* ]]
}

@test "flags: off 뿐 아니라 false/0/no 도 끄기로 해석한다" {
    # config.sh 에 MANGOLOVE_SESSION_GATES=true 같은 불리언 스타일이 섞여 있어,
    # off 만 인정하면 false 라고 적은 사용자가 꺼졌다고 믿는데 켜져 있게 된다.
    command -v python3 >/dev/null 2>&1 || skip "needs python3"
    local out="$TEST_DIR/f.json"
    local v
    for v in off OFF false 0 no; do
        run bash -c "source '$MANGOLOVE_DIR/bin/mangolove'; MANGOLOVE_REVIEW_GATE=$v generate_session_settings '$out'"
        [ "$status" -eq 0 ]
        ! grep -q "review-gate.sh" "$out" || { echo "값 '$v' 에서 게이트가 여전히 주입됨"; false; }
    done
    run bash -c "source '$MANGOLOVE_DIR/bin/mangolove'; MANGOLOVE_REVIEW_GATE=on generate_session_settings '$out'"
    grep -q "review-gate.sh" "$out"
}

# ─────────────────────────────────────────────
# AI 저작 표기: 방법론의 금지를 설정으로 닫는다
# ─────────────────────────────────────────────

@test "session-settings: 커밋 트레일러와 PR 푸터 attribution 을 비운다 (객체형)" {
    command -v python3 >/dev/null 2>&1 || skip "needs python3"
    local out="$TEST_DIR/session-settings.json"
    run bash -c "source '$MANGOLOVE_DIR/bin/mangolove'; generate_session_settings '$out'"
    [ "$status" -eq 0 ]
    # false 단축형이 아니라 객체형이어야 한다: 구버전 CLI 는 false 를 든 설정 파일을 통째로
    # 건너뛰고, 그러면 이 파일이 싣는 게이트 훅까지 함께 빠진다.
    python3 -c "
import json
a = json.load(open('$out'))['attribution']
assert a == {'commit': '', 'pr': ''}, a
"
}

# ─────────────────────────────────────────────
# 재개 경로: claude v2.1.265 부터 대화 첫 요청의 시스템 프롬프트가 세션에 기록되고
# --continue / --resume 뒤에도 압축 전까지 재사용된다. 실측(v2.1.293): 재개하며 넘긴 새
# --append-system-prompt 는 무시되고 --system-prompt-snapshot off 에서만 반영된다.
# ─────────────────────────────────────────────

# claude 를 셸 함수로 가린다. --version 은 $1 을 내고, 그 밖의 호출은 인자를 한 줄씩 기록한다.
_stub_claude() {
    cat <<STUB
claude() {
    if [ "\${1:-}" = "--version" ]; then echo "$1 (Claude Code)"; return 0; fi
    { printf '%s\n' "\$@"; echo "<<END>>"; } >> "$TEST_DIR/claude-calls"
    return \${STUB_RC:-0}
}
STUB
}

@test "version: _ml_version_ge 는 점 구분 버전을 수로 비교한다" {
    run bash -c "source '$MANGOLOVE_DIR/bin/mangolove'
      _ml_version_ge 2.1.293 2.1.257 || exit 1
      _ml_version_ge 2.1.257 2.1.257 || exit 2
      _ml_version_ge 3.0.0 2.1.257   || exit 3
      # 문자열 비교였다면 99 > 257 로 통과한다
      if _ml_version_ge 2.1.99 2.1.257;  then exit 4; fi
      if _ml_version_ge 2.0.300 2.1.257; then exit 5; fi
      # 버전을 못 읽으면 '충족'이 아니다: 모르는 플래그를 넘겨 실행을 깨뜨리지 않는다
      if _ml_version_ge '' 2.1.257;      then exit 6; fi
      exit 0"
    [ "$status" -eq 0 ]
}

@test "resume: 재개 플래그가 있으면 시스템 프롬프트 스냅샷을 끈다" {
    run bash -c "source '$MANGOLOVE_DIR/bin/mangolove'
      $(_stub_claude 2.1.293)
      for f in -c --continue -r --resume --resume=abc --from-pr; do
        _ml_snapshot_args \"\$f\"
        [ \"\${ML_SNAPSHOT_ARGS[*]}\" = '--system-prompt-snapshot off' ] || { echo \"miss: \$f\"; exit 1; }
      done"
    [ "$status" -eq 0 ]
}

@test "resume: 새 대화에는 스냅샷 플래그를 넘기지 않는다 (캐시 안정성 유지)" {
    run bash -c "source '$MANGOLOVE_DIR/bin/mangolove'
      $(_stub_claude 2.1.293)
      _ml_snapshot_args;                          [ \${#ML_SNAPSHOT_ARGS[@]} -eq 0 ] || exit 1
      _ml_snapshot_args 'fix the -c option';      [ \${#ML_SNAPSHOT_ARGS[@]} -eq 0 ] || exit 2
      _ml_snapshot_args --model opus 'hello';     [ \${#ML_SNAPSHOT_ARGS[@]} -eq 0 ] || exit 3
      exit 0"
    [ "$status" -eq 0 ]
}

@test "resume: 플래그를 모르는 구버전 claude 에는 넘기지 않는다" {
    # v2.1.257 미만은 --system-prompt-snapshot 을 모르는 옵션으로 거부해 실행 자체가 깨진다.
    run bash -c "source '$MANGOLOVE_DIR/bin/mangolove'
      $(_stub_claude 2.1.240)
      _ml_snapshot_args -c; [ \${#ML_SNAPSHOT_ARGS[@]} -eq 0 ]"
    [ "$status" -eq 0 ]
}

@test "resume: 버전을 읽지 못하면 플래그를 넘기지 않되 그 사실을 알린다" {
    # 조용히 넘어가면, 최신 CLI 에서 재개한 대화가 옛 프롬프트로 도는 것을 알 길이 없다.
    run bash -c "source '$MANGOLOVE_DIR/bin/mangolove'
      claude() { echo 'dev-build'; }
      _ml_snapshot_args -c
      [ \${#ML_SNAPSHOT_ARGS[@]} -eq 0 ]"
    [ "$status" -eq 0 ]
    [[ "$output" == *"버전을 읽지 못해"* ]]
}

@test "resume: 사용자가 직접 준 --system-prompt-snapshot 은 건드리지 않는다" {
    run bash -c "source '$MANGOLOVE_DIR/bin/mangolove'
      $(_stub_claude 2.1.293)
      _ml_snapshot_args -c --system-prompt-snapshot on; [ \${#ML_SNAPSHOT_ARGS[@]} -eq 0 ]"
    [ "$status" -eq 0 ]
}

@test "launch: 평소에는 인자를 그대로 넘기고 claude 를 한 번만 부른다" {
    run bash -c "source '$MANGOLOVE_DIR/bin/mangolove'
      $(_stub_claude 2.1.293)
      CLAUDE_ARGS=(--settings /tmp/s.json); ML_RESUME=0
      _ml_launch 'hello world'"
    [ "$status" -eq 0 ]
    [ "$(grep -c '<<END>>' "$TEST_DIR/claude-calls")" -eq 1 ]
    [ "$(tr '\n' '|' < "$TEST_DIR/claude-calls")" = "--settings|/tmp/s.json|hello world|<<END>>|" ]
}

@test "launch: -c 로 재개하면 스냅샷을 끄고 나머지는 그대로다" {
    run bash -c "source '$MANGOLOVE_DIR/bin/mangolove'
      $(_stub_claude 2.1.293)
      CLAUDE_ARGS=(--settings /tmp/s.json); ML_RESUME=0
      _ml_launch -c"
    [ "$status" -eq 0 ]
    [ "$(tr '\n' '|' < "$TEST_DIR/claude-calls")" = "--settings|/tmp/s.json|--system-prompt-snapshot|off|-c|<<END>>|" ]
}

# 세션 메모리 load 가 고정된 컨텍스트 한 줄을 내게 한다.
_stub_session_memory() {
    cat > "$MANGOLOVE_DIR/lib/session-memory.sh" <<'SM'
#!/bin/bash
[ "$1" = "load" ] && echo "branch: feat/x"
SM
}

# mangolove resume: 예전에는 게이트(--settings)도 플러그인도 없이 claude 를 따로 띄웠다.
# 세션 컨텍스트는 시스템 프롬프트에 싣는다(_ml_resume_context). 위치 인자로 넘기면 재개 즉시
# 요청이 나가, 캐시가 만료된 큰 대화에서 사용자가 판단하기도 전에 재캐시 비용이 발생한다.
@test "resume: 세션 메모리를 시스템 프롬프트에 덧붙일 블록으로 낸다" {
    _stub_session_memory
    run bash -c "source '$MANGOLOVE_DIR/bin/mangolove'; _ml_resume_context"
    [ "$status" -eq 0 ]
    [[ "$output" == "## Previous Session Context"* ]]
    [[ "$output" == *"branch: feat/x"* ]]
}

@test "resume: 저장된 세션 메모리가 없으면 아무것도 덧붙이지 않는다" {
    printf '#!/bin/bash\nexit 0\n' > "$MANGOLOVE_DIR/lib/session-memory.sh"
    run bash -c "source '$MANGOLOVE_DIR/bin/mangolove'; _ml_resume_context"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "launch: mangolove resume 은 게이트를 실은 채 -c 로 잇고 메시지를 자동 제출하지 않는다" {
    run bash -c "source '$MANGOLOVE_DIR/bin/mangolove'
      $(_stub_claude 2.1.293)
      CLAUDE_ARGS=(--settings /tmp/s.json --append-system-prompt METHODOLOGY); ML_RESUME=1
      _ml_launch"
    [ "$status" -eq 0 ]
    # 마지막 인자가 -c 다: 위치 인자(자동 제출되는 첫 메시지)가 없다
    [ "$(tr '\n' '|' < "$TEST_DIR/claude-calls")" = "--settings|/tmp/s.json|--append-system-prompt|METHODOLOGY|--system-prompt-snapshot|off|-c|<<END>>|" ]
}

@test "launch: 이을 대화가 없어 -c 가 실패하면 새 대화를 연다 (자동 제출 없이)" {
    # 첫 호출(-c)만 실패시킨다
    run bash -c "source '$MANGOLOVE_DIR/bin/mangolove'
      claude() {
          if [ \"\${1:-}\" = '--version' ]; then echo '2.1.293 (Claude Code)'; return 0; fi
          { printf '%s\n' \"\$@\"; echo '<<END>>'; } >> '$TEST_DIR/claude-calls'
          case \" \$* \" in *' -c '*) return 1 ;; esac
          return 0
      }
      CLAUDE_ARGS=(--settings /tmp/s.json); ML_RESUME=1
      _ml_launch"
    [ "$status" -eq 0 ]
    # 새 대화에는 -c 도 스냅샷 플래그도 없다
    [ "$(tr '\n' '|' < "$TEST_DIR/claude-calls")" = "--settings|/tmp/s.json|--system-prompt-snapshot|off|-c|<<END>>|--settings|/tmp/s.json|<<END>>|" ]
}

@test "session-settings: 재개 안내는 환경변수로도 끌 수 있다" {
    # 기본값을 무조건 대입하면 `MANGOLOVE_RESUME_NOTICE=off mangolove -c` 가 듣지 않는다.
    local out="$TEST_DIR/env-off.json"
    run env MANGOLOVE_RESUME_NOTICE=off bash -c "source '$MANGOLOVE_DIR/bin/mangolove'; generate_session_settings '$out'"
    [ "$status" -eq 0 ]
    ! grep -q "SessionStart" "$out"
}

@test "session-settings: 재개 안내 훅은 resume|fork 에만 걸리고 off 면 빠진다" {
    command -v python3 >/dev/null 2>&1 || skip "needs python3"
    local on="$TEST_DIR/on.json" off="$TEST_DIR/off.json"
    run bash -c "source '$MANGOLOVE_DIR/bin/mangolove'
      MANGOLOVE_RESUME_NOTICE=on  generate_session_settings '$on'
      MANGOLOVE_RESUME_NOTICE=off generate_session_settings '$off'"
    [ "$status" -eq 0 ]
    python3 -c "
import json
on = json.load(open('$on'))['hooks']['SessionStart']
assert len(on) == 1 and on[0]['matcher'] == 'resume|fork', on
assert 'resume-notice.sh' in on[0]['hooks'][0]['command'], on
off = json.load(open('$off'))['hooks']
assert 'SessionStart' not in off, off
"
}

# ─────────────────────────────────────────────
# doctor: claude 버전과 플러그인 검증 사유
# ─────────────────────────────────────────────

# PATH 앞에 가짜 claude 를 둔다. $1=버전, $2=plugin validate 의 종료코드(기본 0).
_fake_claude_bin() {
    install_fake_claude <<FAKE
if [ "\${1:-}" = "--version" ]; then echo "$1 (Claude Code)"; exit 0; fi
if [ "\${1:-}" = "plugin" ] && [ "\${2:-}" = "validate" ]; then
    [ "${2:-0}" = "0" ] && exit 0
    [ -n "\${FAKE_VALIDATE_QUIET:-}" ] || echo "plugin.json: name is required" >&2
    exit ${2:-0}
fi
exit 0
FAKE
}

# doctor 가 cc-plugin 검증까지 가도록 최소 플러그인과 core.md 를 둔다.
_fake_cc_plugin() {
    mkdir -p "$MANGOLOVE_DIR/cc-plugin/.claude-plugin" "$MANGOLOVE_DIR/methodology"
    echo '{}' > "$MANGOLOVE_DIR/cc-plugin/.claude-plugin/plugin.json"
    echo '# core' > "$MANGOLOVE_DIR/methodology/core.md"
}

@test "doctor: 게이트가 의존하는 수정보다 낮은 claude 버전을 경고한다" {
    _fake_claude_bin 2.1.240
    cd "$TEST_DIR"
    run env PATH="$TEST_DIR/fakebin:$PATH" bash "$MANGOLOVE_DIR/bin/mangolove" doctor
    [[ "$output" == *"2.1.240"* ]]
    [[ "$output" == *"2.1.259 이상 권장"* ]]
}

@test "doctor: 권장 버전 이상이면 버전 경고가 없다" {
    _fake_claude_bin 2.1.293
    cd "$TEST_DIR"
    run env PATH="$TEST_DIR/fakebin:$PATH" bash "$MANGOLOVE_DIR/bin/mangolove" doctor
    [[ "$output" == *"2.1.293"* ]]
    [[ "$output" != *"이상 권장"* ]]
}

@test "doctor: cc-plugin 검증이 실패하면 사유를 보여준다" {
    _fake_claude_bin 2.1.293 1
    _fake_cc_plugin
    cd "$TEST_DIR"
    run env PATH="$TEST_DIR/fakebin:$PATH" bash "$MANGOLOVE_DIR/bin/mangolove" doctor
    [[ "$output" == *"cc-plugin: 검증 실패"* ]]
    [[ "$output" == *"name is required"* ]]
}

@test "doctor: cc-plugin 검증이 통과하면 valid 로 보고한다" {
    _fake_claude_bin 2.1.293 0
    _fake_cc_plugin
    cd "$TEST_DIR"
    run env PATH="$TEST_DIR/fakebin:$PATH" bash "$MANGOLOVE_DIR/bin/mangolove" doctor
    [[ "$output" == *"cc-plugin: valid"* ]]
}

# doctor 는 set -eo pipefail 아래에서 돈다. grep 의 "불일치"가 실패로 번지면 헤더만 찍고 죽는다.
@test "doctor: 버전 문자열을 못 읽어도 끝까지 점검한다" {
    _fake_claude_bin dev-build
    cd "$TEST_DIR"
    run env PATH="$TEST_DIR/fakebin:$PATH" bash "$MANGOLOVE_DIR/bin/mangolove" doctor
    [[ "$output" == *"dev-build"* ]]
    [[ "$output" != *"이상 권장"* ]]
    [[ "$output" == *"Session gates"* ]]
}

@test "doctor: cc-plugin 검증이 출력 없이 실패해도 끝까지 점검한다" {
    _fake_claude_bin 2.1.293 1
    _fake_cc_plugin
    cd "$TEST_DIR"
    run env PATH="$TEST_DIR/fakebin:$PATH" FAKE_VALIDATE_QUIET=1 bash "$MANGOLOVE_DIR/bin/mangolove" doctor
    [[ "$output" == *"cc-plugin: 검증 실패"* ]]
    [[ "$output" == *"Session gates"* ]]
}

@test "doctor: 재개 필드가 없는 낮은 claude 버전에서는 재개 안내가 표시되지 않음을 알린다" {
    _fake_claude_bin 2.1.240
    cd "$TEST_DIR"
    run env PATH="$TEST_DIR/fakebin:$PATH" bash "$MANGOLOVE_DIR/bin/mangolove" doctor
    [[ "$output" == *"Resume notice: on 이지만 표시되지 않음"* ]]
}

# ─────────────────────────────────────────────
# AGENTS.md: claude v2.1.277 부터 CLAUDE.md 가 없는 프로젝트는 AGENTS.md 를 읽는다
# ─────────────────────────────────────────────

@test "instructions: CLAUDE.md 가 없으면 AGENTS.md 를 프로젝트 지침 파일로 본다" {
    mkdir -p "$TEST_DIR/a" "$TEST_DIR/b" "$TEST_DIR/c"
    echo x > "$TEST_DIR/a/AGENTS.md"
    echo x > "$TEST_DIR/b/AGENTS.md"; echo x > "$TEST_DIR/b/CLAUDE.md"
    run bash -c "source '$MANGOLOVE_DIR/bin/mangolove'
      [ \"\$(_ml_instructions_file '$TEST_DIR/a')\" = '$TEST_DIR/a/AGENTS.md' ] || exit 1
      [ \"\$(_ml_instructions_file '$TEST_DIR/b')\" = '$TEST_DIR/b/CLAUDE.md' ] || exit 2
      [ -z \"\$(_ml_instructions_file '$TEST_DIR/c')\" ] || exit 3
      exit 0"
    [ "$status" -eq 0 ]
}

@test "session-memory: AGENTS.md 만 있는 프로젝트에서도 테스트 명령을 저장한다" {
    mkdir -p "$TEST_DIR/agentsproj" && cd "$TEST_DIR/agentsproj"
    git init -q . && git -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
    printf 'Test: `npm run test:unit`\n' > AGENTS.md
    run bash "$MANGOLOVE_DIR/lib/session-memory.sh" save
    [ "$status" -eq 0 ]
    grep -q 'npm run test:unit' "$MANGOLOVE_DIR/sessions/agentsproj.md"
}

# ─────────────────────────────────────────────
# 업데이트: 설치본의 .gitignore 에 옛 게이트가 남긴 줄과, 실패해도 뜨는 자동 업데이트
# ─────────────────────────────────────────────

# 추적되는 .gitignore 를 가진 가짜 설치본. $1=경로
_fake_install_repo() {
    mkdir -p "$1"
    git -C "$1" init -q
    printf '# rules\n*.swp\n' > "$1/.gitignore"
    git -C "$1" add .gitignore
    git -C "$1" -c user.email=t@example.com -c user.name=t commit -q -m init
}

@test "update: 게이트가 덧붙인 줄만 있는 .gitignore 수정은 되돌린다" {
    local inst="$TEST_DIR/inst"
    _fake_install_repo "$inst"
    printf '.gitignore\ndod.sh\n.dod-gate-attempts\n.review-ledger\n.review-ledger.base\n.review-skip\n' >> "$inst/.gitignore"
    run bash -c "source '$MANGOLOVE_DIR/bin/mangolove'; _ml_heal_install_gitignore '$inst'"
    [ "$status" -eq 0 ]
    git -C "$inst" diff --quiet -- .gitignore
}

@test "update: 사용자가 손댄 줄이 섞인 .gitignore 는 건드리지 않는다" {
    local inst="$TEST_DIR/inst"
    _fake_install_repo "$inst"
    printf 'dod.sh\nmy-notes/\n' >> "$inst/.gitignore"
    run bash -c "source '$MANGOLOVE_DIR/bin/mangolove'; _ml_heal_install_gitignore '$inst'"
    [ "$status" -eq 0 ]
    grep -qx 'my-notes/' "$inst/.gitignore"
    grep -qx 'dod.sh' "$inst/.gitignore"
}

# origin 을 가진 가짜 설치본을 만든다. $1=작업 디렉토리. ORIGIN, INST 를 남긴다.
_install_with_origin() {
    local seed="$1/seed"
    ORIGIN="$1/origin.git"; INST="$1/inst"
    git init -q -b main "$seed"
    mkdir -p "$seed/bin" "$seed/lib"
    printf '# rules\n*.swp\n\n# tail\n.DS_Store\n' > "$seed/.gitignore"
    printf 'MANGOLOVE_VERSION="9.9.9"\n' > "$seed/bin/mangolove"
    printf '#!/bin/bash\n' > "$seed/lib/a.sh"
    git -C "$seed" add -A
    git -C "$seed" -c user.email=t@example.com -c user.name=t commit -q -m init
    git clone -q --bare "$seed" "$ORIGIN"
    git clone -q "$ORIGIN" "$INST"
    git -C "$seed" remote add origin "$ORIGIN"
}

# origin 에 커밋 하나를 더한다. $1=작업 디렉토리 $2=sed 식(.gitignore 에 적용)
_origin_changes_gitignore() {
    sed -i.bak "$2" "$1/seed/.gitignore" && rm -f "$1/seed/.gitignore.bak"
    git -C "$1/seed" -c user.email=t@example.com -c user.name=t commit -q -am "chore: gitignore"
    git -C "$1/seed" push -q origin main
}

_run_auto_update() {
    run bash -c "source '$MANGOLOVE_DIR/bin/mangolove'; MANGOLOVE_DIR='$INST'; auto_update_check; echo AFTER-CHECK"
}

@test "update: 게이트 줄이 남은 설치본도 .gitignore 를 바꾸는 버전으로 올라간다" {
    _install_with_origin "$TEST_DIR"
    printf '.gitignore\ndod.sh\n.dod-gate-attempts\n.review-skip\n' >> "$INST/.gitignore"
    _origin_changes_gitignore "$TEST_DIR" 's/^# rules$/# rules v2/'
    _run_auto_update
    [ "$status" -eq 0 ]
    [[ "$output" == *"AFTER-CHECK"* ]]
    [ "$(git -C "$INST" rev-parse HEAD)" = "$(git -C "$ORIGIN" rev-parse main)" ]
    git -C "$INST" diff --quiet -- .gitignore
}

@test "update: 새 버전이 건드리지 않는 파일의 로컬 수정은 그대로 둔 채 올라간다" {
    _install_with_origin "$TEST_DIR"
    printf '#!/bin/bash\necho local-edit\n' > "$INST/lib/a.sh"
    _origin_changes_gitignore "$TEST_DIR" 's/^# rules$/# rules v2/'
    _run_auto_update
    [ "$status" -eq 0 ]
    [ "$(git -C "$INST" rev-parse HEAD)" = "$(git -C "$ORIGIN" rev-parse main)" ]
    grep -q 'local-edit' "$INST/lib/a.sh"
}

# 로컬 수정을 치웠다 되돌리는 방식(autostash)은 쓰지 않는다: 되돌리다 충돌하면 pull 은 성공으로
# 끝나는데 파일에 충돌 표시가 남고, 그게 스크립트면 게이트가 죽은 채 세션이 뜬다.
@test "update: 사용자가 고친 파일을 새 버전이 건드리면 아무것도 바꾸지 않고 알린다" {
    _install_with_origin "$TEST_DIR"
    printf 'my-notes/\n' >> "$INST/.gitignore"
    local mine; mine="$(cat "$INST/.gitignore")"
    local before; before="$(git -C "$INST" rev-parse HEAD)"
    _origin_changes_gitignore "$TEST_DIR" 's/^# rules$/# rules v2/'
    _run_auto_update
    [ "$status" -eq 0 ]
    [[ "$output" == *"자동 업데이트에 실패"* ]]
    [[ "$output" == *"AFTER-CHECK"* ]]
    [ "$(git -C "$INST" rev-parse HEAD)" = "$before" ]
    # 사용자의 파일은 글자 하나 바뀌지 않았다(충돌 표시도 없다)
    [ "$(cat "$INST/.gitignore")" = "$mine" ]
    [ -z "$(git -C "$INST" diff --name-only --diff-filter=U)" ]
}

# 사용자의 전역 git 설정에 autostash 가 켜져 있으면 옵션을 안 줘도 git 이 autostash 를 돌린다.
# 되돌리다 충돌하면 병합은 성공으로 끝나고 스크립트에 충돌 표시가 남는다. 명시적으로 꺼야 한다.
@test "update: 전역 설정에 autostash 가 켜져 있어도 스크립트에 충돌 표시를 남기지 않는다" {
    _install_with_origin "$TEST_DIR"
    printf '#!/bin/bash\necho local-edit\n' > "$INST/lib/a.sh"
    printf '#!/bin/bash\necho upstream-edit\n' > "$TEST_DIR/seed/lib/a.sh"
    git -C "$TEST_DIR/seed" -c user.email=t@example.com -c user.name=t commit -q -am "feat: upstream edit"
    git -C "$TEST_DIR/seed" push -q origin main
    printf '[merge]\n\tautoStash = true\n[rebase]\n\tautoStash = true\n[pull]\n\trebase = true\n' > "$TEST_DIR/gitconfig"
    local before; before="$(git -C "$INST" rev-parse HEAD)"
    run env GIT_CONFIG_GLOBAL="$TEST_DIR/gitconfig" bash -c "source '$MANGOLOVE_DIR/bin/mangolove'; MANGOLOVE_DIR='$INST'; auto_update_check; echo AFTER-CHECK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"자동 업데이트에 실패"* ]]
    [[ "$output" == *"AFTER-CHECK"* ]]
    [ "$(git -C "$INST" rev-parse HEAD)" = "$before" ]
    [ "$(cat "$INST/lib/a.sh")" = "$(printf '#!/bin/bash\necho local-edit')" ]
}

# 실측 사고의 회귀 테스트: pull 이 실패하면 예전에는 그 종료코드로 mangolove 가 끝났다.
@test "update: pull 이 실패해도 실행을 막지 않고, 한 시간 뒤에 다시 시도한다" {
    _install_with_origin "$TEST_DIR"
    # 설치본에 로컬 커밋을 둬 fast-forward 가 불가능하게 만든다
    printf 'local\n' > "$INST/local.txt"
    git -C "$INST" add local.txt
    git -C "$INST" -c user.email=t@example.com -c user.name=t commit -q -m local
    local before; before="$(git -C "$INST" rev-parse HEAD)"
    _origin_changes_gitignore "$TEST_DIR" 's/^# rules$/# rules v2/'
    _run_auto_update
    [ "$status" -eq 0 ]
    [[ "$output" == *"자동 업데이트에 실패"* ]]
    [[ "$output" == *"AFTER-CHECK"* ]]
    # 실패한 pull 은 설치본의 추적 파일을 건드리지 않는다(--ff-only)
    [ "$(git -C "$INST" rev-parse HEAD)" = "$before" ]
    git -C "$INST" diff --quiet
    git -C "$INST" diff --cached --quiet
    # 하루가 아니라 한 시간 뒤에 다시 시도하도록 확인 시각을 당겨 적는다
    local stamp now; stamp="$(cat "$INST/.last_update_check")"; now="$(date +%s)"
    [ "$((now - stamp))" -ge 82000 ]
    [ "$((now - stamp))" -lt 86400 ]
    # 그 사이의 실행은 네트워크 확인도 경고도 되풀이하지 않는다
    _run_auto_update
    [ "$status" -eq 0 ]
    [[ "$output" != *"자동 업데이트에 실패"* ]]
}

@test "update: 확인 시각 파일이 깨져 있어도 실행을 막지 않는다" {
    _install_with_origin "$TEST_DIR"
    # 산술을 실제로 오류로 만드는 값들이다. 08 은 8진수로 읽혀서, 1.5 와 공백 섞인 값은 구문
    # 오류로. (not-a-number 같은 값은 변수 뺄셈으로 평가돼 오류가 나지 않아 회귀를 못 잡는다.)
    local bad
    for bad in '08' '1.5' 'abc def'; do
        printf '%s\n' "$bad" > "$INST/.last_update_check"
        _run_auto_update
        [ "$status" -eq 0 ] || { echo "aborted on: $bad"; false; }
        [[ "$output" == *"AFTER-CHECK"* ]] || { echo "no launch on: $bad"; false; }
    done
}

# install.sh 는 설치 전에도 돌아야 해서 bin/mangolove 의 함수를 못 쓰고 같은 판정을 한 벌 더 갖는다.
# 두 목록이 어긋나면 한쪽만 게이트 줄을 못 알아봐 막힌 설치본을 풀지 못한다.
@test "update: install.sh 와 bin/mangolove 의 게이트 줄 목록이 같다" {
    local repo="$BATS_TEST_DIRNAME/.." a b
    a="$(grep -oE "GATE_IGNORE_LINES='[^']+'" "$repo/bin/mangolove")"
    b="$(grep -oE "GATE_IGNORE_LINES='[^']+'" "$repo/install.sh")"
    [ -n "$a" ]
    [ "$a" = "$b" ]
}

@test "update: 확인 시각이 미래여도 업데이트 확인이 영영 꺼지지 않는다" {
    _install_with_origin "$TEST_DIR"
    printf '9999999999\n' > "$INST/.last_update_check"
    _run_auto_update
    [ "$status" -eq 0 ]
    # 확인이 돌았으면 시각이 지금으로 다시 적힌다
    [ "$(cat "$INST/.last_update_check")" -le "$(date +%s)" ]
}

@test "update: 수정이 없거나 git 설치본이 아니면 아무 일도 하지 않는다" {
    local inst="$TEST_DIR/inst"
    _fake_install_repo "$inst"
    run bash -c "source '$MANGOLOVE_DIR/bin/mangolove'; _ml_heal_install_gitignore '$inst' && _ml_heal_install_gitignore '$TEST_DIR/nope'"
    [ "$status" -eq 0 ]
    git -C "$inst" diff --quiet -- .gitignore
}

# ─────────────────────────────────────────────
# switch: 다른 프로젝트로 건너가도 MangoLove 세션이어야 한다
# 예전에는 프로젝트 폴더로 옮긴 뒤 claude 를 아무 인자 없이 띄웠다. 방법론도, 시크릿 스캔과
# 비가역 가드도, 리뷰 게이트도 없는 맨 claude 인데 겉으로는 구분되지 않았다(resume 과 같은 결함).
# ─────────────────────────────────────────────

# 받은 인자와 실행된 폴더를 기록하는 가짜 claude
_fake_claude_recording() {
    install_fake_claude <<FAKE
if [ "\${1:-}" = "--version" ]; then echo "2.1.293 (Claude Code)"; exit 0; fi
{ pwd -P; printf '%s\n' "\$@" | cut -c1-60; } > "$TEST_DIR/switch-calls"
exit 0
FAKE
}

_register_demo_project() {
    mkdir -p "$TEST_DIR/demoproj"
    printf 'name: demo\npath: %s\n' "$TEST_DIR/demoproj" > "$MANGOLOVE_DIR/projects/demo.md"
}

@test "switch: 인자가 없으면 목록만 내고 세션을 띄우지 않는다" {
    _fake_claude_recording
    _register_demo_project
    cd "$TEST_DIR"
    run env HOME="$TEST_DIR" PATH="$TEST_DIR/fakebin:$PATH" bash "$MANGOLOVE_DIR/bin/mangolove" switch </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"MangoLove Switch"* ]]
    [ ! -e "$TEST_DIR/switch-calls" ]
}

@test "switch: 이름을 주면 그 프로젝트 폴더에서 게이트와 방법론을 실은 채 뜬다" {
    command -v python3 >/dev/null 2>&1 || skip "needs python3"
    _fake_claude_recording
    _register_demo_project
    cd "$TEST_DIR"
    run env HOME="$TEST_DIR" PATH="$TEST_DIR/fakebin:$PATH" bash "$MANGOLOVE_DIR/bin/mangolove" switch demo </dev/null
    [ "$status" -eq 0 ]
    [ "$(head -1 "$TEST_DIR/switch-calls")" = "$(cd "$TEST_DIR/demoproj" && pwd -P)" ]
    grep -qx -- '--append-system-prompt' "$TEST_DIR/switch-calls"
    grep -qx -- '--settings' "$TEST_DIR/switch-calls"
    # 프로젝트 이름이 claude 의 프롬프트 인자로 새지 않는다
    # (bats 에서 `! 명령` 은 마지막 줄이 아니면 실패해도 통과한다. run 으로 받는다.)
    run grep -qx 'demo' "$TEST_DIR/switch-calls"
    [ "$status" -ne 0 ]
}

# 종료 trap 은 플러그인 훅과 작업 로거를 최대 10번(1초씩) 기다린다. 로거를 띄우지 않았을 때
# pid 자리에 0 을 두면 kill -0 0 이 항상 성공해 10번을 꽉 채웠다. 벽시계 대신 sleep 횟수를 센다.
@test "exit: 작업 로그가 꺼져 있으면 종료할 때 로거를 기다리지 않는다" {
    _fake_claude_recording
    cat > "$TEST_DIR/fakebin/sleep" <<FAKE
#!/bin/bash
echo x >> "$TEST_DIR/sleep-calls"
exec /bin/sleep 0.1
FAKE
    chmod +x "$TEST_DIR/fakebin/sleep"
    mkdir -p "$TEST_DIR/plain" && cd "$TEST_DIR/plain"
    run env HOME="$TEST_DIR" PATH="$TEST_DIR/fakebin:$PATH" bash "$MANGOLOVE_DIR/bin/mangolove" "hi" </dev/null
    [ "$status" -eq 0 ]
    local n=0
    [ -f "$TEST_DIR/sleep-calls" ] && n="$(wc -l < "$TEST_DIR/sleep-calls" | tr -d ' ')"
    [ "$n" -lt 8 ]
}

@test "switch: 없는 프로젝트면 세션을 띄우지 않고 실패한다" {
    _fake_claude_recording
    cd "$TEST_DIR"
    run env HOME="$TEST_DIR" PATH="$TEST_DIR/fakebin:$PATH" bash "$MANGOLOVE_DIR/bin/mangolove" switch nope </dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"Project not found"* ]]
    [ ! -e "$TEST_DIR/switch-calls" ]
}
