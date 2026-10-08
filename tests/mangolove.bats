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
    [ ! -e "$MANGOLOVE_DIR/lib/session-budget.sh" ]
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

# mangolove resume: 예전에는 게이트(--settings)도 플러그인도 없이 claude 를 따로 띄웠고,
# 세션 컨텍스트를 --append-system-prompt 로 넘겨 재개 시 통째로 무시됐다.
@test "launch: mangolove resume 은 게이트를 실은 채 -c 로 잇고 컨텍스트를 첫 메시지로 넘긴다" {
    cat > "$MANGOLOVE_DIR/lib/session-memory.sh" <<'SM'
#!/bin/bash
[ "$1" = "load" ] && echo "branch: feat/x"
SM
    run bash -c "source '$MANGOLOVE_DIR/bin/mangolove'
      $(_stub_claude 2.1.293)
      CLAUDE_ARGS=(--settings /tmp/s.json --append-system-prompt METHODOLOGY); ML_RESUME=1
      _ml_launch"
    [ "$status" -eq 0 ]
    [ "$(grep -c '<<END>>' "$TEST_DIR/claude-calls")" -eq 1 ]
    grep -qx -- '--settings' "$TEST_DIR/claude-calls"
    grep -qx -- '-c' "$TEST_DIR/claude-calls"
    grep -qx -- 'off' "$TEST_DIR/claude-calls"
    # 컨텍스트는 시스템 프롬프트 값이 아니라 마지막 위치 인자(첫 사용자 메시지)다
    grep -q 'branch: feat/x' "$TEST_DIR/claude-calls"
    grep -qx 'METHODOLOGY' "$TEST_DIR/claude-calls"
    [ "$(grep -c 'Previous Session Context' "$TEST_DIR/claude-calls")" -eq 1 ]
}

@test "launch: 이을 대화가 없어 -c 가 실패하면 새 대화로 같은 컨텍스트를 넘긴다" {
    cat > "$MANGOLOVE_DIR/lib/session-memory.sh" <<'SM'
#!/bin/bash
[ "$1" = "load" ] && echo "branch: feat/x"
SM
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
    [ "$(grep -c '<<END>>' "$TEST_DIR/claude-calls")" -eq 2 ]
    [ "$(grep -cx -- '-c' "$TEST_DIR/claude-calls")" -eq 1 ]
    # 새 대화에는 스냅샷 플래그가 필요 없다
    [ "$(grep -cx -- '--system-prompt-snapshot' "$TEST_DIR/claude-calls")" -eq 1 ]
    [ "$(grep -c 'branch: feat/x' "$TEST_DIR/claude-calls")" -eq 2 ]
}

# ─────────────────────────────────────────────
# doctor: claude 버전과 플러그인 검증 사유
# ─────────────────────────────────────────────

# PATH 앞에 가짜 claude 를 둔다. $1=버전, $2=plugin validate 의 종료코드(기본 0).
_fake_claude_bin() {
    mkdir -p "$TEST_DIR/fakebin"
    cat > "$TEST_DIR/fakebin/claude" <<FAKE
#!/bin/bash
if [ "\${1:-}" = "--version" ]; then echo "$1 (Claude Code)"; exit 0; fi
if [ "\${1:-}" = "plugin" ] && [ "\${2:-}" = "validate" ]; then
    [ "${2:-0}" = "0" ] && exit 0
    echo "plugin.json: name is required" >&2
    exit ${2:-0}
fi
exit 0
FAKE
    chmod +x "$TEST_DIR/fakebin/claude"
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
    mkdir -p "$MANGOLOVE_DIR/cc-plugin/.claude-plugin" "$MANGOLOVE_DIR/methodology"
    echo '{}' > "$MANGOLOVE_DIR/cc-plugin/.claude-plugin/plugin.json"
    echo '# core' > "$MANGOLOVE_DIR/methodology/core.md"
    cd "$TEST_DIR"
    run env PATH="$TEST_DIR/fakebin:$PATH" bash "$MANGOLOVE_DIR/bin/mangolove" doctor
    [[ "$output" == *"cc-plugin: 검증 실패"* ]]
    [[ "$output" == *"name is required"* ]]
}

@test "doctor: cc-plugin 검증이 통과하면 valid 로 보고한다" {
    _fake_claude_bin 2.1.293 0
    mkdir -p "$MANGOLOVE_DIR/cc-plugin/.claude-plugin" "$MANGOLOVE_DIR/methodology"
    echo '{}' > "$MANGOLOVE_DIR/cc-plugin/.claude-plugin/plugin.json"
    echo '# core' > "$MANGOLOVE_DIR/methodology/core.md"
    cd "$TEST_DIR"
    run env PATH="$TEST_DIR/fakebin:$PATH" bash "$MANGOLOVE_DIR/bin/mangolove" doctor
    [[ "$output" == *"cc-plugin: valid"* ]]
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
