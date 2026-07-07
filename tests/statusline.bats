#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove — status line 렌더 + 세션 설정 주입 테스트
# ─────────────────────────────────────────────

setup() {
    REPO="$BATS_TEST_DIRNAME/.."
    SL="$REPO/lib/statusline.sh"
}

@test "statusline: renders model, context %, cost, project" {
    json='{"model":{"display_name":"Opus"},"context_window":{"used_percentage":42.3},"cost":{"total_cost_usd":0.1234},"workspace":{"current_dir":"/x/myproj"}}'
    run bash -c "printf '%s' '$json' | '$SL'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Opus"* ]]
    [[ "$output" == *"42%"* ]]
    [[ "$output" == *'$0.12'* ]]
    [[ "$output" == *"myproj"* ]]
}

@test "statusline: null context → 'ctx —', zero cost hidden" {
    json='{"model":{"display_name":"Opus"},"context_window":{"used_percentage":null},"cost":{"total_cost_usd":0}}'
    run bash -c "printf '%s' '$json' | '$SL'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ctx"* ]]
    [[ "$output" != *'$0.00'* ]]
}

@test "statusline: invalid JSON → graceful fallback" {
    run bash -c "printf 'not json' | '$SL'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"MangoLove"* ]]
}

@test "statusline: methodology mode shown from env" {
    json='{"model":{"display_name":"Opus"}}'
    run bash -c "printf '%s' '$json' | MANGOLOVE_STATUSLINE_MODE=split MANGOLOVE_STATUSLINE_DOD=on '$SL'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"split"* ]]
    [[ "$output" == *"dod"* ]]
}

@test "statusline: session-settings includes statusLine when on, omits when off, both valid JSON" {
    run bash -c '
      set +e
      MANGOLOVE_DIR="'"$REPO"'"
      source "$MANGOLOVE_DIR/bin/mangolove" 2>/dev/null
      on="$(mktemp)"; off="$(mktemp)"
      MANGOLOVE_STATUSLINE=on  generate_session_settings "$on"
      MANGOLOVE_STATUSLINE=off generate_session_settings "$off"
      python3 -c "import json; print(\"statusLine\" in json.load(open(\"$on\")))"
      python3 -c "import json; print(\"statusLine\" in json.load(open(\"$off\")))"
      rm -f "$on" "$off"
    '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "True" ]
    [ "${lines[1]}" = "False" ]
}
