#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove — A/B Harness (Phase 4 v2 skeleton)
# 환경 수준 게이트 보호(실측)·결과 채점 엔진(자체검증)·정직 라벨·teeth 를 검증한다.
# ─────────────────────────────────────────────

load test_helper

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

AB() { echo "$MANGOLOVE_DIR/lib/ab-harness.sh"; }

@test "ab: gate protection blocks all dangerous steps in treatment, none in control" {
    run bash "$(AB)" gate
    [ "$status" -eq 0 ]
    # 처치군은 위험 스텝을 전부 차단(5/5), 대조군은 0
    [[ "$output" == *"처치군 5/5"* ]]
    [[ "$output" == *"대조군 0/5"* ]]
}

@test "ab: scoring engine distinguishes good vs bad results (self-test)" {
    run bash "$(AB)" engine
    [ "$status" -eq 0 ]
    [[ "$output" == *"good[build:1 track:1]"* ]]
    [[ "$output" == *"bad[build:0 track:0]"* ]]
}

@test "ab: report shows the gate-protection delta with honest (non-overclaiming) framing" {
    run bash "$(AB)" report
    [ "$status" -eq 0 ]
    [[ "$output" == *"환경 차이 — 안전망"* ]]
    [[ "$output" == *"대표 위험 카테고리 5/5 차단"* ]]
    # 과장 금지: '새 측정 아님' + demo arm 명시
    [[ "$output" == *"새 측정 아님"* ]]
    [[ "$output" == *"실제 모델 출력 아님"* ]]
}

@test "ab: report honestly states no live-model numbers without wired arms" {
    run bash "$(AB)" report
    [[ "$output" == *"live arm 미연결"* ]]
    [[ "$output" == *"실모델 A/B 수치 없음"* ]]
}

# ── teeth: 안전망이 무너지면 하니스가 잡는가 ──

@test "ab: a broken guard collapses the protection delta and is caught (exit 1)" {
    # 가드를 항상-통과 스텁으로 → 처치군이 위험 스텝을 못 막음 → 안전망 붕괴 감지
    printf '#!/usr/bin/env bash\nexit 0\n' > "$MANGOLOVE_DIR/lib/irreversible-guard.sh"
    run bash "$(AB)" gate
    [ "$status" -eq 1 ]
    [[ "$output" == *"처치군 미차단"* ]]
}

@test "ab: mangolove ab dispatches to the harness" {
    cp "$BATS_TEST_DIRNAME/../bin/mangolove" "$MANGOLOVE_DIR/bin/mangolove"
    chmod +x "$MANGOLOVE_DIR/bin/mangolove"
    run bash "$MANGOLOVE_DIR/bin/mangolove" ab
    [ "$status" -eq 0 ]
    [[ "$output" == *"A/B 하니스"* ]]
}
