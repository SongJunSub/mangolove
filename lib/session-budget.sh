#!/usr/bin/env bash
# ─────────────────────────────────────────────
# MangoLove: session context budget (Stop hook)
#
# 왜 있는가 (실측):
#   이 머신의 세션 118개를 집계하니 상위 10세션이 총비용의 64%, 턴 300+ 인 45세션이 95% 였고,
#   상위 세션의 peak context 는 전부 1M 천장이었다. 캐시 적중률은 이미 97.9% 라 캐시는
#   레버가 아니다. 비용은 전적으로 "세션을 안 끊고 계속 쓰는" 습관에서 나온다.
#   그런데 그에 대한 대응은 상태줄의 시각 넛지 하나뿐이었다(= 산문 규율, 확률적).
#   strict.md 의 「신뢰성 게이트」가 지목하는 상황이다: 규율이 어조에만 있으면 지켜지지 않는다.
#
# 무엇을 재는가:
#   턴 수가 아니라 **현재 컨텍스트 크기**를 잰다. 턴 수는 진짜 동인의 느슨한 대리 지표이고,
#   무엇보다 세션마다 세려면 상태를 프로젝트 단위 파일에 둬야 해서 같은 레포의 두 세션이
#   서로의 카운트를 리셋한다(dod-gate 가 겪은 사고의 변종). 컨텍스트는 그 세션 자신의
#   transcript 에서 직접 읽으므로 그 문제가 구조적으로 없다.
#   한 요청이 실제로 보낸 컨텍스트 = input_tokens + cache_creation + cache_read 이고,
#   transcript 의 마지막 usage 레코드가 곧 현재 값이다.
#
# 임계 보정(실측 2회). 처음엔 "싼 세션을 건드리지 않는가"(오탐)로 골랐고 200K 가 답이었다.
# 재측정에서 그 지표는 판별력을 잃었다: 135세션 기준 200K~800K 어느 값에서도 $10 미만
# 세션은 0개가 걸린다. 임계는 싼 세션을 거르는 문제가 아니었다.
#
# 실제로 갈리는 지표는 **안내가 행동으로 옮겨질 만한 지점인가**다. 알림 직후 그 세션이
# 컨텍스트를 얼마나 더 늘렸는지로 잰다(135세션, $21,346):
#   임계   발화세션  알림/세션  알림후 증가배수(중앙값)  비용커버  걸린금액(중앙값)
#   200K     75        2.0          2.75x                94.3%      $91
#   400K     54        1.4          1.66x                82.9%      $93    <- 기본값
#   500K     43        1.0          1.56x                76.0%      $116
# 200K 에서는 알림을 받고도 컨텍스트가 중앙값 2.75배 더 늘었다. 그 시점의 세션은 객관적으로
# 갈 길이 한참 남아 있었고, 무시하는 쪽이 옳았다는 뜻이다. 무시되는 안내는 정작 중요한
# 800K 안내까지 같이 무시하게 만들어 게이트 전체를 죽인다. 1M 윈도우 기준 400K = 40%,
# 다음 버킷 800K = 80% 라 사다리가 창 크기와도 맞는다. 비용커버 11.4%p 를 내주지만,
# 그 돈은 애초에 무시되던 안내로는 지켜지지 않았다.
#   (사용자 보고에서 출발했다: "200K 는 너무 쉽게 뜬다, 계속 진행해도 될 것 같다".
#    이 머신의 실제 이력이 정확히 그랬다: 200K 안내를 받은 8세션 중 6개가 400K 를 넘겼고,
#    그중 2개는 800K 까지 갔다. 안내는 8번 중 6번 무시됐고, 무시하는 쪽이 옳았다.)
#
# 계약(stdin=JSON, exit code 로 제어), 위에서부터:
#   stop_hook_active == true       → exit 0  (이미 어떤 Stop 훅이 막아 이어지는 중)
#   MANGOLOVE_SESSION_BUDGET=off   → exit 0  (주 스위치는 주입 시점이다. 아래 "끄기" 참조)
#   transcript 없음/컨텍스트 미상  → exit 0  (fail-open)
#   컨텍스트 < 임계                → exit 0  (상태 읽기/쓰기 없음: 절대다수 턴의 경로)
#   이 버킷을 이미 통지            → exit 0
#   상태 쓰기 실패                 → exit 0  ("쓰기에 성공했을 때만 exit 2" 가 루프 불가 불변식)
#   그 외 (버킷 최초 도달)         → stderr 안내 → exit 2
#
# 왜 exit 2 인가 (실측으로 확인함):
#   Stop 훅에서 모델에 메시지를 전달하는 경로는 exit 2 뿐이다. exit 0 + stderr,
#   exit 0 + {"systemMessage":...}, exit 0 + {"decision":"block"} 은 전부 모델에 닿지 않는다.
#   안내가 모델에 닿아야 사용자에게 relay 된다. 버킷당 1회뿐이고, 1M 컨텍스트 턴 1회의
#   입력비용이 약 $0.50 이므로 세션당 2~4회면 최고비용 세션($2,499) 대비 0.08% 다.
#
#   이건 시크릿 게이트 같은 **진짜 차단이 아니다.** 같은 메커니즘(exit 2)을 쓰지만 의미는
#   "이 턴을 한 번 붙잡아 안내를 전달한다"이다. 확장할 때 이 구분을 지울 것.
#
# 효능 원장:
#   통지(exit 2)는 record-block: 이 훅이 실제로 한 일이 그것이고, dod-gate 가 exit 2 에
#   record-block 을 쓰는 것과 대칭이다. fail-open 중에는 **쓰기 실패만** record-skip 으로
#   남긴다. 임계 미만/이미 통지 같은 경로는 매 턴 발생해서, 기록하면 원장이 수천 줄로
#   불어나 efficacy 리포트의 다른 신호를 통째로 덮는다.
#   (record-block/record-skip 뒤의 phase 이름은 헬퍼로 감싸지 않고 호출부에 리터럴로 둔다:
#    audit-methodology.sh 가 그 문자열에서 게이트 phase 우주를 파생한다. 커밋 5b707ea 회귀.)
#
# 상태: ${MANGOLOVE_DIR}/state/session-budget/<session_id>  (레포 밖, 세션별)
#   레포 안에 두지 않으므로 .mangolove/.gitignore 시딩이 필요 없다(dod-gate/review-gate 에
#   있는 _ml_seed_gitignore 의 세 번째 사본을 만들지 않는다). 세션별이라 진동도 없다.
#   죽은 세션의 파일은 통지 시점(드묾)에 30일 기준으로 정리한다.
#
# 비용 (실측, 같은 머신 70MB transcript, 임계 미만 = 매 턴 도는 경로):
#   dod-gate 의 idle 경로 대비 +18.5ms/턴. 전부 transcript tail 읽기(tail+awk 포크 3개)다.
#   나머지 경로는 포크 0 이다(정규식을 호출부에 인라인해 $() 서브셸을 없앴다).
#   Stop 훅은 턴당 1회, 같은 이벤트의 훅끼리 병렬로 도므로 체감 지연은 아니다.
#   off 로 끄면 훅 자체가 주입되지 않아 이 비용이 완전히 사라진다.
#
# 끄기: MANGOLOVE_SESSION_BUDGET=off
#   주 스위치는 generate_session_settings() 의 주입 시점이다(off 면 훅 자체가 안 실린다
#   = 진짜 0 비용). 아래 런타임 검사는 이중 안전장치다. 완전한 롤백은 env 가 아니라
#   주입 커밋을 되돌리는 것이다.
#
# 알려진 한계 (전부 "차단하지 않는" 방향이라 오탐보다 안전하다):
#   1) **읽는 값은 한 턴 뒤처진다.** usage 레코드는 Stop 훅이 발화한 *뒤에* transcript 에
#      기록된다(실측: 훅 시점의 37KB transcript 에 "input_tokens" 레코드가 0개였다).
#      그래서 이 훅이 보는 것은 직전 턴까지의 컨텍스트다. 500K 임계에서 한 턴 차이는
#      무의미하고, 타깃 코호트(장기 세션)의 tail 에는 usage 레코드가 10~20개씩 들어 있어
#      정상 계산된다(실측 확인). 반면 -p 일회성 세션처럼 앞선 턴이 없으면 0 을 읽고
#      통과한다: 그런 세션은 애초에 이 게이트가 겨냥하는 대상이 아니다.
#   2) --resume 으로 session_id 가 바뀌면 통지 이력이 초기화돼 같은 버킷에서 한 번 더 알린다.
#   3) 임계는 절대 토큰 수다. 1M 윈도우 모델 기준으로 보정했으므로 200K 윈도우 세션에서는
#      기본값이 발화하지 않는다. 그런 세션은 애초에 이 게이트가 겨냥하는 코호트가 아니다.
# ─────────────────────────────────────────────
set -uo pipefail

# 스크립트 위치는 cd 전에 확정한다(dod-gate 와 같은 이유: 이동 후 상대 경로로 계산하면
# 빈 값이 되어 효능 기록이 조용히 죽는다). 파라미터 확장이라 포크를 늘리지 않는다.
case "${BASH_SOURCE[0]}" in
    /*)  GATE_DIR="${BASH_SOURCE[0]%/*}" ;;
    */*) GATE_DIR="$PWD/${BASH_SOURCE[0]%/*}" ;;
    *)   GATE_DIR="$PWD" ;;
esac

STATE_ROOT="${MANGOLOVE_DIR:-$HOME/.mangolove}/state/session-budget"

# ── stdin JSON 필드 추출: 정규식을 **호출부에 직접** 둔다.
# 헬퍼 함수로 빼면 값을 받으려고 $(...) 를 써야 하고, 그 서브셸이 곧 포크다.
# fork-0 함수를 $() 로 감싸면 최적화가 통째로 사라진다(실측: 포크 2개 = 4~6ms/턴,
# 이 훅 전체 실행시간의 15~20%). dod-gate/review-gate 는 idle 경로에서 즉시 빠져나가
# 호출이 1회뿐이라 함수형을 쓸 수 있지만, 이 훅은 매 턴 끝까지 돈다.
# 정규식 자체는 dod-gate.sh 의 _json_str 과 같은 형태다(이스케이프된 따옴표 처리 포함).
_RE_BOOL_ACTIVE='"stop_hook_active"[[:space:]]*:[[:space:]]*(true|false)'
_RE_TRANSCRIPT='"transcript_path"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)"'
_RE_SESSION='"session_id"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)"'

# ── transcript 꼬리에서 마지막 요청의 컨텍스트 크기.
# 전수 파싱하지 않는다: transcript 는 최대 73MB 이고, 매 턴 전수 파싱은 세션 전체로 O(n^2) 다.
# tail 은 끝으로 seek 하므로 파일 크기와 거의 무관하다(실측 70MB 파일에서 11.7ms).
# 기본 256KB 는 실측 보정값이다: 마지막 128KB 에는 보통 usage 레코드가 16개쯤 들어 있어
# 정상 케이스는 충분하지만, 이 머신의 transcript 에는 128KB 를 단독으로 넘는 라인이 184개
# (최대 1.04MB) 있어 그런 라인 위에서 턴이 끝나면 레코드를 하나도 못 찾는다. 256KB 로
# 올리는 비용은 +2~4ms 로 사실상 공짜다. 관측된 최악(1MB)까지 덮으려면 +25ms 가 드는데,
# 그건 매 턴 내는 값으로는 비싸고 놓쳐도 fail-open 이라 여기서 멈춘다.
# awk 한 번에 세 필드를 뽑는다. "input_tokens" 앞의 따옴표가 필수라
# cache_creation_input_tokens / cache_read_input_tokens 에 오매칭되지 않는다(python3 대조 확인).
_read_ctx() {
    # LC_ALL=C 는 필수다. tail -c 는 바이트 경계에서 자르므로 첫 레코드가 UTF-8 문자
    # 중간에서 시작하는 일이 흔한데, macOS awk(20200816)는 그때 "towc: multibyte
    # conversion failure" 로 **죽는다**. END 에 닿지 못해 아무것도 출력하지 않고,
    # 그 에러는 2>/dev/null 에 삼켜져 CTX 가 빈 값이 되고 게이트가 조용히 꺼진다.
    # 실측: 이 머신의 256KB 초과 transcript 중 8.8% 가 그렇게 무음이 됐고, 하필
    # 한국어 위주의 긴 세션(= 이 게이트의 타깃 코호트)에서 터진다. 게다가 자르는
    # 지점이 파일이 커질수록 움직여서 턴마다 켜졌다 꺼졌다 한다.
    # C 로케일이면 바이트로만 다루므로 이 경로가 사라진다(정상 파일의 결과는 동일).
    tail -c "${MANGOLOVE_SESSION_BUDGET_TAIL:-262144}" "$1" 2>/dev/null | LC_ALL=C awk '
        /"input_tokens"/ {
            i = 0; w = 0; r = 0
            if (match($0, /"input_tokens":[0-9]+/))                { i = substr($0, RSTART + 15, RLENGTH - 15) }
            if (match($0, /"cache_creation_input_tokens":[0-9]+/)) { w = substr($0, RSTART + 30, RLENGTH - 30) }
            if (match($0, /"cache_read_input_tokens":[0-9]+/))     { r = substr($0, RSTART + 26, RLENGTH - 26) }
            if (i + w + r > 0) { last = i + w + r }
        }
        END { print last + 0 }
    ' 2>/dev/null
}

# 효능 원장 기록(비차단, 실패무시).
_record_efficacy() {
    local rec="$GATE_DIR/efficacy-recorder.sh"
    [ -f "$rec" ] || return 0
    bash "$rec" "$@" 2>/dev/null || true
}

# ① 런타임 이중 안전장치(주 스위치는 주입 시점). stdin 을 읽기도 전에 끝나는 가장 싼 검사다.
#    값 집합은 bin/mangolove 의 _ml_is_off 와 같아야 한다(off/false/0/no/disabled, 대소문자 무관).
#    그 함수를 그대로 못 쓰는 것은 훅이 별도 프로세스로 뜨기 때문이고, tr 포크를 되살리지
#    않으려고 case 패턴으로 대소문자를 흡수한다.
case "${MANGOLOVE_SESSION_BUDGET:-on}" in
    [Oo][Ff][Ff]|[Ff][Aa][Ll][Ss][Ee]|0|[Nn][Oo]|[Dd][Ii][Ss][Aa][Bb][Ll][Ee][Dd]) exit 0 ;;
esac

IFS= read -r -d '' input || true

# ② 이미 어떤 Stop 훅이 막아 이어지는 중이면 관여하지 않는다.
[[ "$input" =~ $_RE_BOOL_ACTIVE ]] && [ "${BASH_REMATCH[1]}" = "true" ] && exit 0

TRANSCRIPT=""
[[ "$input" =~ $_RE_TRANSCRIPT ]] && TRANSCRIPT="${BASH_REMATCH[1]}"
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0

# 임계: 10# 로 강제 십진 해석. "0500000" 은 숫자 검사를 통과하고도 8진수로 읽혀 산술을
# 깨뜨리고, set -u 와 맞물려 훅을 죽인다(= 게이트가 조용히 꺼진다). dod-gate 가 겪은 사고.
THRESH="${MANGOLOVE_SESSION_BUDGET_TOKENS:-400000}"
case "$THRESH" in
    ''|*[!0-9]*) THRESH=400000 ;;
    *) THRESH=$((10#$THRESH)); [ "$THRESH" -ge 1 ] || THRESH=400000 ;;
esac

CTX="$(_read_ctx "$TRANSCRIPT")"
case "$CTX" in ''|*[!0-9]*) exit 0 ;; esac

# ③ 임계 미만: 절대다수의 턴이 여기서 끝난다. 상태 파일을 읽지도 쓰지도 않는다.
[ "$CTX" -lt "$THRESH" ] && exit 0

# 도달한 최고 버킷: THRESH 에서 **배증**한다 (400K, 800K ...).
# 등차(THRESH/2 씩)로 하면 임계가 낮을수록 알림이 촘촘해진다: 400K 등차는 1M 세션에서
# 4회, 배증은 2회다. 세션이 길어질수록 알림 간격이 벌어지는 쪽이 옳다.
BUCKET="$THRESH"
while [ $((BUCKET * 2)) -le "$CTX" ]; do BUCKET=$((BUCKET * 2)); done

SESSION=""
[[ "$input" =~ $_RE_SESSION ]] && SESSION="${BASH_REMATCH[1]}"
[ -n "$SESSION" ] || SESSION="_nosession"
SESSION="${SESSION//[^A-Za-z0-9._-]/_}"     # 경로 조작 방지: 파일명에 쓰기 전에 정규화
STATE="$STATE_ROOT/$SESSION"

NOTIFIED=0
if [ -f "$STATE" ]; then
    read -r NOTIFIED < "$STATE" 2>/dev/null || NOTIFIED=0
    case "$NOTIFIED" in ''|*[!0-9]*) NOTIFIED=0 ;; *) NOTIFIED=$((10#$NOTIFIED)) ;; esac
fi

# ④ 이 버킷은 이미 알렸다.
[ "$BUCKET" -le "$NOTIFIED" ] && exit 0

# ⑤ 상태를 먼저 기록한다. 실패하면 통지하지 않는다: 기록 없이 exit 2 를 내면 다음 Stop 이
#    같은 버킷을 다시 통지해 무한루프가 된다. "쓰기 성공 시에만 차단"이 그 불변식이다.
mkdir -p "$STATE_ROOT" 2>/dev/null
if ! printf '%s\n' "$BUCKET" > "$STATE" 2>/dev/null; then
    _record_efficacy record-skip budget "write-fail"
    exit 0
fi

# 죽은 세션의 상태 파일 정리. 통지 시점(드묾)에만 돌아 상시 비용이 없다.
find "$STATE_ROOT" -type f -mtime +30 -delete 2>/dev/null || true

# 다음 안내 지점. 배증한 값이 현행 최대 창(1M)을 넘으면 그 안내는 영영 오지 않으므로
# "다음 1600K" 는 거짓말이 된다. 그 경우엔 마지막 안내임을 밝힌다. 포크는 늘지 않는다.
if [ $((BUCKET * 2)) -le 1000000 ]; then
    NEXT_NOTE="다음 $((BUCKET / 500))K"
else
    NEXT_NOTE="1M 창 기준 이번이 마지막"
fi

# 안내: 자문 어조로 쓴다. 강한 명령형은 모델이 실제 차단으로 과잉 해석해 작업을 멈추게 한다.
# 달러가 아니라 컨텍스트로 시작한다(구독 과금이면 달러는 동기부여가 되지 않는다).
# 끊는 비용(맥락 손실)을 낮추는 경로를 함께 준다: 그게 없으면 안내는 실행되지 않는다.
#
# 단정형을 금지하는 문장을 넣는다. 이전 문안은 "끊기 좋은 지점인지 알려주세요"였는데,
# 모델이 그것을 "지금이 끊기 좋은 지점입니다"라는 단정으로 relay 했다(사용자 보고).
# 다음 알림 지점을 함께 알려 이 안내가 반복 잔소리가 아님을 드러낸다.
{
    echo "--- MangoLove 세션 예산: 컨텍스트 $((CTX / 1000))K 토큰 (안내 지점 $((BUCKET / 1000))K, $NEXT_NOTE) ---"
    echo "    컨텍스트가 커질수록 매 턴 그 전체를 다시 보내므로 턴당 비용이 그만큼 커집니다."
    echo "    작업이 한 단락 끝났다면 끊는 편이 낫고, 진행 중이면 그대로 이어가면 됩니다."
    echo "    판단은 사용자 몫입니다. 지금 끊어야 한다고 단정하지 말고 선택지만 전달하세요."
    echo "      - 다음 작업이 무관하면          : /clear"
    echo "      - 같은 작업을 이어가면          : /compact <초점>"
    echo "      - 잘못된 방향을 되돌리는 것이면 : /rewind (기존 캐시를 유지하는 유일한 경로)"
    echo "    끊기 전에 .progress.md 에 상태를 남기면 mangolove resume 으로 이어갈 수 있습니다."
    echo "    이건 차단이 아니라 안내입니다. 계속 진행해도 됩니다(같은 지점에서 다시 알리지 않습니다)."
} >&2

_record_efficacy record-block budget "ctx-$((BUCKET / 1000))k"

exit 2
