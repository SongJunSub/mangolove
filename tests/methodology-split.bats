#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove: Methodology split (core.md + cc-plugin) integrity
# core.md/skills 는 strict.md 에서 gen-methodology.sh 로 생성된다. 이 테스트가 RED면
# (a) 손 편집 드리프트, (b) strict.md 변경 후 미재생성, (c) 섹션 누락,
# (d) 안전 절차 이탈, (e) 플러그인 매니페스트/훅 오류 중 하나다.
# ─────────────────────────────────────────────

setup() {
    REPO="$BATS_TEST_DIRNAME/.."
}

@test "split: gen-methodology.sh regen matches committed core.md + skills (no drift)" {
    local tmp; tmp="$(mktemp -d)"
    bash "$REPO/lib/gen-methodology.sh" "$tmp"
    diff -u "$REPO/methodology/core.md" "$tmp/methodology/core.md"
    local s
    for s in mangolove-spec mangolove-large-review mangolove-subagent-worktree mangolove-cicd; do
        diff -u "$REPO/cc-plugin/skills/$s/SKILL.md" "$tmp/cc-plugin/skills/$s/SKILL.md"
    done
    rm -rf "$tmp"
}

@test "split: every strict.md line lands in core or a skill (only moved section header dropped)" {
    local total; total="$(wc -l < "$REPO/methodology/strict.md")"
    [ "$total" -gt 0 ]
    # 추출 범위는 생성기에게 물어본다: 여기에 다시 적으면 두 번째 진실 출처가 되어
    # strict.md 를 고칠 때마다 생성기와 테스트를 손으로 맞춰야 한다(드리프트 원인 자체).
    # 생성기가 헤딩에서 범위를 계산하므로, 소스를 긁는 대신 --print-ranges 를 쓴다.
    local ranges
    ranges="$(bash "$REPO/lib/gen-methodology.sh" --print-ranges | tr '\n' ' ')"
    [ "$(printf '%s' "$ranges" | wc -w)" -eq 7 ]   # core 3구간 + 스킬 4구간
    local missing
    missing="$(awk -v ranges="$ranges" -v total="$total" 'BEGIN{
        n=split(ranges, R, " ");
        for(i=1;i<=n;i++){split(R[i],p,"-"); for(l=p[1];l<=p[2];l++) c[l]=1}
        miss="";
        for(l=1;l<=total;l++) if(!(l in c)) miss=miss (miss==""?"":" ") l;
        print miss
    }')"
    # 합집합이 빠뜨리는 줄은 '이동된 섹션 헤더 + 뒤 공백' 2줄뿐이어야 한다.
    # 줄번호가 아니라 내용으로 검증한다: strict.md 가 길어져도 이 단언은 유효하다.
    [ "$(printf '%s' "$missing" | wc -w)" -eq 2 ]
    local l content
    for l in $missing; do
        content="$(sed -n "${l}p" "$REPO/methodology/strict.md")"
        [ "$content" = '## Large Track 워크플로우' ] || [ -z "$content" ]
    done
}

# ── 범위 유도 방식의 가드레일 ──────────────────────────────────
# 범위를 헤딩에서 계산하도록 바꾸면서 잃을 뻔한 보호를, 변이(mutation)로 고정한다.
# 섹션 '안'의 편집은 수작업 0으로 통과해야 하고, 구조가 바뀌면 큰소리로 실패해야 한다.

# strict.md 를 복제한 미러 저장소를 만들고 그 사본 경로를 출력한다.
_mirror() {
    local m; m="$(mktemp -d)"
    mkdir -p "$m/lib" "$m/methodology"
    cp "$REPO/lib/gen-methodology.sh" "$m/lib/"
    cp "$REPO/methodology/strict.md" "$m/methodology/"
    printf '%s' "$m"
}

@test "gen: 섹션 안에 줄을 추가해도 수작업 없이 재생성된다 (범위 자동 이동)" {
    local m; m="$(_mirror)"
    # 코어 영역 한복판에 한 줄 삽입
    awk '{print} /^## 세션 위생/{print ""; print "- 새 규칙 한 줄."}' \
        "$m/methodology/strict.md" > "$m/s.md" && mv "$m/s.md" "$m/methodology/strict.md"
    run bash "$m/lib/gen-methodology.sh" "$m/out"
    [ "$status" -eq 0 ]
    # 뒤쪽 범위가 삽입한 줄 수만큼 밀렸어야 한다 (하드코딩이면 여기서 깨졌다)
    run bash "$m/lib/gen-methodology.sh" --print-ranges
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | wc -l)" -eq 7 ]
    rm -rf "$m"
}

@test "gen: 경계 헤딩이 바뀌면 큰소리로 실패한다" {
    local m; m="$(_mirror)"
    sed 's/^## 스마트 리뷰 라우팅$/## 스마트 리뷰 라우팅 (개편)/' \
        "$m/methodology/strict.md" > "$m/s.md" && mv "$m/s.md" "$m/methodology/strict.md"
    run bash "$m/lib/gen-methodology.sh" "$m/out"
    [ "$status" -ne 0 ]
    [[ "$output" == *"헤딩"* ]]
    rm -rf "$m"
}

@test "gen: 꼬리에 새 구조 섹션이 생기면 실패한다 (목적지를 사람이 정하게)" {
    local m; m="$(_mirror)"
    printf '\n## 새 섹션\n\n내용\n' >> "$m/methodology/strict.md"
    run bash "$m/lib/gen-methodology.sh" "$m/out"
    [ "$status" -ne 0 ]
    [[ "$output" == *"목적지"* ]]
    rm -rf "$m"
}

@test "gen: 드롭 구간(Large Track 헤더~1단계)에 내용이 끼면 실패한다" {
    local m; m="$(_mirror)"
    awk '{print} /^## Large Track 워크플로우$/{print "삽입된 설명."}' \
        "$m/methodology/strict.md" > "$m/s.md" && mv "$m/s.md" "$m/methodology/strict.md"
    run bash "$m/lib/gen-methodology.sh" "$m/out"
    [ "$status" -ne 0 ]
    rm -rf "$m"
}

@test "gen: 경계 헤딩이 중복되면 실패한다 (범위가 모호해진다)" {
    local m; m="$(_mirror)"
    printf '\n## CI/CD 워크플로우 작업 규칙\n' >> "$m/methodology/strict.md"
    run bash "$m/lib/gen-methodology.sh" "$m/out"
    [ "$status" -ne 0 ]
    rm -rf "$m"
}

@test "split: safety-critical procedures stay resident in core.md (not on-demand skills)" {
    grep -q '## 되돌리기 어려운 작업: Dry-run 게이트' "$REPO/methodology/core.md"
    grep -q '## 메모리 루프: 검증 게이트' "$REPO/methodology/core.md"
    grep -q '## 경계면 교차검증' "$REPO/methodology/core.md"
    # 트랙 판정, 승인 게이트도 코어에 남아야 한다
    grep -qE '\| 합산 점수 \| 규모 \| 트랙 \|' "$REPO/methodology/core.md"
    grep -q '## 사용자 승인 원칙' "$REPO/methodology/core.md"
    # 온디맨드 스킬 라우팅 표
    grep -q '트랙 워크플로우 상세: 온디맨드 스킬' "$REPO/methodology/core.md"
}

@test "split: heavy procedures moved OUT of core into skills" {
    ! grep -q '#### API 변경 (신규/수정) 템플릿' "$REPO/methodology/core.md"
    ! grep -q '### 8단계: 병렬 독립 코드 리뷰' "$REPO/methodology/core.md"
    grep -q '#### API 변경 (신규/수정) 템플릿' "$REPO/cc-plugin/skills/mangolove-spec/SKILL.md"
    grep -q '### 8단계: 병렬 독립 코드 리뷰' "$REPO/cc-plugin/skills/mangolove-large-review/SKILL.md"
}

@test "split: cc-plugin passes claude plugin validate --strict" {
    command -v claude >/dev/null 2>&1 || skip "claude not installed"
    run claude plugin validate --strict "$REPO/cc-plugin"
    [ "$status" -eq 0 ]
}

@test "split: cc-plugin ships zero hooks and no scripts (single execution channel, no git mode-drift)" {
    # 네이티브 플러그인이 훅을 실으면 --settings 로 주입한 게이트와 이중 발화한다.
    run bash -c "find '$REPO/cc-plugin' -name 'hooks.json' | head -1"
    [ -z "$output" ]
    run bash -c "find '$REPO/cc-plugin' -name '*.sh' | head -1"
    [ -z "$output" ]
}

@test "agents: 3인 탈상관 리뷰어 + 검증자가 정의돼 있고 전부 읽기 전용이다" {
    # 리뷰 구성을 매 세션 프롬프트로 지어내면 리뷰 강도가 세션마다 달라진다.
    # 그리고 리뷰어가 Edit/Write 를 가지면 그건 리뷰가 아니라 두 번째 구현이다.
    local a
    for a in mangolove-reviewer-close-read mangolove-reviewer-refute \
             mangolove-reviewer-counterexample mangolove-verifier; do
        local f="$REPO/cc-plugin/agents/$a.md"
        [ -f "$f" ] || { echo "missing agent: $a"; false; }
        grep -qE "^name: $a\$" "$f"
        grep -qE '^description: .+' "$f"
        grep -qE '^tools: Read, Grep, Glob, Bash$' "$f"
        grep -qE '^model: (opus|fable|sonnet|haiku|inherit)$' "$f"
    done
}

@test "methodology: 실존하지 않는 스킬 이름(/review)을 지시로 쓰지 않는다" {
    # F1 회귀의 나머지 절반: 생성되는 스킬 본문에도 /review 지시가 있었다.
    # "그런 스킬은 없다"고 밝히는 부정 언급(없다 포함 줄)은 의도된 것이라 예외로 둔다.
    local hits
    hits="$(grep -rnE '(^|[^a-z-])/review([^a-z-]|$)' \
              "$REPO/methodology/" "$REPO/cc-plugin/skills/" | grep -v '없다' || true)"
    [ -z "$hits" ] || { echo "지시로 쓰인 /review 발견:"; echo "$hits"; false; }
}
