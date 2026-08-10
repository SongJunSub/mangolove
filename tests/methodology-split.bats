#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove — Methodology split (core.md + cc-plugin) integrity
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
    # 추출 범위는 생성기에서 파싱한다 — 여기에 다시 적으면 두 번째 진실 출처가 되어
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
    # 줄번호가 아니라 내용으로 검증한다 — strict.md 가 길어져도 이 단언은 유효하다.
    [ "$(printf '%s' "$missing" | wc -w)" -eq 2 ]
    local l content
    for l in $missing; do
        content="$(sed -n "${l}p" "$REPO/methodology/strict.md")"
        [ "$content" = '## Large Track 워크플로우' ] || [ -z "$content" ]
    done
}

@test "split: safety-critical procedures stay resident in core.md (not on-demand skills)" {
    grep -q '## 되돌리기 어려운 작업 — Dry-run 게이트' "$REPO/methodology/core.md"
    grep -q '## 메모리 루프 — 검증 게이트' "$REPO/methodology/core.md"
    grep -q '## 경계면 교차검증' "$REPO/methodology/core.md"
    # 트랙 판정·승인 게이트도 코어에 남아야 한다
    grep -qE '\| 합산 점수 \| 규모 \| 트랙 \|' "$REPO/methodology/core.md"
    grep -q '## 사용자 승인 원칙' "$REPO/methodology/core.md"
    # 온디맨드 스킬 라우팅 표
    grep -q '트랙 워크플로우 상세 — 온디맨드 스킬' "$REPO/methodology/core.md"
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
