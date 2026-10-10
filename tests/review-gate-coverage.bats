#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove: Review gate: 리뷰가 찾은 우회와 커버리지 범위
# 게이트의 목적과 회귀 대상 행동은 tests/review-gate.bats 머리말에 있다.
# ─────────────────────────────────────────────

load test_helper
load review_gate_helper

# ── 코드/보안 리뷰가 찾은 우회들 (전부 조용한 통과였다) ────────

@test "우회: 비-ASCII 파일명이 게이트를 통과하지 않는다 (core.quotePath)" {
    # git 은 기본값에서 비-ASCII 경로를 "\355\225\234..." 로 C-quote 한다. 그 문자열을
    # pathspec 으로 넘기면 아무 파일도 안 잡혀 잔여 0건 -> Trivial -> 조용히 통과했다.
    printf 'const a = await axios.get("https://api.example.com/a")\n' > "$REPO_DIR/a.js"
    _run_all_reviews
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm reviewed
    # 리뷰가 본 적 없는 한글 파일명 Medium 변경을 얹는다
    printf 'const k = await axios.post("https://api.example.com/k", {})\n' > "$REPO_DIR/한글파일.js"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm korean
    _gate "git push"
    [ "$status" -eq 2 ]
}

@test "우회: dry-run 미끼 뒤에 붙은 진짜 push 를 잡는다" {
    # `git push --dry-run && git push origin main` 은 한 줄이다. push 키워드 뒤를
    # 첫 구분자에서 끊으면 앞의 dry-run 만 보고 뒤의 진짜 push 를 통째로 놓쳤다.
    _commit_external_api
    _gate "git push --dry-run && git push origin main"
    [ "$status" -eq 2 ]
}

@test "우회: 줄바꿈으로 이어진 dry-run + 진짜 push 도 잡는다" {
    _commit_external_api
    _gate 'git push --dry-run\ngit push origin main'
    [ "$status" -eq 2 ]
}

@test "우회: refspec 으로 다른 브랜치를 올리면 그 브랜치를 판정한다" {
    # `git push origin topic:main` 은 현재 브랜치가 아니라 topic 을 올린다.
    # HEAD 를 가정하면 (깨끗한) main 을 보고 통과시켰다.
    git -C "$REPO_DIR" checkout -q -b topic
    printf 'const t = await axios.get("https://api.example.com/t")\n' > "$REPO_DIR/t.js"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm topic
    git -C "$REPO_DIR" checkout -q main    # main 은 origin/main 과 동일 = 범위 비어 있음
    _gate "git push origin topic:main"
    [ "$status" -eq 2 ]
}

@test "게이트 대상 아님: 원격 브랜치 삭제는 내용을 공유하지 않는다" {
    _commit_external_api
    _gate "git push --delete origin oldbranch"
    [ "$status" -eq 0 ]
    _gate "git push -d origin oldbranch"
    [ "$status" -eq 0 ]
}

@test "status: 범위가 아닌 ref 는 거짓 PASS 대신 거부한다" {
    # _range_signature 는 A...B 만 이해한다. sha 를 넘기면 서명이 비어 모든 스킬이
    # 충족으로 보이고 "필수 리뷰: simplify code-review / 판정: PASS" 라는 모순이 났다.
    _commit_external_api
    run bash -c "cd '$REPO_DIR' && bash '$GATE' status HEAD"
    [ "$status" -eq 2 ]
    [[ "$output" == *"범위(A...B)만"* ]]
    run bash -c "cd '$REPO_DIR' && bash '$GATE' status --working"
    [ "$status" -eq 2 ]
}

@test "보안: 상태 파일이 심볼릭 링크면 그리로 쓰지 않는다" {
    # 적대적 브랜치가 .review-covered 를 레포 밖으로 향하는 링크로 커밋해 두면,
    # 리뷰 스킬 한 번으로 그 파일에 공격자가 정한 경로 문자열이 append 된다.
    local target="$TEST_DIR/outside.txt"
    echo "원본" > "$target"
    mkdir -p "$REPO_DIR/.git/mangolove"
    ln -s "$target" "$REPO_DIR/.git/mangolove/.review-covered"
    echo changed > "$REPO_DIR/seed.txt"
    printf '%s' "$(_json_skill simplify)" | bash "$GATE" record
    [ "$(cat "$target")" = "원본" ]
    [ ! -L "$REPO_DIR/.git/mangolove/.review-covered" ]
}

# ── prepush: git 이 주는 ref 목록을 쓴다 ───────────────────────

@test "prepush: git 이 준 ref 로 판정한다 (현재 브랜치를 가정하지 않는다)" {
    _commit_external_api
    local sha; sha=$(git -C "$REPO_DIR" rev-parse HEAD)
    local base; base=$(git -C "$REPO_DIR" rev-parse origin/main)
    run bash -c "cd '$REPO_DIR' && printf 'refs/heads/main %s refs/heads/main %s\n' '$sha' '$base' | bash '$GATE' prepush origin /tmp/fake.git"
    [ "$status" -eq 1 ]
    [[ "$output" == *"push 차단"* ]]
}

@test "prepush: 삭제 ref 는 통과시킨다 (내용을 공유하지 않는다)" {
    _commit_external_api
    local sha; sha=$(git -C "$REPO_DIR" rev-parse HEAD)
    run bash -c "cd '$REPO_DIR' && printf '(delete) 0000000000000000000000000000000000000000 refs/heads/old %s\n' '$sha' | bash '$GATE' prepush origin /tmp/fake.git"
    [ "$status" -eq 0 ]
}

@test "prepush: git 이 불렀는데 올릴 ref 가 없으면 통과한다" {
    # 이미 up-to-date 인 push 다. 공유되는 내용이 없으므로 막을 이유가 없다.
    _commit_external_api
    run bash -c "cd '$REPO_DIR' && bash '$GATE' prepush origin /tmp/fake.git </dev/null"
    [ "$status" -eq 0 ]
}

@test "prepush: 설치된 게이트가 구버전이면 push 를 막지 않는다 (버전 스큐 fail-open)" {
    # 훅은 레포에 커밋돼 함께 배포되고 게이트는 머신마다 따로 설치된다. 설치본이
    # prepush 를 모르면 usage + exit 2 라, 그대로 exec 하면 그 머신의 push 가 전부 막힌다.
    local old="$TEST_DIR/oldinstall"; mkdir -p "$old/lib"
    cat > "$old/lib/review-gate.sh" <<'OLD'
#!/usr/bin/env bash
echo "usage: review-gate.sh {record|pretooluse|required|status}" >&2
exit 2
OLD
    run bash -c "MANGOLOVE_DIR='$old' bash '$BATS_TEST_DIRNAME/../.githooks/pre-push' origin url </dev/null"
    [ "$status" -eq 0 ]
}

# ── 커버리지 범위: 스킬이 실제로 본 것만 인정한다 ──────────────
#
# args 는 도구 호출 사실이라 근거로 쓸 수 있다. 무시하면 `/code-review 1952` 처럼
# **원격 PR 을 본 리뷰**가 이 워킹트리 전체를 통과시킨다(이 트리를 쳐다보지도 않았는데).

@test "범위: PR 번호를 리뷰한 스킬은 이 워킹트리를 커버하지 않는다" {
    _commit_external_api
    _run_all_reviews "1952"
    _gate "git push"
    [ "$status" -eq 2 ]
}

@test "범위: PR URL 을 리뷰한 스킬도 이 워킹트리를 커버하지 않는다" {
    _commit_external_api
    _run_all_reviews "https://github.com/o/r/pull/710"
    _gate "git push"
    [ "$status" -eq 2 ]
}

@test "범위: 레포 밖 경로(다른 worktree)만 리뷰하면 이 트리를 커버하지 않는다" {
    _commit_external_api
    local other="$TEST_DIR/otherworktree"; mkdir -p "$other"
    git -C "$other" init -q -b main
    _run_all_reviews "high $other"
    _gate "git push"
    [ "$status" -eq 2 ]
}

@test "범위: 짚은 경로만 커버한다 (짚지 않은 파일은 여전히 미검토)" {
    printf 'const a = await axios.get("https://api.example.com/a")\n' > "$REPO_DIR/a.js"
    printf 'const b = await axios.get("https://api.example.com/b")\n' > "$REPO_DIR/b.js"
    _run_all_reviews "high a.js"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm two
    _gate "git push"
    [ "$status" -eq 2 ]
    # a.js 는 covered, b.js 는 아니다
    grep -q "	a.js\$" "$REPO_DIR/.git/mangolove/.review-covered"
    ! grep -q "	b.js\$" "$REPO_DIR/.git/mangolove/.review-covered"
}

@test "범위: 짚은 경로를 전부 덮으면 통과한다" {
    printf 'const a = await axios.get("https://api.example.com/a")\n' > "$REPO_DIR/a.js"
    _run_all_reviews "high a.js"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm one
    _gate "git push"
    [ "$status" -eq 0 ]
}

@test "범위: 닫힌 강도 목록 전체가 기본 범위를 커버한다" {
    # 여섯 개 중 둘만 테스트하면 목록이 낡았을 때 알아채지 못한다.
    _commit_external_api
    local lvl
    for lvl in low medium high max xhigh ultra; do
        rm -f "$REPO_DIR/.git/mangolove/.review-ledger" "$REPO_DIR/.git/mangolove/.review-covered"
        _run_all_reviews "$lvl"
        _gate "git push"
        [ "$status" -eq 0 ] || { echo "강도 '$lvl' 에서 실패"; return 1; }
    done
}

@test "범위: 무언가를 가리키는데 이 트리에서 못 찾으면 커버하지 않는다" {
    # 기본값을 ALL 로 두면 열거 밖의 인자 모양마다 조용한 과대 인정이 생긴다.
    # "해석하지 않겠다"는 안전한 쪽으로 두겠다는 뜻이지 최대로 믿겠다는 뜻이 아니다.
    _commit_external_api
    _run_all_reviews "리뷰 200 줄 정도 워킹트리 변경분 봐줘"
    _gate "git push"
    [ "$status" -eq 2 ]
}

@test "범위: 강도뿐인 호출만 기본 범위를 커버한다 (산문은 아니다)" {
    # 모르는 낱말을 수식어로 넘기면 두 가지가 샌다: 부정문의 경로를 긍정으로 읽고,
    # 브랜치 이름(main)을 준 호출이 전체를 커버한다. 닫힌 목록만 인정한다.
    _commit_external_api
    _run_all_reviews "medium"
    _gate "git push"
    [ "$status" -eq 0 ]
}

@test "한계: 부정문 안의 경로는 커버 대상으로 읽힌다 (산문을 해석하지 않는 대가)" {
    # 알려진 한계다. "lib 는 빼고" 를 "lib 를 봤다" 로 읽는다. 산문의 의미를 해석하지 않는
    # 한 못 막는다. 대신 과대 인정은 **짚은 그 경로 하나**로 제한되고 나머지는 미검토로
    # 남는다. 이 테스트는 그 경계가 유지되는지를 고정한다(lib 만 covered, 나머지는 아님).
    mkdir -p "$REPO_DIR/lib"
    printf 'const a = await axios.get("https://api.example.com/a")\n' > "$REPO_DIR/lib/a.js"
    printf 'const o = await axios.get("https://api.example.com/o")\n' > "$REPO_DIR/outside.js"
    _run_all_reviews "review everything except lib"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm neg
    _gate "git push"
    [ "$status" -eq 2 ]                       # lib 밖은 여전히 미검토라 막힌다
    ! grep -q "	outside.js\$" "$REPO_DIR/.git/mangolove/.review-covered"
}

@test "위험: 갈라진 다른 브랜치를 리뷰한 호출이 이 워킹트리를 커버하지 않는다" {
    # /code-review other-feature 는 다른 브랜치를 본다. 이 트리의 기준(HEAD, 현재 브랜치,
    # upstream, 딴 지점, 조상)이 아닌 ref 는 다른 대상 신호다.
    _make_sibling other-feature
    _commit_external_api
    _run_all_reviews "other-feature"
    _gate "git push"
    [ "$status" -eq 2 ]
    # 로컬에 없는 브랜치 이름은 산문 낱말과 형태가 같아 구별되지 않는다(알려진 한계).
}

@test "범위: 비교 기준 ref(upstream, 현재 브랜치)만 적은 산문은 이 트리를 본 것이다" {
    # "origin/main 대비 변경" 의 origin/main 은 비교 기준이지 다른 리뷰 대상이 아니다.
    # 이걸 다른 브랜치 리뷰로 읽으면 가장 흔한 산문이 전부 미커버가 된다.
    _commit_external_api
    _run_all_reviews "origin/main 대비 변경 전체"
    _gate "git push"
    [ "$status" -eq 0 ]
    rm -f "$REPO_DIR/.git/mangolove/.review-ledger" "$REPO_DIR/.git/mangolove/.review-covered"
    _run_all_reviews "main"
    _gate "git push"
    [ "$status" -eq 0 ]
}

@test "범위: PR 낱말과 티켓번호가 섞인 산문도 원격 리뷰로 본다" {
    # 순수숫자도 #번호도 아닌 형태다. PR 낱말 + 숫자를 품은 토큰의 공존으로 잡는다.
    _commit_external_api
    _run_all_reviews "크스-1952 관련 PR 검토해줘"
    _gate "git push"
    [ "$status" -eq 2 ]
}

@test "범위: 실재하지 않는 경로 토큰은 무시하고 실재하는 것만 커버한다" {
    # 오타나 다른 트리의 경로가 섞여도, 실제로 짚은 파일의 커버리지까지 버리지 않는다.
    printf 'const a = await axios.get("https://api.example.com/a")\n' > "$REPO_DIR/a.js"
    printf 'const b = await axios.get("https://api.example.com/b")\n' > "$REPO_DIR/b.js"
    _run_all_reviews "high a.js nosuch.js"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm partial
    _gate "git push"
    [ "$status" -eq 2 ]                       # b.js 는 여전히 미검토
    grep -q "	a.js\$" "$REPO_DIR/.git/mangolove/.review-covered"
    ! grep -q "	b.js\$" "$REPO_DIR/.git/mangolove/.review-covered"
}
