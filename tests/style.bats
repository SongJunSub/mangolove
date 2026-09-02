#!/usr/bin/env bats
# ─────────────────────────────────────────────
# MangoLove: 문장부호 규약을 코드로 강제한다
#
# 사용자 규약은 em dash 와 가운뎃점을 금지한다. 한국어 실무 문서에서 쓰지 않는
# 문장부호라 AI 가 쓴 티가 나기 때문이다. 그런데 이 규칙이 프롬프트에만 있고
# 코드에 없어서, 한 세션이 500줄 넘게 다시 만들어 놓았다. 사람이 손으로 훑는
# 방식은 더 나쁘다. 확장자 필터를 쓴 정리는 .gitignore, .shellcheckrc,
# config.sh.default, tests/test_helper.bash 의 15건을 통째로 놓쳤다.
#
# 그래서 어조가 아니라 게이트로 옮긴다(strict.md 의 「신뢰성 게이트」).
# git grep 은 추적 파일 전수를 훑고 바이너리를 알아서 건너뛴다. 확장자 목록을
# 손으로 관리하지 않는 것이 핵심이다. 그 목록이 바로 지난번 누락의 원인이었다.
# ─────────────────────────────────────────────

setup() {
    REPO="$BATS_TEST_DIRNAME/.."
    # 금지 문자를 이 파일에 리터럴로 적으면 검사가 자기 자신을 잡는다.
    # UTF-8 바이트로 만든다 (bash 3.2 에도 \u 없이 동작).
    EM_DASH="$(printf '\xe2\x80\x94')"      # U+2014
    MIDDOT="$(printf '\xc2\xb7')"           # U+00B7

    # 허용되는 UI 구분자 세 곳. 이 패턴들도 리터럴로 적으면 이 파일이 '가운뎃점을
    # 가진 파일' 이 되어 아래 파일 집합 검사가 자기 자신을 잡는다. 위에서 만든
    # 바이트로 조립해서 이 파일에는 금지 문자가 한 글자도 남지 않게 한다.
    UI_STATUSLINE="\" ${MIDDOT} \".join"
    UI_BANNER="\${FGR}${MIDDOT}\${R}"
    UI_README_SAMPLE="🥭 ${MIDDOT} Opus"
}

@test "style: em dash 가 추적 파일 어디에도 없다" {
    local hits
    hits="$(git -C "$REPO" grep -n -- "$EM_DASH" || true)"
    [ -z "$hits" ] || {
        echo "em dash 는 금지된 문장부호다. 문맥에 맞게 바꿔라."
        echo "  제목이나 라벨과 설명을 잇는 자리 -> ':'"
        echo "  산문 삽입구 -> 앞이 문장으로 끝나면 '.', 아니면 ','"
        echo "  범위 표기 -> '~'   목록 구분 -> '-'"
        echo "$hits"
        false
    }
}

@test "style: 가운뎃점이 산문에 없다 (UI 구분자만 예외)" {
    # 예외는 화면 요소다. statusline 의 구분자, 배너의 항목 구분자, 그리고
    # README 가 보여주는 상태줄 예시 출력. 셋 다 한국어 산문이 아니고,
    # 바꾸면 제품 외형이 달라지거나 문서가 실제 화면과 어긋난다.
    local hits
    hits="$(git -C "$REPO" grep -n -- "$MIDDOT" \
            | grep -vF -e "$UI_STATUSLINE" -e "$UI_BANNER" -e "$UI_README_SAMPLE" || true)"
    [ -z "$hits" ] || {
        echo "가운뎃점은 금지된 문장부호다. 문맥에 맞게 바꿔라."
        echo "  대등한 나열 -> ','   한 덩어리 개념 -> '과'/'와'/'나'   택일이나 구분 -> '/'"
        echo "$hits"
        false
    }
}

@test "style: UI 구분자 예외가 실제로 그 세 곳뿐이다" {
    # 예외 목록이 조용히 넓어지는 것을 막는다. 새 UI 구분자가 필요하면
    # 위 테스트의 예외에 추가하는 결정을 사람이 명시적으로 내려야 한다.
    # LC_ALL=C 로 고정한다. 로케일에 따라 대소문자 정렬 순서가 달라져
    # 같은 집합인데 문자열 비교가 깨진다.
    local allowed
    allowed="$(git -C "$REPO" grep -l -- "$MIDDOT" | LC_ALL=C sort | tr '\n' ' ')"
    [ "$allowed" = "README.md lib/banner.sh lib/statusline.sh " ] || {
        echo "가운뎃점을 가진 파일이 예상과 다르다: [$allowed]"
        echo "기대: README.md lib/banner.sh lib/statusline.sh"
        false
    }
}

@test "style: commit-msg 훅이 존재하고 금지 문자를 잡는다" {
    # 테스트는 추적 파일만 볼 수 있다. 커밋 메시지는 파일이 아니라서
    # 구조적으로 못 잡으므로, 그 자리는 훅이 맡는다.
    local hook="$REPO/.githooks/commit-msg"
    [ -x "$hook" ]

    local tmp; tmp="$(mktemp -d)"
    printf 'fix: 정상 메시지\n\n본문도 정상이다.\n' > "$tmp/ok.txt"
    run bash "$hook" "$tmp/ok.txt"
    [ "$status" -eq 0 ]

    printf 'fix: 제목에 %s 가 있다\n' "$EM_DASH" > "$tmp/bad1.txt"
    run bash "$hook" "$tmp/bad1.txt"
    [ "$status" -ne 0 ]

    printf 'fix: 정상 제목\n\n본문에 보안%s성능 이 있다.\n' "$MIDDOT" > "$tmp/bad2.txt"
    run bash "$hook" "$tmp/bad2.txt"
    [ "$status" -ne 0 ]

    # 주석 줄(#)은 커밋에 들어가지 않으므로 검사하지 않는다.
    printf 'fix: 정상 제목\n\n# 안내문에 %s 가 있어도 통과\n' "$EM_DASH" > "$tmp/ok2.txt"
    run bash "$hook" "$tmp/ok2.txt"
    [ "$status" -eq 0 ]

    rm -rf "$tmp"
}

@test "style: commit-msg 훅이 AI 저작 표기를 잡는다" {
    # 사용자 지침: 어떤 산출물에도 AI 가 작업했다는 표시를 남기지 않는다.
    # 하네스 기본 지침이 커밋 footer 에 공저자/세션 링크를 붙이라고 해도 따르지 않는다.
    local hook="$REPO/.githooks/commit-msg"
    local tmp; tmp="$(mktemp -d)"

    printf 'fix: 제목\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n' > "$tmp/a.txt"
    run bash "$hook" "$tmp/a.txt"
    [ "$status" -ne 0 ]

    printf 'fix: 제목\n\nClaude-Session: https://example.invalid/s\n' > "$tmp/b.txt"
    run bash "$hook" "$tmp/b.txt"
    [ "$status" -ne 0 ]

    printf 'fix: 제목\n\n本문\n\nGenerated with Claude Code\n' > "$tmp/c.txt"
    run bash "$hook" "$tmp/c.txt"
    [ "$status" -ne 0 ]

    # 사람 공저자는 정상이다. 이걸 막으면 훅이 쓸모없어진다.
    printf 'fix: 제목\n\nCo-Authored-By: 홍길동 <hong@example.com>\n' > "$tmp/ok.txt"
    run bash "$hook" "$tmp/ok.txt"
    [ "$status" -eq 0 ]

    rm -rf "$tmp"
}

@test "style: 추적 파일에 AI 저작 표기가 없다" {
    # 트레일러 형태(줄 시작)와 생성 표기만 잡는다. 방법론 문서가 금지 규칙을
    # 설명하며 그 이름을 문장 중간에 인용하는 것은 저작 표기가 아니다.
    local hits
    hits="$(git -C "$REPO" grep -nE '^Co-Authored-By:|^Claude-Session:|Generated with .*Claude Code' \
            -- . ':(exclude)tests/style.bats' ':(exclude).githooks/commit-msg' || true)"
    [ -z "$hits" ] || {
        echo "AI 저작 표기가 남아 있다:"
        echo "$hits"
        false
    }
}
