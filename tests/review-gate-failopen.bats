#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove: Review gate: fail-open 과 차단 사유 분류
# 게이트의 목적과 회귀 대상 행동은 tests/review-gate.bats 머리말에 있다.
# ─────────────────────────────────────────────

load test_helper
load review_gate_helper

# ── 코드 리뷰가 실증한 fail-open 들 (전부 조용한 통과였다) ─────

@test "범위: 인용부호로 감싼 경로도 그 경로만 커버한다" {
    # args 는 JSON 이스케이프되어 도착하고(\" ), 되돌려도 셸 인용부호가 토큰에 붙어 있다.
    # 둘 다 처리하지 않으면 토큰이 실제 파일명과 달라 경로 지정이 통째로 무시된다.
    printf 'const a = await axios.get("https://api.example.com/a")\n' > "$REPO_DIR/a b.js"
    printf 'const o = await axios.get("https://api.example.com/o")\n' > "$REPO_DIR/other.js"
    _run_all_reviews 'high \"a b.js\"'
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm quoted
    _gate "git push"
    [ "$status" -eq 2 ]
    grep -q "	a b.js\$"  "$REPO_DIR/.git/mangolove/.review-covered"
    ! grep -q "	other.js\$" "$REPO_DIR/.git/mangolove/.review-covered"
}

@test "범위: JSON 이스케이프된 개행으로 나열한 경로들을 인식한다" {
    printf 'const a = await axios.get("https://api.example.com/a")\n' > "$REPO_DIR/a.js"
    printf 'const b = await axios.get("https://api.example.com/b")\n' > "$REPO_DIR/b.js"
    printf 'const c = await axios.get("https://api.example.com/c")\n' > "$REPO_DIR/c.js"
    _run_all_reviews 'a.js\nb.js'
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm nl
    _gate "git push"
    [ "$status" -eq 2 ]
    ! grep -q "	c.js\$" "$REPO_DIR/.git/mangolove/.review-covered"
}

@test "범위: 스킴 없는 PR 링크도 원격 참조로 본다" {
    _commit_external_api
    _run_all_reviews 'github.com/onda/repo/pull/710'
    _gate "git push"
    [ "$status" -eq 2 ]
}

@test "범위: PR 번호가 낱말과 흩어져 있어도 원격 참조로 본다" {
    # 실측한 실제 호출의 다수가 이 모양이다: "tportio/crs PR #1891".
    _commit_external_api
    _run_all_reviews 'tportio/crs PR #1891'
    _gate "git push"
    [ "$status" -eq 2 ]
    SESSION=s2
    _run_all_reviews 'PR #423 (crs-admin-web)'
    _gate "git push"
    [ "$status" -eq 2 ]
}

@test "범위: 후행 슬래시 디렉토리도 그 아래를 커버한다 (git pathspec)" {
    mkdir -p "$REPO_DIR/lib"
    printf 'const a = await axios.get("https://api.example.com/a")\n' > "$REPO_DIR/lib/a.js"
    _run_all_reviews 'high lib/'
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm dir
    _gate "git push"
    [ "$status" -eq 0 ]
}

@test "범위: 레포 안 절대경로는 경로로, 레포 밖 절대경로는 미커버로 본다" {
    printf 'const a = await axios.get("https://api.example.com/a")\n' > "$REPO_DIR/a.js"
    _run_all_reviews "high $REPO_DIR/a.js"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm abs
    _gate "git push"
    [ "$status" -eq 0 ]
}

@test "범위: 실재하는 pull 경로는 PR 링크로 오인하지 않는다" {
    mkdir -p "$REPO_DIR/docs/pull"
    printf 'const a = await axios.get("https://api.example.com/a")\n' > "$REPO_DIR/docs/pull/710"
    _run_all_reviews "high docs/pull/710"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm realpath
    _gate "git push"
    [ "$status" -eq 0 ]
}

@test "범위: # 없이 'PR 1891' 로 써도 원격 참조로 본다" {
    # #번호 규칙과 별개 경로다. 이 테스트가 없으면 낱말+숫자 규칙이 검증되지 않는다
    # (변이 테스트로 확인: 규칙을 지워도 다른 테스트가 아무도 실패하지 않았다).
    _commit_external_api
    _run_all_reviews 'tportio/crs PR 1891'
    _gate "git push"
    [ "$status" -eq 2 ]
}

# ── 보안 리뷰가 실증한 우회 (둘 다 조용한 과대 인정이었다) ─────

@test "보안: 이름이 겹치는 로컬 경로가 원격 참조를 가리지 않는다" {
    # 공격자가 브랜치에 1952/ 디렉토리를 심어 두면, /code-review 1952(원격 PR 리뷰)가
    # 그 디렉토리를 봤다고 기록됐다. 원격 참조 판정을 경로 검사보다 먼저 한다.
    mkdir -p "$REPO_DIR/1952"
    echo decoy > "$REPO_DIR/1952/decoy.js"
    printf 'const a = await axios.get("https://api.example.com/a")\n' > "$REPO_DIR/real.js"
    _run_all_reviews "1952"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm decoy
    _gate "git push"
    [ "$status" -eq 2 ]
    [ ! -s "$REPO_DIR/.git/mangolove/.review-covered" ] || \
        ! grep -q "1952/decoy.js" "$REPO_DIR/.git/mangolove/.review-covered"
}

@test "보안: 브랜치 이름과 같은 디렉토리가 있어도 브랜치 리뷰로 본다" {
    _make_sibling feature-x
    mkdir -p "$REPO_DIR/feature-x"
    echo decoy > "$REPO_DIR/feature-x/decoy.js"
    printf 'const a = await axios.get("https://api.example.com/a")\n' > "$REPO_DIR/real.js"
    _run_all_reviews "feature-x"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm branchname
    _gate "git push"
    [ "$status" -eq 2 ]
    # 차단만으로는 부족하다(real.js 때문에 어차피 막힌다). decoy 가 covered 면 안 된다.
    [ ! -s "$REPO_DIR/.git/mangolove/.review-covered" ] || \
        ! grep -q "feature-x/decoy.js" "$REPO_DIR/.git/mangolove/.review-covered"
}

@test "보안: __all__ 이라는 이름의 파일이 sentinel 과 충돌하지 않는다" {
    # 문자열 하나로 전체/없음/경로목록을 다 실어 보내면 도메인이 겹친다. paths 가
    # "__all__\n" 이 되면 명령치환이 개행을 떼어 SCOPE_ALL 과 바이트가 같아지고,
    # 그 한 파일만 인정하려던 호출이 **범위 전체**를 인정했다.
    echo x > "$REPO_DIR/__all__"
    printf 'const o = await axios.get("https://api.example.com/o")\n' > "$REPO_DIR/other.js"
    _run_all_reviews "__all__"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm sentinel
    _gate "git push"
    [ "$status" -eq 2 ]
    grep -q "	__all__\$"  "$REPO_DIR/.git/mangolove/.review-covered"
    ! grep -q "	other.js\$" "$REPO_DIR/.git/mangolove/.review-covered"
}

# ── 차단 사유 분류 (효능 측정의 근거) ──────────────────────────
#
# 셋이 한 버킷이면 "커버리지 판정이 너무 엄격한가"를 그 수치로 답할 수 없다.
# 가장 흔한 stale 이 scope 를 덮어써 엄격해 보이게 만든다.

@test "사유: 스킬이 아예 안 돌았으면 missing 으로 기록한다" {
    _commit_external_api
    _gate "git push"
    [ "$status" -eq 2 ]
    [ "$(_block_kinds)" = '"kind":"missing"' ]
}

@test "사유: 돌았지만 딴 데를 리뷰했으면 scope 로 기록한다" {
    _commit_external_api
    _run_all_reviews "1952"
    _gate "git push"
    [ "$status" -eq 2 ]
    [ "$(_block_kinds)" = '"kind":"scope"' ]
}

@test "사유: 보고 나서 더 쓴 것이면 stale 로 기록한다 (scope 와 섞이면 안 된다)" {
    printf 'const a = await axios.get("https://api.example.com/a")\n' > "$REPO_DIR/a.js"
    _run_all_reviews
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm reviewed
    # 리뷰 뒤에 새로 쓴 코드
    local i
    for i in $(seq 1 11); do
        echo "export const V$i = $i" > "$REPO_DIR/n$i.js"
    done
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm more
    _gate "git push"
    [ "$status" -eq 2 ]
    [ "$(_block_kinds)" = '"kind":"stale"' ]
}

@test "플래그: 대상을 담은 옵션은 모르는 토큰으로 본다" {
    # --* 를 전부 건너뛰면 --pr=1952 가 유일하게 판정을 빠져나가 전체를 커버했다.
    _commit_external_api
    _run_all_reviews "--pr=1952"
    _gate "git push"
    [ "$status" -eq 2 ]
}

@test "플래그: 범위와 무관한 알려진 플래그는 기본 범위를 유지한다" {
    _commit_external_api
    _run_all_reviews "high --fix"
    _gate "git push"
    [ "$status" -eq 0 ]
}

# ── 미커버 표시의 수명 (측정의 정확도) ────────────────────────

@test "사유: 딴 데를 본 뒤 제대로 리뷰하면 표시가 걷힌다 (고착 금지)" {
    # 표시가 남으면 그 스킬은 영영 "딴 데를 봤다"로 분류되어, 정작 가장 흔한 사유
    # (보고 나서 더 씀)가 통계에서 사라진다. grep -v 는 출력이 비면 exit 1 이라
    # 종료코드로 분기하면 마지막 한 줄이 안 지워진다.
    _commit_external_api
    _run_all_reviews "1952"
    [ -s "$REPO_DIR/.git/mangolove/.review-noscope" ]
    _run_all_reviews "high"
    [ ! -s "$REPO_DIR/.git/mangolove/.review-noscope" ]
    # 그 뒤 델타를 얹으면 scope 가 아니라 stale 로 기록돼야 한다
    local i
    for i in $(seq 1 11); do echo "export const V$i = $i" > "$REPO_DIR/n$i.js"; done
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm more
    _gate "git push"
    [ "$status" -eq 2 ]
    [ "$(_block_kinds)" = '"kind":"stale"' ]
}

@test "미커버 표시는 커버리지 파일이 아니라 전용 파일에 쓴다" {
    # 커버리지 파일의 스키마는 "무엇을 실제로 봤나"다. 진단 비트를 얹지 않는다.
    _commit_external_api
    _run_all_reviews "1952"
    grep -qx 'simplify' "$REPO_DIR/.git/mangolove/.review-noscope"
    [ ! -f "$REPO_DIR/.git/mangolove/.review-covered" ] || \
        ! grep -q '_noscope' "$REPO_DIR/.git/mangolove/.review-covered"
}

@test "우회: Write 로 만든 마커도 근거와 함께 인정한다 (권한 없이 되는 경로)" {
    # 권한 허용은 세션 시작 시 고정이라 실행 중인 세션에는 적용되지 않는다.
    # 파일을 쓰는 것은 권한이 필요 없으므로 그 경로가 항상 열려 있어야 한다.
    _commit_external_api
    mkdir -p "$REPO_DIR/.mangolove"
    printf '리뷰 3종 실행, 델타는 테스트 파일뿐\n' > "$REPO_DIR/.mangolove/.review-skip"
    _gate "git push"
    [ "$status" -eq 0 ]
    [[ "$output" == *"근거: 리뷰 3종"* ]]
    [ ! -f "$REPO_DIR/.mangolove/.review-skip" ]
}

@test "우회: MANGOLOVE_SKIP_REVIEW=1 도 효능 원장에 남는다 (감사됨이라 적혀 있다)" {
    # 셋 중 이것만 기록되지 않아, 게이트를 껐다는 사실이 측정에서 사라졌다.
    _commit_external_api
    run bash -c "printf '%s' '$(_json_cmd "git push")' | MANGOLOVE_SKIP_REVIEW=1 bash '$GATE' pretooluse"
    [ "$status" -eq 0 ]
    grep -q '"type":"skip","phase":"review","kind":"env"' "$MANGOLOVE_DIR/efficacy/proj.jsonl"
}
