#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove: Review gate (트랙별 필수 리뷰의 결정적 강제)
#
# 회귀 대상 행동: "Medium 트랙인데 /simplify 와 코드 리뷰를 돌리지 않았습니다,
# 필요하시면 지금 돌리겠습니다": 트랙을 선언하고 절차를 생략한 뒤 사후에 고백하는 것.
# 이 게이트는 push 경계에서 코드가 트랙을 계산해 그 답변 자체가 불가능하게 만든다.
#
# 경계가 commit 이 아니라 push 인 이유는 실측이다(차단 39건 중 23건이 10분 내 재차단).
# 그 이동이 안전을 깎지 않는다는 것을 "위험" 테스트들이 고정한다(이 파일과 review-gate-coverage.bats).
# ─────────────────────────────────────────────

load test_helper
load review_gate_helper

# ── 정책 표 (required_skills): strict.md 의 트랙별 리뷰 표와 단일 출처를 공유한다 ──

@test "policy: Trivial/Small 은 아무 리뷰도 요구하지 않는다 (과대 판정 방지)" {
    run bash "$GATE" required Trivial false false false
    [ "$status" -eq 0 ]
    [ -z "$(echo "$output" | tr -d '[:space:]')" ]
    run bash "$GATE" required Small false false false
    [ -z "$(echo "$output" | tr -d '[:space:]')" ]
}

@test "policy: Medium 은 simplify + code-review" {
    run bash "$GATE" required Medium false false false
    [ "$output" = "simplify code-review" ]
}

@test "policy: Large 는 security-review 까지" {
    run bash "$GATE" required Large false false false
    [ "$output" = "simplify code-review security-review" ]
}

@test "policy: DB/인증/외부API 신호가 있으면 트랙과 무관하게 security-review 추가" {
    run bash "$GATE" required Medium true false false
    [[ "$output" == *"security-review"* ]]
    run bash "$GATE" required Medium false false true
    [[ "$output" == *"security-review"* ]]
}

# ── push 경계 게이트 ────────────────────────────────────────────

@test "gate: push 가 아닌 Bash 는 통과 (게이트가 일반 작업을 막지 않는다)" {
    _commit_external_api
    _gate "git log --grep=push"
    [ "$status" -eq 0 ]
}

@test "gate: commit 은 더 이상 게이트 대상이 아니다 (로컬 작업을 방해하지 않는다)" {
    # 경계를 push 로 옮긴 핵심. 커밋마다 막던 것이 재차단 23건의 원인이었다.
    _commit_external_api
    _gate "git commit -m x"
    [ "$status" -eq 0 ]
}

@test "gate: Trivial 범위 push 는 리뷰 없이 통과 (사소한 작업에 절차를 씌우지 않는다)" {
    echo "one line" > "$REPO_DIR/a.txt"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm x
    _gate "git push"
    [ "$status" -eq 0 ]
}

@test "gate: Medium 범위인데 리뷰 미실행이면 push 차단(exit 2)" {
    _commit_external_api
    _gate "git push"
    [ "$status" -eq 2 ]
    [[ "$output" == *"push 차단"* ]]
    [[ "$output" == *"simplify"* ]]
    [[ "$output" == *"code-review"* ]]
}

@test "gate: 원장에 필수 스킬이 기록돼 있고 그 내용이면 통과한다" {
    _commit_external_api
    _run_all_reviews
    [ -f "$REPO_DIR/.git/mangolove/.review-ledger" ]
    _gate "git push"
    [ "$status" -eq 0 ]
}

@test "gate: 일부만 실행하면 부족분만 지목하며 차단" {
    _commit_external_api
    printf '%s' "$(_json_skill simplify)" | bash "$GATE" record
    _gate "git push"
    [ "$status" -eq 2 ]
    [[ "$output" == *"code-review"* ]]
}

@test "gate: 플러그인 네임스페이스(code-review:code-review)도 같은 스킬로 인정" {
    _commit_external_api
    printf '%s' "$(_json_skill simplify)" | bash "$GATE" record
    printf '%s' "$(_json_skill "code-review:code-review")" | bash "$GATE" record
    printf '%s' "$(_json_skill "security:security-review")" | bash "$GATE" record
    _gate "git push"
    [ "$status" -eq 0 ]
}

# ── 이 이동이 없앤 소음 ─────────────────────────────────────────

@test "개선: 리뷰 한 번 뒤 커밋을 몇 개로 쪼개 담아도 push 는 통과한다" {
    # 옛 게이트의 실패 모드: 커밋이 성공해 HEAD 가 움직이면 원장을 버려서, 두 번째
    # 커밋부터 이미 한 리뷰를 다시 요구했다. 실측 차단의 59%가 이것이었다.
    printf 'const a = await axios.get("https://api.example.com/a")\n' > "$REPO_DIR/a.js"
    printf 'const b = await axios.get("https://api.example.com/b")\n' > "$REPO_DIR/b.js"
    printf 'const c = await axios.get("https://api.example.com/c")\n' > "$REPO_DIR/c.js"
    _run_all_reviews   # 워킹트리 상태 그대로를 리뷰가 봤다

    local f
    for f in a b c; do
        git -C "$REPO_DIR" add "$f.js"
        git -C "$REPO_DIR" commit -qm "add $f"
    done
    _gate "git push"
    [ "$status" -eq 0 ]
}

@test "개선: 이미 upstream 에 있는 브랜치를 머지해도 push 는 통과한다 (머지 특별처리 없이)" {
    # 원래 막혔던 케이스: `merge: HUB2-378 ... 반영` 이 13개 파일 Large 로 계산됐다.
    # 세 점 범위의 merge base 가 그 내용을 자동으로 뺀다.
    git -C "$REPO_DIR" checkout -q -b feat-378
    printf 'const x = await axios.get("https://api.example.com/378")\n' > "$REPO_DIR/f378.js"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm "378 work"

    # 378 이 upstream 에 반영됐다 (= 그 브랜치에서 이미 검토, 공유된 코드)
    git -C "$REPO_DIR" checkout -q main
    git -C "$REPO_DIR" merge -q --no-ff -m "merge 378" feat-378
    git -C "$REPO_DIR" update-ref refs/remotes/origin/main HEAD

    # 내 브랜치는 378 을 머지하고 사소한 작업만 얹는다
    git -C "$REPO_DIR" checkout -q -b feat-379 refs/remotes/origin/main
    echo mine > "$REPO_DIR/mine.txt"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm "my small work"

    _gate "git push"
    [ "$status" -eq 0 ]
}

# ── 위험 회귀: push 로 옮기면서 안전이 깎이지 않았음을 고정한다 ──

@test "위험1: 머지 충돌을 해결하며 새로 쓴 코드는 범위에 남아 차단된다" {
    git -C "$REPO_DIR" checkout -q -b other
    echo theirs > "$REPO_DIR/shared.js"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm theirs
    git -C "$REPO_DIR" checkout -q main
    echo ours > "$REPO_DIR/shared.js"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm ours
    git -C "$REPO_DIR" merge -q other 2>/dev/null || true
    # 충돌 해결이랍시고 검토되지 않은 새 코드를 써 넣는다
    printf 'const evil = await axios.post("https://api.example.com/x", {})\n' > "$REPO_DIR/shared.js"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm "resolve"
    _gate "git push"
    [ "$status" -eq 2 ]
}

@test "위험2: 리뷰가 본 뒤에 쓴 코드가 그것만으로 리뷰 대상이면 차단된다" {
    # 리뷰 뒤 변경은 리뷰가 본 판본과의 차이만 따로 잰다(tests/review-gate-delta.bats).
    # 그 차이가 Trivial/Small 이면 통과하고 효능 원장에 남는다. 여기서는 막혀야 하는 쪽을 고정한다.
    printf 'const a = await axios.get("https://api.example.com/a")\n' > "$REPO_DIR/a.js"
    _run_all_reviews    # 이 내용까지가 리뷰가 본 것
    # 리뷰 이후에 외부 호출을 하나 더 써 넣는다
    _add_external_call "$REPO_DIR/a.js" sneak
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm "sneak"
    _gate "git push"
    [ "$status" -eq 2 ]
}

@test "위험3: 작은 커밋으로 쪼개도 범위는 합쳐서 계산돼 차단된다" {
    # 커밋 하나하나는 Trivial 이라 커밋 경계 게이트라면 전부 통과했을 변경이다.
    local i
    for i in $(seq 1 11); do
        echo "export const V$i = $i" > "$REPO_DIR/f$i.js"
        git -C "$REPO_DIR" add -A
        git -C "$REPO_DIR" commit -qm "c$i"
    done
    _gate "git push"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Medium"* ]]
}

@test "위험4: upstream 에 없는 브랜치를 머지하면 그 내용이 범위에 남아 차단된다" {
    git -C "$REPO_DIR" checkout -q -b rogue
    printf 'const r = await axios.post("https://api.example.com/rogue", {})\n' > "$REPO_DIR/rogue.js"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm rogue
    git -C "$REPO_DIR" checkout -q main
    git -C "$REPO_DIR" merge -q --no-ff -m "merge rogue" rogue
    _gate "git push"
    [ "$status" -eq 2 ]
}

@test "세션: 다른 세션이 스킬을 돌려도 이 세션이 돌린 리뷰가 지워지지 않는다" {
    # 원장을 세션으로 무효화하던 시절, 같은 worktree 의 다른 세션이 아무 스킬이나 부르면
    # 리뷰 기록이 통째로 지워져 리뷰를 다 돌린 push 가 "미실행"으로 막혔다.
    _commit_external_api
    SESSION=s1 _run_all_reviews
    printf '%s' "$(SESSION=s2 _json_skill linear-ticket)" | bash "$GATE" record
    run bash -c "printf '%s' '$(SESSION=s1 _json_cmd "git push")' | bash '$GATE' pretooluse"
    [ "$status" -eq 0 ]
    run bash -c "printf '%s' '$(SESSION=s2 _json_cmd "git push")' | bash '$GATE' pretooluse"
    [ "$status" -eq 0 ]
}

@test "세션: 세션이 바뀌어도 리뷰가 본 뒤 바뀐 내용은 막힌다 (내용 주소가 기준)" {
    printf 'const a = await axios.get("https://api.example.com/a")\n' > "$REPO_DIR/a.js"
    SESSION=s1 _run_all_reviews
    printf 'const a = await axios.post("https://api.example.com/a", {})\nconst e = eval(x)\n' > "$REPO_DIR/a.js"
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -qm sneak
    run bash -c "printf '%s' '$(SESSION=s2 _json_cmd "git push")' | bash '$GATE' pretooluse"
    [ "$status" -eq 2 ]
}

# ── 명령 인식 경계 ──────────────────────────────────────────────

@test "gate: --dry-run push 는 아무 것도 공유하지 않으므로 통과" {
    _commit_external_api
    _gate "git push --dry-run"
    [ "$status" -eq 0 ]
}

@test "gate: push 뒤에 붙은 다른 명령의 -n 을 dry-run 으로 오인하지 않는다" {
    # 오인하면 게이트가 통째로 샌다. 오탐보다 누락이 위험한 방향이다.
    _commit_external_api
    _gate "git push origin main && echo -n done"
    [ "$status" -eq 2 ]
}

@test "gate: 멀티라인 명령의 git push 도 잡는다 (JSON 의 \\n 이 단어 경계를 지운다)" {
    _commit_external_api
    _gate 'git add -A\ngit push'
    [ "$status" -eq 2 ]
}

@test "gate: gh pr create 는 내용을 올리지 않으므로 게이트 대상이 아니다" {
    # 올라간 브랜치는 원격 추적 ref 가 갱신돼 범위가 늘 비고, 안 올라간 브랜치로는 PR 을 만들 수
    # 없다(비대화형 gh 는 push 를 대신하지 않는다). 막을 수 있는 대상이 없으니 걸지 않는다.
    _commit_external_api
    _gate "gh pr create --fill"
    [ "$status" -eq 0 ]
}

@test "gate: 여러 줄이어도 push 가 없으면 통과한다 (오탐 방지)" {
    _commit_external_api
    _gate 'git log --grep=push\necho done'
    [ "$status" -eq 0 ]
}
