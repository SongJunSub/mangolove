#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove: Docs <-> Methodology Consistency
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
    # 3인 리뷰는 Large 트랙 전용: '자동으로 ... 3인 병렬 리뷰' 무조건 흐름 표현은 드리프트다.
    ! grep -qE 'automatically follows.*3-agent parallel review' "$REPO/README.md"
    ! grep -qE '자동으로.*3인 병렬 리뷰' "$REPO/README.md"
    # 옛 고정 5-Phase 리뷰 루프 헤더의 재발 방지 (방법론은 4-track)
    ! grep -qE '^### (Phase|[0-9]단계)' "$REPO/README.md"
}

@test "docs: README documents the current model (tracks, find->verify, gates, ops, claude-vs-mangolove)" {
    local r="$REPO/README.md"
    # 4 트랙이 문서화돼 있다
    local t
    for t in Trivial Small Medium Large; do grep -q "$t" "$r" || { echo "missing track: $t"; false; }; done
    # 리뷰 탈상관/검증
    grep -q 'find → verify' "$r"
    # 결정적 게이트 + 측정 ops 명령
    grep -q 'PreToolUse' "$r"
    grep -q 'mangolove efficacy' "$r"
    grep -q 'mangolove eval' "$r"
    grep -q 'mangolove ab' "$r"
    grep -q 'mangolove audit-methodology' "$r"
    grep -q 'Change-Track' "$r"
    # claude vs mangolove 차이가 문서화돼 있다(정직한 경계 포함)
    grep -q '정직한 경계' "$r"
    grep -qE 'claude.* vs .*mangolove' "$r"
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

@test "methodology: multi-agent review mandates an adversarial find->verify stage (decorrelation)" {
    # Phase 3: 리뷰 탈상관: 3인 페르소나(도메인 분리)만으로는 같은 맹점을 공유하므로
    # (a) 발견을 반증으로 검증하는 단계와 (b) 방법(method) 탈상관을 방법론이 강제해야 한다.
    # 이 가드가 RED면 리뷰 규율이 '찾기만 하고 검증 안 함'으로 후퇴했다는 뜻이다.
    grep -qE 'find → verify|찾기 → 검증|적대적 검증' "$REPO/methodology/strict.md"
    grep -q '반증' "$REPO/methodology/strict.md"
    grep -qE '방법\(method\) 탈상관' "$REPO/methodology/strict.md"
    # review.md 모드도 동일 규율로 정렬돼 있어야 한다
    grep -qE 'find → verify|찾기 → 검증' "$REPO/prompts/modes/review.md"
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

@test "methodology: 트랙별 필수 리뷰 표가 strict.md 에 단일 출처로 존재한다" {
    # F2 회귀: 트랙별 리뷰 요구가 system-prompt 와 strict.md 두 곳에서 다르게 정의되면
    # 모델은 둘 중 아무거나 인용하고("Medium 인데 3인 리뷰 대상") 그 다음 생략한다.
    grep -q '### 트랙별 필수 리뷰 (단일 출처)' "$REPO/methodology/strict.md"
    grep -qE '^\| Medium \| `simplify`, `code-review` \|$' "$REPO/methodology/strict.md"
    grep -qE '^\| Large \| `simplify`, `code-review`, `security-review` \|$' "$REPO/methodology/strict.md"
}

@test "methodology: 실존하지 않는 스킬(/plan, /review)을 필수로 지정하지 않는다" {
    # F1 회귀: 실행 불가능한 의무는 "돌리지 않았습니다" 보고로 귀결된다.
    # 실존 이름은 simplify / code-review / security-review 이고, 계획은 EnterPlanMode 도구다.
    local sp="$REPO/prompts/system-prompt.md"
    ! grep -qE 'Skill\("plan"\)|Skill\("review"\)' "$sp"
    ! grep -qE '^\| *[0-9]?단계?:? *분석 *\| *`/plan`' "$sp"
    grep -q 'EnterPlanMode' "$sp"
    grep -q 'Skill("code-review")' "$sp"
}

@test "methodology: 생략 후 사후 보고 금지 규칙이 strict.md 에 있다" {
    # F4 회귀: "생략하고 → 완료 보고하고 → 그 안에서 고백하며 → 돌릴까요" 를 금지하는 규칙.
    grep -q '### 생략을 사후에 보고하지 않는다' "$REPO/methodology/strict.md"
    grep -q '필요하시면 지금 돌리겠습니다' "$REPO/methodology/strict.md"
}

@test "methodology: 트랙 판정을 mangolove impact 로 확정하도록 배선돼 있다" {
    # F3 회귀: 결정적 계산기가 있는데 모델이 표를 보고 암산하면 과대 판정이 나온다.
    grep -q '트랙 판정은 암산이 아니라' "$REPO/methodology/strict.md"
    grep -q 'mangolove impact' "$REPO/methodology/strict.md"
}

@test "boundary: strict.md 의 필수 리뷰 표와 review-gate.sh 의 코드가 일치한다" {
    # 경계면 교차검증: 산문(표)과 게이트(코드)가 어긋나면 모델은 표를 따르고
    # 게이트는 코드를 따라 서로 다른 것을 요구한다. 양쪽을 같이 읽어 대조한다.
    local gate="$REPO/lib/review-gate.sh" md="$REPO/methodology/strict.md"
    local doc_medium doc_large code_medium code_large
    doc_medium="$(grep -E '^\| Medium \|' "$md" | sed -E 's/^\| Medium \| //; s/ \|$//; s/`//g; s/, / /g')"
    doc_large="$(grep -E '^\| Large \|' "$md" | sed -E 's/^\| Large \| //; s/ \|$//; s/`//g; s/, / /g')"
    code_medium="$(bash "$gate" required Medium false false false)"
    code_large="$(bash "$gate" required Large false false false)"
    [ "$doc_medium" = "$code_medium" ] || { echo "Medium 불일치: doc=[$doc_medium] code=[$code_medium]"; false; }
    [ "$doc_large" = "$code_large" ] || { echo "Large 불일치: doc=[$doc_large] code=[$code_large]"; false; }
}
