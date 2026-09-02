#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove: Methodology Audit
# 감사 수치가 결정적으로(=합성 점수 없이) 산출되고, 읽기 전용이며,
# git, 원장이 없어도 죽지 않는지 검증한다.
# ─────────────────────────────────────────────

load test_helper

setup() {
    setup_test_env
    AUD="$MANGOLOVE_DIR/lib/audit-methodology.sh"
    FIX="$TEST_DIR/fixture.md"
    # 펜스 안의 "## ..." 는 Spec/.progress.md 템플릿 예시: 섹션으로 세면 안 된다.
    cat > "$FIX" <<'EOF'
# 제목
머리말 한 줄

## 알파
반드시 지킬 것
금지 사항

## 베타
```
## 펜스 안 가짜 섹션
반드시 절대
```
끝
EOF
}

teardown() {
    teardown_test_env
}

@test "audit: 섹션 줄수 합이 파일 총 줄수와 같다 (누락 없음)" {
    local total; total="$(wc -l < "$FIX" | tr -d ' ')"
    run env MANGOLOVE_METHODOLOGY_SRC="$FIX" bash "$AUD" report
    [ "$status" -eq 0 ]
    # 합계 행의 첫 숫자가 총 줄수와 일치
    local sum
    sum="$(printf '%s\n' "$output" | awk '/합계/{print $1}')"
    [ "$sum" = "$total" ]
}

@test "audit: 코드 펜스 안의 '## ' 는 섹션으로 세지 않는다" {
    run env MANGOLOVE_METHODOLOGY_SRC="$FIX" bash "$AUD" report
    [ "$status" -eq 0 ]
    [[ "$output" == *"알파"* ]]
    [[ "$output" == *"베타"* ]]
    [[ "$output" != *"펜스 안 가짜 섹션"* ]]
}

@test "audit: 줄수, 강제표현을 섹션별로 정확히 집계한다" {
    run env MANGOLOVE_METHODOLOGY_SRC="$FIX" bash "$AUD" report
    [ "$status" -eq 0 ]
    # 알파 = 헤딩+2줄+공백 = 4줄, 강제표현 '반드시'+'금지' = 2
    printf '%s\n' "$output" | grep -qE '^[[:space:]]+4[[:space:]]+2[[:space:]]+-[[:space:]]+알파$'
    # 베타 = 헤딩+펜스4줄+끝 = 6줄, 펜스 안 '반드시 절대' 도 밀도에는 포함 = 2
    printf '%s\n' "$output" | grep -qE '^[[:space:]]+6[[:space:]]+2[[:space:]]+-[[:space:]]+베타$'
}

@test "audit: 비-git 환경에서도 exit 0 (최종수정은 '-')" {
    run env MANGOLOVE_METHODOLOGY_SRC="$FIX" bash "$AUD" report
    [ "$status" -eq 0 ]
    [[ "$output" == *"섹션"* ]]
    # TEST_DIR 은 git 레포가 아니므로 blame 이 비고 '-' 로 표기돼야 한다
    printf '%s\n' "$output" | grep -q -- "-   알파"
}

@test "audit: efficacy 원장이 없어도 동작하고 발동 0건을 표기한다" {
    run env MANGOLOVE_METHODOLOGY_SRC="$FIX" bash "$AUD" report
    [ "$status" -eq 0 ]
    [[ "$output" == *"발동 0건"* ]]
}

@test "audit: 게이트 phase 우주를 호출부에서 파생한다 (하드코딩 아님)" {
    run env MANGOLOVE_METHODOLOGY_SRC="$FIX" bash "$AUD" report
    [ "$status" -eq 0 ]
    # lib/*.sh 의 record-block 호출부에 존재하는 phase 가 전부 표에 나와야 한다
    local p
    for p in $(grep -rhoE 'record-(block|skip) [a-z-]+' "$MANGOLOVE_DIR/lib" | awk '{print $2}' | sort -u); do
        [[ "$output" == *"$p"* ]] || { echo "missing phase: $p"; false; }
    done
}

@test "audit: 파생된 phase 가 실제 게이트 이름과 일치한다" {
    # 위 테스트는 기대값을 같은 grep 으로 만들기 때문에 파생이 어긋나도 초록이다.
    # 실제로 효능 호출을 헬퍼로 감싸자 phase 가 'dod-gate' 에서 'fail' 로 바뀌었는데도
    # 통과했다. 그래서 이름을 여기 한 번 고정한다. 게이트를 늘리면 이 줄도 같이 고친다.
    local derived
    derived="$(grep -rhoE 'record-(block|skip) [a-z-]+' "$MANGOLOVE_DIR/lib" \
               | awk '{print $2}' | sort -u | tr '\n' ' ')"
    [ "$derived" = "budget dod-gate gate guard review " ]
}

@test "audit: 원장이 있으면 phase 별 차단 건수를 반영한다" {
    local r="$TEST_DIR/aud-ledger"; mkdir -p "$r"
    git -C "$r" init -q
    cd "$r"
    bash "$MANGOLOVE_DIR/lib/efficacy-recorder.sh" record-block guard "rm -rf /"
    bash "$MANGOLOVE_DIR/lib/efficacy-recorder.sh" record-block guard "git push --force"
    run env MANGOLOVE_METHODOLOGY_SRC="$FIX" bash "$AUD" report
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" | grep -qE '^  guard +2회'
    # '발동 0건' 을 '규칙이 무용' 으로 오독하지 않도록 기록 기간을 함께 낸다
    [[ "$output" == *"기록 기간:"* ]]
    [[ "$output" != *"원장 없음"* ]]
}

@test "audit: 읽기 전용, 어떤 파일도 만들거나 고치지 않는다" {
    local before after fixsum_before fixsum_after
    before="$(find "$TEST_DIR" -type f | sort | md5 2>/dev/null || find "$TEST_DIR" -type f | sort | md5sum)"
    fixsum_before="$(md5 -q "$FIX" 2>/dev/null || md5sum "$FIX" | awk '{print $1}')"
    run env MANGOLOVE_METHODOLOGY_SRC="$FIX" bash "$AUD" report
    [ "$status" -eq 0 ]
    after="$(find "$TEST_DIR" -type f | sort | md5 2>/dev/null || find "$TEST_DIR" -type f | sort | md5sum)"
    fixsum_after="$(md5 -q "$FIX" 2>/dev/null || md5sum "$FIX" | awk '{print $1}')"
    [ "$before" = "$after" ]
    [ "$fixsum_before" = "$fixsum_after" ]
}

@test "audit: 방법론 파일이 없으면 실패로 알린다 (조용히 빈 리포트 금지)" {
    run env MANGOLOVE_METHODOLOGY_SRC="$TEST_DIR/nope.md" bash "$AUD" report
    [ "$status" -eq 1 ]
    [[ "$output" == *"찾을 수 없습니다"* ]]
}

@test "audit: 잘못된 서브커맨드는 usage 로 거절한다" {
    run bash "$AUD" bogus
    [ "$status" -eq 2 ]
    [[ "$output" == *"usage:"* ]]
}

@test "audit: mangolove audit-methodology 가 리포트로 디스패치된다" {
    cp "$BATS_TEST_DIRNAME/../bin/mangolove" "$MANGOLOVE_DIR/bin/mangolove"
    chmod +x "$MANGOLOVE_DIR/bin/mangolove"
    run env MANGOLOVE_METHODOLOGY_SRC="$FIX" bash "$MANGOLOVE_DIR/bin/mangolove" audit-methodology
    [ "$status" -eq 0 ]
    [[ "$output" == *"방법론 감사"* ]]
}

@test "audit: 실제 strict.md 를 감사하면 섹션 합계가 총 줄수와 일치한다" {
    local src="$BATS_TEST_DIRNAME/../methodology/strict.md"
    local total; total="$(wc -l < "$src" | tr -d ' ')"
    run env MANGOLOVE_METHODOLOGY_SRC="$src" bash "$AUD" report
    [ "$status" -eq 0 ]
    local sum; sum="$(printf '%s\n' "$output" | awk '/합계/{print $1}')"
    [ "$sum" = "$total" ]
    [[ "$output" != *"코드 펜스가 홀수개"* ]]
}
