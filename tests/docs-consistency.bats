#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove — Docs <-> Methodology Consistency
# 방법론의 단일 출처(strict.md)와 대외 문서/버전이 어긋나지 않게 강제한다.
# (이 테스트가 RED면 드리프트가 발생했다는 뜻이다.)
# ─────────────────────────────────────────────

setup() {
    REPO="$BATS_TEST_DIRNAME/.."
}

@test "docs: README has no stale fixed-phase workflow claims (methodology is 4-track)" {
    # 방법론은 이미 Change Impact Score 기반 4트랙으로 이동했다.
    # "5-phase"/"4-phase"/"5단계 품질 워크플로우"는 옛 모델의 드리프트 잔재다.
    ! grep -qi "5-phase" "$REPO/README.md"
    ! grep -qi "4-phase" "$REPO/README.md"
    ! grep -q "5단계 품질 워크플로우" "$REPO/README.md"
}

@test "methodology: strict.md defines all four tracks (single source of truth)" {
    for track in Trivial Small Medium Large; do
        grep -q "$track" "$REPO/methodology/strict.md"
    done
}

@test "version: bin/mangolove MANGOLOVE_VERSION matches .version" {
    local file_ver bin_ver
    file_ver=$(tr -d '[:space:]' < "$REPO/.version")
    bin_ver=$(grep -E '^MANGOLOVE_VERSION=' "$REPO/bin/mangolove" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
    [ -n "$file_ver" ]
    [ "$file_ver" = "$bin_ver" ]
}

@test "version: README footer version matches .version" {
    local file_ver
    file_ver=$(tr -d '[:space:]' < "$REPO/.version")
    grep -q "v${file_ver}" "$REPO/README.md"
}
