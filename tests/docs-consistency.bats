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
    # 3인 리뷰는 Large 트랙 전용 — '자동으로 ... 3인 병렬 리뷰' 무조건 흐름 표현은 드리프트다.
    ! grep -qE 'automatically follows.*3-agent parallel review' "$REPO/README.md"
    ! grep -qE '자동으로.*3인 병렬 리뷰' "$REPO/README.md"
}

@test "methodology: strict.md defines all four tracks (single source of truth)" {
    # 단어 출현이 아니라 트랙 정의 블록(워크플로우 헤더)과 점수 매핑 표의 존재를 강제한다.
    for track in Trivial Small Medium Large; do
        grep -qE "^#+ +${track} Track" "$REPO/methodology/strict.md"
    done
    grep -qE '\| 합산 점수 \| 규모 \| 트랙 \|' "$REPO/methodology/strict.md"
}

@test "version: bin/mangolove MANGOLOVE_VERSION matches .version" {
    local file_ver bin_ver
    file_ver=$(tr -d '[:space:]' < "$REPO/.version")
    bin_ver=$(grep -E '^MANGOLOVE_VERSION=' "$REPO/bin/mangolove" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
    [ -n "$file_ver" ]
    [ "$file_ver" = "$bin_ver" ]
}

@test "version: README footer version matches .version" {
    local file_ver esc
    file_ver=$(tr -d '[:space:]' < "$REPO/.version")
    [ -n "$file_ver" ]
    esc=$(printf '%s' "$file_ver" | sed 's/[.]/\\./g')
    grep -qE "^\*\*MangoLove\*\* v${esc}\$" "$REPO/README.md"
}

@test "repo: all lib/*.sh are executable in git (runtime chmod must not block mangolove update)" {
    # mangolove 는 세션 시작/설치 시 lib/*.sh 를 chmod +x 한다. git 에 100644 로 커밋된 스크립트가
    # 있으면 그 mode 차이가 다음 'mangolove update' 의 git pull 을 막는다. 전부 100755 여야 한다.
    local f mode bad=""
    while IFS= read -r f; do
        mode="$(git -C "$REPO" ls-files -s -- "$f" | awk '{print $1}')"
        [ "$mode" = "100755" ] || bad="$bad $f($mode)"
    done < <(git -C "$REPO" ls-files -- 'lib/*.sh')
    [ -z "$bad" ] || { echo "non-executable in git:$bad"; false; }
}
