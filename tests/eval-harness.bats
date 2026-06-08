#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove — Deterministic Self-Eval Harness (Phase 4 / v1)
# 결정적 부품(impact-score 보정도, 비가역 가드 정밀도/재현율)을 라벨 픽스처로 측정하고,
# 하니스가 회귀를 실제로 잡는지(teeth)까지 검증한다.
# ─────────────────────────────────────────────

load test_helper

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

EVAL() { echo "$MANGOLOVE_DIR/lib/eval-harness.sh"; }

@test "eval: report runs green on the shipped deterministic components" {
    run bash "$(EVAL)" report
    [ "$status" -eq 0 ]
    [[ "$output" == *"트랙 보정도"* ]]
    [[ "$output" == *"정밀도"* ]]
    [[ "$output" == *"재현율"* ]]
    [[ "$output" == *"회귀 없음"* ]]
}

@test "eval: impact calibration matches all spec fixtures" {
    run bash "$(EVAL)" impact
    [ "$status" -eq 0 ]
    [[ "$output" == *"적합 8/8"* ]]
}

@test "eval: guard precision/recall is perfect on the labeled suite" {
    run bash "$(EVAL)" guard
    [ "$status" -eq 0 ]
    [[ "$output" == *"FP 0"* ]]
    [[ "$output" == *"FN 0"* ]]
}

@test "eval: report honestly surfaces a known coverage gap (not hidden)" {
    run bash "$(EVAL)" report
    [[ "$output" == *"known-gap"* ]]
}

# ── 하니스가 회귀를 실제로 잡는가 (teeth) — 항상 초록인 eval 은 허영 ──

@test "eval: a broken guard is caught as a regression (exit 1, FN reported)" {
    # 가드를 항상-통과 스텁으로 교체 → 막아야 할 명령이 통과 → FN → 회귀 감지
    printf '#!/usr/bin/env bash\nexit 0\n' > "$MANGOLOVE_DIR/lib/irreversible-guard.sh"
    run bash "$(EVAL)" guard
    [ "$status" -eq 1 ]
    [[ "$output" == *"FN"* ]]
}

@test "eval: a broken impact-score is caught as a regression (exit 1, MISS reported)" {
    # impact-score 를 항상 Trivial 로 → db/auth/ext 픽스처 불일치 → MISS → 회귀
    printf '#!/usr/bin/env bash\necho %s\n' "'{\"track_floor\":\"Trivial\"}'" > "$MANGOLOVE_DIR/lib/impact-score.sh"
    run bash "$(EVAL)" impact
    [ "$status" -eq 1 ]
    [[ "$output" == *"MISS"* ]]
}

@test "eval: an impact-score emitting non-track output is flagged 측정실패 (no silent inflation)" {
    # impact-score 가 트랙이 아닌 출력/오류를 내면 — 가짜 일치나 분모 축소가 아니라 '측정실패'로 회귀 처리
    printf '#!/usr/bin/env bash\necho "Error: boom" >&2\nexit 1\n' > "$MANGOLOVE_DIR/lib/impact-score.sh"
    run bash "$(EVAL)" impact
    [ "$status" -eq 1 ]
    [[ "$output" == *"측정실패"* ]]
}

@test "eval: a guard that over-blocks is caught as a regression (FP reported)" {
    # 가드를 항상-차단 스텁으로 교체 → 통과해야 할 명령을 막음 → FP → 회귀
    printf '#!/usr/bin/env bash\nexit 2\n' > "$MANGOLOVE_DIR/lib/irreversible-guard.sh"
    run bash "$(EVAL)" guard
    [ "$status" -eq 1 ]
    [[ "$output" == *"FP"* ]]
}

@test "eval: mangolove eval dispatches to the harness" {
    cp "$BATS_TEST_DIRNAME/../bin/mangolove" "$MANGOLOVE_DIR/bin/mangolove"
    chmod +x "$MANGOLOVE_DIR/bin/mangolove"
    run bash "$MANGOLOVE_DIR/bin/mangolove" eval
    [ "$status" -eq 0 ]
    [[ "$output" == *"자가평가"* ]]
}
