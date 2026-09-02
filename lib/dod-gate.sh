#!/usr/bin/env bash
# ─────────────────────────────────────────────
# MangoLove: DoD gate (Stop hook)
#
# 선언한 DoD 를 모델의 자기채점이 아니라 결정적 게이트로 닫는다(best-practices #1: Stop hook).
# bare mangolove 세션에 Stop 훅으로 런타임 주입된다(claude --settings), MANGOLOVE_DOD_GATE=on 일 때만.
# Stop 은 매 턴 종료마다 발화하나, DoD 가 외부화되지 않았으면 즉시 통과하므로 idle 비용이 없다.
#
# 계약(stdin=JSON, exit code 로 제어):
#   ./.mangolove/dod.sh 없음        → exit 0  (allow stop: DoD 미외부화)
#   dod.sh 가 남의 세션 소유         → exit 0  (안내만, 실행도 삭제도 하지 않음. 아래 "소유권")
#   dod.sh 있고 전 항목 PASS        → dod.sh + 상태 제거 → exit 0 (게이트 충족, allow)
#   dod.sh 있고 하나라도 FAIL       → 시도++, 실패 출력 stderr → exit 2 (block: 모델이 계속 수정)
#   시도가 상한에 닿음              → 상태를 released 로 표시 → exit 0 + 경고 (무한루프 backstop)
#
# 소유권(이 게이트가 남의 세션을 인질로 잡지 않게 하는 장치):
#   dod.sh 경로는 세션이 아니라 프로젝트에 매여 있어(./.mangolove/dod.sh), 같은 cwd 에서 도는
#   모든 세션이 파일 하나를 공유한다. 실측 사고: 조사만 한 세션이 다른 세션의 DoD 를 물려받아
#   빌드까지 돌린 뒤 "커밋되지 않은 변경 있음"으로 차단됐고, 그 변경은 남의 소유라 해결할
#   수도 없었다. 그래서 **처음 평가하는 세션이 소유자로 기록**되고, 같은 내용의 dod.sh 를
#   만난 다른 세션은 안내 한 줄만 내고 통과한다. 내용이 바뀌면 새 소유자로 갱신하므로
#   같은 세션이 DoD 를 다시 쓰는 정상 흐름은 막지 않는다.
#   (review-gate.sh 의 원장 스탬프와 같은 발상이다.)
#
#   알려진 한계 두 가지. 둘 다 "차단하지 않는" 방향이라 무관한 세션을 막는 실패보다 안전하다.
#   1) --resume 으로 session_id 가 바뀌면 자기 DoD 를 남의 것으로 보고 건너뛴다.
#   2) 소유자 세션이 죽으면 그 dod.sh 는 회수되지 않는다. 이후 세션들은 매 턴 안내 한 줄을
#      보며 통과한다(차단은 아니다). 자동 회수(mtime 임계 등)를 넣지 않은 것은 의도다:
#      시간 휴리스틱으로 남의 DoD 를 되가져오는 경로는 곧 남의 DoD 로 차단되는 경로다.
#      정리는 사람이 한다: rm .mangolove/dod.sh
#
# 시도 상한 두 겹(둘 다 넘기면 해제):
#   MANGOLOVE_DOD_MAX_ATTEMPTS (기본 3)  같은 DoD 를 몇 번까지 미는가. 내용이 바뀌면 0 으로 돌아간다.
#   그 3배                                DoD 를 바꿔 가며 실패해도 반드시 끝나게 하는 누적 상한.
#   (누적 상한이 없으면 매 턴 dod.sh 를 새로 쓰는 흐름에서 backstop 이 영영 발화하지 않는다.)
#
# 우회(감사됨): MANGOLOVE_SKIP_DOD=1
#
# 모델은 완료를 주장하기 직전 DoD 를 실행형 체크로 ./.mangolove/dod.sh 에 외부화한다(system-prompt 참조).
# ─────────────────────────────────────────────
set -uo pipefail

# 스크립트 위치는 **cd 전에** 확정한다. 훅은 stdin 의 cwd 로 이동하므로, 이동한 뒤에
# 상대 경로(bash lib/dod-gate.sh)로 계산하면 빈 값이 되고 효능 기록이 조용히 죽는다.
# $(cd .. && pwd) 대신 파라미터 확장으로 푼다: 매 턴 도는 훅이라 포크를 하나도 안 늘린다.
case "${BASH_SOURCE[0]}" in
    /*)  GATE_DIR="${BASH_SOURCE[0]%/*}" ;;
    */*) GATE_DIR="$PWD/${BASH_SOURCE[0]%/*}" ;;
    *)   GATE_DIR="$PWD" ;;
esac

MAX_ATTEMPTS="${MANGOLOVE_DOD_MAX_ATTEMPTS:-3}"
# 10# 로 강제 십진 해석: "08" 은 숫자 검사를 통과하고도 8진수로 읽혀 산술을 깨뜨린다
# (그러면 MAX_TOTAL 이 대입되지 않고 set -u 가 훅을 죽인다: 게이트가 조용히 꺼진다).
case "$MAX_ATTEMPTS" in
    ''|*[!0-9]*) MAX_ATTEMPTS=3 ;;
    *) MAX_ATTEMPTS=$((10#$MAX_ATTEMPTS)); [ "$MAX_ATTEMPTS" -ge 1 ] || MAX_ATTEMPTS=3 ;;
esac
MAX_TOTAL=$((MAX_ATTEMPTS * 3))

DOD="./.mangolove/dod.sh"
# 상태 파일 한 줄: "<시도|released>\t<누적 시도>\t<session_id>\t<dod.sh 해시>".
# 소유권을 **새 파일이 아니라 이 파일에** 담는 이유: 이 파일은 이미 어느 레포에서든 무시되고
# 있다. 새 파일은 무시 목록에 늦게 추가돼, 하필 "커밋되지 않은 변경 없음" 류의 DoD 를
# 게이트 자신이 깨뜨린 전례가 있다(_ml_seed_gitignore 주석 참조).
# 옛 포맷(정수만)은 나머지 필드가 빈 값으로 파싱되어 버전 분기 없이 그대로 호환된다.
STATE="./.mangolove/.dod-gate-attempts"

# ── stdin JSON 에서 문자열 필드 하나를 꺼낸다 (jq 비의존).
# bash 정규식으로 푼다: 이 훅들은 매 턴/매 Bash 호출마다 돌아서, grep 파이프라인의
# 포크 5개가 그대로 상시 비용이 된다. 실측 8KB payload 기준 7.2ms -> 1.1ms.
# 두 게이트가 이 함수를 각자 한 벌씩 갖는 것은 의도다(서로 source 하지 않는다).
# 두 사본이 갈라지지 않는지는 tests/dod-gate.bats 의 경계 테스트가 강제한다.
_json_str() {
    local re="\"$2\"[[:space:]]*:[[:space:]]*\"(([^\"\\\\]|\\\\.)*)\""
    [[ "$1" =~ $re ]] && printf '%s' "${BASH_REMATCH[1]}"
    return 0
}

# 훅은 다른 cwd 에서 실행될 수 있으므로 stdin 의 cwd 로 이동해 프로젝트를 정확히 식별한다.
# read -d '' 는 builtin 이라 cat 의 포크를 없앤다. NUL 이 없으면 1 을 반환하나
# 그때도 읽은 내용은 input 에 담긴다.
IFS= read -r -d '' input || true
cwd_field="$(_json_str "$input" cwd)"
if [ -n "$cwd_field" ] && [ -d "$cwd_field" ]; then
    cd "$cwd_field" 2>/dev/null || true
fi

# DoD 가 외부화되지 않았으면 게이트 비활성: 즉시 통과(무비용).
# 이 아래로는 DoD 가 실재할 때만 도는 코드다. 매 턴 발화하는 훅이므로 위쪽을 얇게 유지한다.
[ -f "$DOD" ] || exit 0

# 감사되는 우회구: strict.md 는 우회를 금지하나 물리적으로는 존재한다.
if [ "${MANGOLOVE_SKIP_DOD:-}" = "1" ]; then
    echo "MangoLove DoD gate: MANGOLOVE_SKIP_DOD=1 (게이트 우회, 감사 대상)" >&2
    exit 0
fi

SESSION="$(_json_str "$input" session_id)"

# .mangolove/ 는 프로젝트가 버전관리할 수도 있는 디렉토리다(.mangolove/hooks/ 는 감사 대상).
# 그러니 통째로 무시하지 않고, 게이트가 만드는 **일시 파일만** 자기 자신을 무시하게 한다.
# 없으면 만들고, 있으면 **빠진 줄만 덧붙인다**: "없을 때만 생성"이던 옛 동작은 먼저 심은
# 게이트가 이겨서, 나중에 추가된 패턴(.review-skip)이 그 레포에서 영영 누락됐다. 누락된
# 일시 파일은 untracked 로 떠서 "커밋되지 않은 변경 없음" 류의 DoD 를 게이트가 깨뜨린다.
# (review-gate.sh 에 같은 함수가 있다. 훅 스크립트는 서로를 source 하지 않는다: 한 파일이
#  없거나 깨져도 다른 게이트가 같이 죽지 않게 하는 기존 설계를 따른다. 두 사본이 같은 목록을
#  심는지는 tests/dod-gate.bats 의 경계 테스트가 강제한다.)
_ml_seed_gitignore() {
    local d="./.mangolove" f p
    [ -d "$d" ] || return 0
    f="$d/.gitignore"
    if [ ! -f "$f" ]; then
        {
            echo "# MangoLove 게이트의 일시 상태 (자동 생성). 레포 내용이 아니다."
            echo "# 이 파일 자신도 무시한다. 게이트가 어느 머신에서든 다시 만든다."
        } > "$f" 2>/dev/null || return 0
    fi
    # 마지막 줄에 개행이 없으면 append 가 그 줄에 붙어 패턴 두 개를 한꺼번에 무효화한다
    # (`dod.sh` + `.dod-gate-attempts` → `dod.sh.dod-gate-attempts`). 손으로 쓴 파일에서 실제로 난다.
    if [ -s "$f" ] && [ -n "$(tail -c1 "$f" 2>/dev/null)" ]; then
        printf '\n' >> "$f" 2>/dev/null || return 0
    fi
    for p in .gitignore dod.sh .dod-gate-attempts .review-ledger .review-ledger.base .review-skip; do
        grep -qxF "$p" "$f" 2>/dev/null || printf '%s\n' "$p" >> "$f" 2>/dev/null || true
    done
}

# dod.sh 내용 해시: 소유권이 "이 DoD"에 매이게 한다. 내용이 바뀌면 다른 DoD 다.
# 어느 도구도 없으면 **빈 값**을 낸다: "해시 불가"는 "같은 DoD"가 아니라 "소유권 판정 불가"이고,
# 그때는 예전처럼 평가하는 쪽이 맞다(상수를 돌려주면 모든 DoD 가 같은 것이 돼 게이트가 조용히 꺼진다).
_dod_hash() {
    local line
    if line="$(sha256sum "$1" 2>/dev/null)" || line="$(shasum -a 256 "$1" 2>/dev/null)"; then
        printf '%s' "${line%% *}"
    elif line="$(cksum "$1" 2>/dev/null)"; then
        line="${line% *}"            # 파일명 제거 → "<crc> <size>"
        printf '%s' "${line/ /-}"
    fi
}

# 효능 원장 기록(비차단, 실패무시). 차단은 block, 게이트가 손을 뗀 시점은 skip 이다.
# 둘을 섞으면 통과가 차단으로 세져 효능 수치가 부푼다(efficacy-recorder.sh 의 절대원칙).
_record_efficacy() {
    local rec="$GATE_DIR/efficacy-recorder.sh"
    [ -f "$rec" ] || return 0
    bash "$rec" "$1" dod-gate "$2" 2>/dev/null || true
}

STATUS=""; TOTAL=0; OWNER=""; OWNED_HASH=""
_read_state() {
    [ -f "$STATE" ] || return 0
    local t=""
    IFS=$'\t' read -r STATUS t OWNER OWNED_HASH < "$STATE" 2>/dev/null || true
    case "$t" in ''|*[!0-9]*) t="" ;; esac
    # 옛 포맷(정수만)에는 누적치가 없다. 그 값이 곧 누적치였다.
    if [ -z "$t" ]; then
        case "$STATUS" in ''|*[!0-9]*) t=0 ;; *) t="$STATUS" ;; esac
    fi
    TOTAL="$t"
}

# 상태를 현재 세션/해시 소유로 기록한다. $1 = 이 DoD 의 시도 횟수 또는 "released", $2 = 누적 시도.
# 전역 SESSION, HASH 를 함께 읽는다(둘 다 이 함수 위에서 대입된다).
_write_state() {
    mkdir -p ./.mangolove 2>/dev/null || return 0
    _ml_seed_gitignore
    printf '%s\t%s\t%s\t%s' "$1" "$2" "$SESSION" "$HASH" > "$STATE" 2>/dev/null || true
}

HASH="$(_dod_hash "$DOD")"
_read_state
same_dod=0
[ -n "$HASH" ] && [ "$OWNED_HASH" = "$HASH" ] && same_dod=1

# ① 소유권: 같은 DoD 인데 소유자가 다른 세션이면 남의 것이다. 실행도 삭제도 하지 않는다.
#    (소유자가 돌아와 통과시킬 여지를 남긴다. 지우면 원 세션이 근거를 잃는다.)
if [ "$same_dod" = 1 ] && [ -n "$OWNER" ] && [ -n "$SESSION" ] && [ "$OWNER" != "$SESSION" ]; then
    echo "MangoLove DoD gate: 다른 세션(${OWNER})이 남긴 ./.mangolove/dod.sh 입니다. 이 세션은 건너뜁니다." >&2
    _record_efficacy record-skip foreign
    exit 0
fi

# ② 해제를 이미 알린 DoD 는 같은 내용인 한 조용히 통과시킨다.
#    해제 시 카운터만 지우던 옛 동작은 다음 턴에 0 으로 되돌아가 또 상한만큼 차단했다.
if [ "$same_dod" = 1 ] && [ "$STATUS" = "released" ]; then
    exit 0
fi

# 해제를 알린 뒤 **새 DoD** 가 오면 새 에피소드다: 누적치까지 0 으로 되돌린다.
# 이게 없으면 누적 상한에 한 번 닿은 프로젝트에서 게이트가 영구히 죽는다. 해제 경로는
# dod.sh 를 실행하지 않으므로 상태를 지우는 통과 경로에 영영 닿지 못하고, 누적치는 줄지
# 않는다. 그 뒤로는 새 세션이 새 DoD 를 써도 조용히 통과한다(검증되지 않은 채로).
if [ "$same_dod" = 0 ] && [ "$STATUS" = "released" ]; then
    TOTAL=0
fi

# 이 DoD 의 시도 횟수. 내용이 바뀌었으면 0 에서 다시 시작한다: 새 DoD 는 자기 몫의 예산을 받는다.
# (해시가 없는 옛 포맷은 판정할 수 없으므로 예전처럼 카운터를 이어받는다.)
ATTEMPTS=0
if [ "$same_dod" = 1 ] || [ -z "$OWNED_HASH" ]; then
    case "$STATUS" in ''|*[!0-9]*) ATTEMPTS=0 ;; *) ATTEMPTS="$STATUS" ;; esac
fi

# ③ 무한루프 backstop: 상한에 닿으면 게이트를 놓아준다(자체 종료 보장).
#    dod.sh 는 미충족 근거로 남기고, 상태만 released 로 표시해 같은 DoD 의 재차단을 막는다.
if [ "$ATTEMPTS" -ge "$MAX_ATTEMPTS" ] || [ "$TOTAL" -ge "$MAX_TOTAL" ]; then
    _write_state released "$TOTAL"
    if [ "$ATTEMPTS" -ge "$MAX_ATTEMPTS" ]; then
        why="같은 DoD 를 ${ATTEMPTS}회 시도했으나 미통과"
    else
        why="DoD 를 바꿔 가며 누적 ${TOTAL}회 시도했으나 미통과"
    fi
    {
        echo "--- MangoLove DoD gate: 게이트 해제(무한루프 방지). ${why}. 수동 확인 필요. ---"
        echo "    dod.sh 는 근거로 남깁니다: bash .mangolove/dod.sh 로 무엇이 걸리는지 볼 수 있습니다."
        echo "    새 DoD 를 쓰면 재무장합니다. 상태까지 지우려면: rm .mangolove/.dod-gate-attempts"
    } >&2
    _record_efficacy record-skip released
    exit 0
fi

# ④ DoD 체크 실행. 실행 **전에** 소유권을 찍는다: 실제 DoD 는 빌드/테스트라 몇 분씩 걸리고,
#    그 사이 다른 세션의 Stop 이 발화하면 같은 빌드를 한 번 더 돌린 뒤 소유권까지 가져간다
#    (그러면 정작 DoD 를 쓴 세션이 자기 DoD 를 남의 것으로 보고 영영 건너뛴다).
_write_state "$ATTEMPTS" "$TOTAL"
out="$(bash "$DOD" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
    rm -f "$DOD" "$STATE"
    echo "MangoLove DoD gate: DoD 전 항목 통과 ✓" >&2
    exit 0
fi

# 실패 → 시도 증가 후 block. 소유자는 현재 세션으로 (재)기록된다.
ATTEMPTS=$((ATTEMPTS + 1))
TOTAL=$((TOTAL + 1))
_write_state "$ATTEMPTS" "$TOTAL"
{
    echo "--- MangoLove DoD gate: DoD 미통과 (시도 ${ATTEMPTS}/${MAX_ATTEMPTS}, 누적 ${TOTAL}/${MAX_TOTAL}), 완료를 주장하기 전에 아래를 해결하세요 ---"
    printf '%s\n' "$out" | tail -30
} >&2

_record_efficacy record-block fail

exit 2
