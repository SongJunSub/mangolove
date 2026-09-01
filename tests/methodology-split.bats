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
    # 추출 범위는 생성기에서 파싱한다: 여기에 다시 적으면 두 번째 진실 출처가 되어
    # strict.md 를 고칠 때마다 생성기와 테스트를 손으로 맞춰야 한다(드리프트 원인 자체).
    local ranges
    ranges="$(grep -oE "sed -n '[0-9]+,[0-9]+p'" "$REPO/lib/gen-methodology.sh" \
              | sed -E "s/sed -n '([0-9]+),([0-9]+)p'/\1-\2/" | tr '\n' ' ')"
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

@test "split: safety-critical procedures stay resident in core.md (not on-demand skills)" {
    grep -q '## 되돌리기 어려운 작업: Dry-run 게이트' "$REPO/methodology/core.md"
    grep -q '## 메모리 루프: 검증 게이트' "$REPO/methodology/core.md"
    grep -q '## 경계면 교차검증' "$REPO/methodology/core.md"
    # 트랙 판정·승인 게이트도 코어에 남아야 한다
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
