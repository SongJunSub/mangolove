#!/usr/bin/env bash
# ─────────────────────────────────────────────
# MangoLove: End-to-End A/B Harness  [Phase 4 / v2 skeleton]
#
# 질문: "방법론(mangolove)이 맨 claude보다 실제로 더 나은 결과를 내는가?"
# 이 하네스는 그 비교를 위한 **측정 도구**다. 두 부분으로 나뉜다: 정직성이 핵심:
#
#   ① 결과 채점 엔진: build/test, 트랙선언을 결정적으로 채점(impact-score, 체크 명령 재사용).
#      여기 내장 arm 은 **demo(손수 작성)**: 엔진이 좋은/나쁜 결과를 구별하는지 *자체 검증*할 뿐,
#      실제 모델 출력이 아니다.
#
#   ② live arm (`ab live`): 실모델 수치는 여기서만 나온다. 실행기를 직접 짜지 않고 Claude Code의
#      `claude plugin eval` 을 쓴다(v2.1.269+): cc-plugin/evals 의 케이스를 플러그인이 있는 arm 과
#      없는 arm 으로 각각 실세션에서 돌려 점수 차(Δ)를 낸다. 실세션 = 과금, 비결정성이라 CI 에서
#      돌리지 않는다(별도 opt-in). 재는 범위는 **cc-plugin(스킬, 에이전트)** 까지다. 시스템
#      프롬프트로 들어가는 core.md 와 세션 게이트는 그 세션에 실리지 않으므로 대상이 아니다.
#
# 절대 과장 금지: "mangolove > claude"는 ②를 충분한 반복으로 돌렸을 때만, 분포와 함께 말할 수
# 있다. ①은 측정 기계의 자체 검증이다.
#
# 사용: ab-harness.sh report | engine | live [claude plugin eval 옵션...]
# ─────────────────────────────────────────────
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMPACT="$SELF_DIR/impact-score.sh"

# ── ① 결과 채점 엔진 ──
# score_result <repo> <check_cmd> → "build:<0|1> track:<0|1>"
#   build/test: check_cmd 가 repo 에서 0 종료하면 1
#   track: HEAD 선언 트랙이 코드 floor 와 **일치(ok)**하면 1. 과대선언(over), 과소선언(under), 미선언은
#          전부 0: 과대선언도 잘못된 트리아지(불필요한 무거운 절차)이므로 성공이 아니다.
score_result() {
    local repo="$1" check="$2" b=0 t=0 verdict
    if ( cd "$repo" && bash -c "$check" ) >/dev/null 2>&1; then b=1; fi
    verdict="$(cd "$repo" && bash "$IMPACT" triage-commit HEAD 2>/dev/null | sed -E 's/.*"verdict":"([^"]+)".*/\1/')"
    case "$verdict" in ok) t=1 ;; esac
    printf 'build:%s track:%s' "$b" "$t"
}

# demo task 의 수용 체크: auth 체크 함수가 실제로 존재하는가
_demo_check() { echo 'test -f src/auth/check.kt && grep -q isAdmin src/auth/check.kt'; }

# demo 처치-style arm: 통과하는 변경 + floor 에 맞는 Change-Track 트레일러
_demo_arm_good() {
    local repo="$1"
    git -C "$repo" init -q
    mkdir -p "$repo/src/auth"
    printf 'fun isAdmin(u: User) = u.role == "ADMIN"\n' > "$repo/src/auth/check.kt"
    git -C "$repo" add -A
    git -C "$repo" -c user.email=e@e -c user.name=n \
        commit -qm "$(printf 'feat: admin check\n\nChange-Track: Large\n')" >/dev/null 2>&1
}

# demo 대조-style arm: 깨진 변경(체크 실패) + 트레일러 없음
_demo_arm_bad() {
    local repo="$1"
    git -C "$repo" init -q
    mkdir -p "$repo/src/auth"
    printf 'fun todo() {}\n' > "$repo/src/auth/check.kt"
    git -C "$repo" add -A
    git -C "$repo" -c user.email=e@e -c user.name=n commit -qm "wip" >/dev/null 2>&1
}

# 결과 채점 엔진 자체 검증 → ENG_GOOD / ENG_BAD (각 "build:x track:y")
ab_engine_selftest() {
    local rg rb
    rg="$(mktemp -d)"; rb="$(mktemp -d)"
    _demo_arm_good "$rg"; _demo_arm_bad "$rb"
    ENG_GOOD="$(score_result "$rg" "$(_demo_check)")"
    ENG_BAD="$(score_result "$rb" "$(_demo_check)")"
    rm -rf "$rg" "$rb" 2>/dev/null
}

# 엔진이 좋은 결과는 전부 통과, 나쁜 결과는 전부 실패로 채점했는가. 아니면 회귀다:
# 채점 엔진이 고장 나도 하네스가 성공으로 끝나면 그 위의 live 수치도 믿을 수 없다.
_engine_ok() { [ "$ENG_GOOD" = "build:1 track:1" ] && [ "$ENG_BAD" = "build:0 track:0" ]; }

report() {
    echo "A/B 하네스 (Phase 4 v2, 방법론 vs 맨 claude)"
    echo "[정직] ①은 채점 엔진 자체검증(demo arm, 실제 모델 출력 아님)."
    echo "       실모델 A/B 수치는 'mangolove ab live' 가 낸다(claude plugin eval: 과금, 비결정성, CI 미실행)."
    echo ""

    ab_engine_selftest
    echo "① 결과 채점 엔진 (demo arm 자체검증, 실수치 아님):"
    printf '  처치-style arm: %s\n' "$ENG_GOOD"
    printf '  대조-style arm: %s\n' "$ENG_BAD"
    echo "  (엔진이 좋은/나쁜 결과를 build, track 으로 구별함. 실모델 수치는 'ab live' 필요.)"

    echo ""
    echo "이 보고서는 결정적 계층만 다룬다: 실모델 A/B 수치 없음. 내려면 'mangolove ab live' (과금)."
    if ! _engine_ok; then
        echo "결과: 회귀 감지, 채점 엔진이 기대(good[build:1 track:1] bad[build:0 track:0])와 다르게 채점했습니다."
        return 1
    fi
}

# ── ② live arm: claude plugin eval ──
# 플러그인 디렉토리는 MangoLove 가 싣고 다니는 cc-plugin 으로 고정이다(임의 플러그인을 받지 않는다).
# 그래서 --trust-plugin 을 넘긴다: 비대화 실행에서는 신뢰 확인 프롬프트에 답할 수 없다.
# --no-publish: 리포트는 기본이 claude.ai 게시다. 요청 없이 외부로 내보내지 않는다.
# 비용: 케이스 x 반복(기본 3) x arm 2개의 실세션에 judge 호출이 더해진다. 상한을 넘으면
# 부분 결과를 내고 멈춘다(exit 2). 반복을 줄이려면 `ab live --runs 1`.
ab_live() {
    local plugin="${MANGOLOVE_AB_PLUGIN_DIR:-$SELF_DIR/../cc-plugin}"
    command -v claude >/dev/null 2>&1 || { echo "ab live: claude 를 찾을 수 없습니다." >&2; return 2; }
    [ -d "$plugin/evals" ] || { echo "ab live: eval 케이스가 없습니다: $plugin/evals" >&2; return 2; }
    # 종료코드로는 알 수 없다: 없는 서브커맨드에 --help 를 붙이면 claude 는 plugin 도움말을 찍고
    # 0 을 낸다. eval 의 도움말에만 나오는 옵션이 있는지로 판단한다. 출력을 받아 두고 본다:
    # 파이프로 grep -q 에 물리면 pipefail 아래에서 일찍 끝난 grep 이 앞 명령을 SIGPIPE 로 죽여
    # "없음"으로 오판할 수 있다.
    local eval_help
    eval_help="$(claude plugin eval --help 2>&1)" || true
    case "$eval_help" in
        *--ablation*) ;;
        *) echo "ab live: 'claude plugin eval' 이 없습니다 (Claude Code v2.1.269 이상 필요)." >&2; return 2 ;;
    esac
    local cap="${AB_LIVE_MAX_COST_USD:-3}"
    echo "live arm: 실세션을 띄우므로 과금됩니다 (케이스 x 반복 x arm 2개). 비용 상한 \$${cap}"
    claude plugin eval "$plugin" --no-publish --trust-plugin --ablation with-without \
        --max-cost-usd "$cap" "$@"
}

main() {
    case "${1:-report}" in
        live) shift; ab_live "$@" ;;
        report|"") report ;;
        engine)
            ab_engine_selftest
            printf 'engine selftest: good[%s] bad[%s]\n' "$ENG_GOOD" "$ENG_BAD"
            _engine_ok
            ;;
        *) echo "usage: ab-harness.sh {report|engine|live}" >&2; exit 2 ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
