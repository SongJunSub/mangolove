#!/usr/bin/env bash
# ─────────────────────────────────────────────
# MangoLove: Review gate (트랙별 필수 리뷰의 결정적 강제)
#
# 왜 존재하나: 방법론은 Medium 이상 변경에 리뷰 단계를 요구하지만 그 요구는 산문이라
# 확률적으로만 지켜졌다. 실제 관측된 실패 모드는 "트랙을 선언하고 → 리뷰를 생략하고 →
# 사후에 고백하며 → 지금 돌릴까요라고 되묻는" 것이다. 사용자가 요청한 적 없는 결정을
# 사후에 떠넘기는, 가능한 선택지 중 최악이다.
# strict.md 의 신뢰성 게이트 원칙("강제 표현이 잦은 규칙은 hook 으로 옮겨라")을 리뷰
# 의무에 적용해, push 경계에서 코드가 결정한다.
#
# 경계는 commit 이 아니라 push 다. 리뷰가 의미를 갖는 단위는 "작업이 이 머신을 떠나는
# 시점"이기 때문이다. 근거가 세 개인데, 소음 하나만으로는 이 이동을 정당화하지 못한다.
#
#   1. 소음: 커밋 경계에서 차단 39건 중 23건(59%)이 10분 내 재차단이었다. 커밋은 잦고
#      증분적이라("잘게, 자주" 가 이 레포 규약) 커밋마다 리뷰를 요구하면 같은 작업이
#      계속 다시 막힌다. **다만 이 항목만이라면 아래 커버리지(내용 주소)로도 풀린다.**
#   2. 머지: 커밋 경계는 머지 커밋의 staged diff 를 "이 커밋이 새로 쓴 코드"로 본다.
#      다른 브랜치에서 이미 검토된 13개 파일이 Large 로 계산돼 막혔다(실제 사례).
#      커버리지로는 못 푼다: 그 파일들은 이 세션의 어떤 리뷰도 본 적이 없다.
#      push 범위의 merge base 가 특별처리 없이 해결한다.
#   3. 누적 우회: 커밋 경계에서는 큰 작업을 Trivial 커밋 N 개로 쪼개면 전부 통과한다.
#      push 범위는 커밋 개수와 무관하므로 합쳐서 계산된다.
#
# 2와 3은 경계를 옮겨야만 닫힌다. 그래서 커버리지와 경계 이동을 함께 한다.
#
# 범위는 "이 push 로 원격에 처음 가는 커밋이 더하는 변경"이다(_push_scope). 기준 브랜치를
# 추정하지 않고 git 에게 묻는다. 그래서 두 가지가 특별처리 없이 해결된다:
#   - 이미 원격에 있는 브랜치를 머지해도 그 내용은 범위에서 빠진다
#   - 원격에 없는(= 어디서도 공유되지 않은) 브랜치를 머지하면 그 내용은 범위에 남는다
#     (미검토 코드가 머지로 숨지 못한다)
# 그리고 범위는 커밋 개수와 무관하므로, 작은 커밋으로 쪼개 누적 우회하는 길이 막힌다.
#
# 두 개의 훅으로 동작한다 (bare mangolove 세션에 claude --settings 로 주입):
#   PostToolUse(matcher=Skill) → review-gate.sh record
#       실제로 실행된 스킬만 원장에 남는다. 모델의 자기보고가 아니라 도구 호출 사실이다.
#       동시에 그 시점 작업 내용을 blob 해시로 스냅샷한다(아래 "커버리지").
#   PreToolUse(matcher=Bash)   → review-gate.sh pretooluse
#       git push 일 때만 발화(명령이 가리키는 레포마다). 범위에서 리뷰가 이미 본 내용을 뺀
#       잔여를 impact-score.sh 로 점수화해, 필수 리뷰가 원장에 있는지 대조하고
#       없으면 push 를 차단(exit 2)한다.
#
# 커버리지(왜 blob 해시인가): 세션 원장만 대조하면 "리뷰 한 번 돌리고 그 뒤로 10커밋 더
# 쓰고 push" 가 통과한다. 리뷰가 실제로 본 파일 내용을 해시로 붙잡아 두어야, 그 뒤에
# 새로 쓴 것만 잔여로 남는다. 내용이 같으면 커밋을 몇 개로 쪼개 담았든 통과한다.
# 무엇을 봤는지는 스킬 호출의 args 로 좁힌다(_coverage_scope 참조): 원격 PR 이나 다른
# worktree 를 리뷰한 스킬이 이 트리를 통과시키면 안 되기 때문이다.
#
# 트랙이 Trivial/Small 이면 아무 것도 요구하지 않는다: 사소한 변경에 무거운 절차를
# 씌우지 않는 것이 이 게이트의 절반이다(과대 판정도 실패다).
#
# 계약:
#   review-gate.sh record       stdin=PostToolUse JSON. 항상 exit 0 (게이트가 작업을 막지 않는다).
#   review-gate.sh pretooluse   stdin=PreToolUse JSON. 통과 exit 0 / 차단 exit 2.
#   review-gate.sh prepush      .githooks/pre-push 용. 통과 exit 0 / 차단 exit 1.
#   review-gate.sh required <track> <db> <auth> <ext>   필수 스킬 목록 출력: 정책 단일 출처.
#   review-gate.sh status [ref] 사람용: 계산된 트랙 + 원장 + 부족분.
#
# 우회(감사됨): .mangolove/.review-skip 파일(1회용, 세션 도중 가능)
#               또는 mangolove 실행 전에 export 한 MANGOLOVE_SKIP_REVIEW=1
#               (훅은 Claude Code 프로세스 환경에서 뜨므로 명령 앞 VAR=1 은 닿지 않는다)
# 비활성: MANGOLOVE_REVIEW_GATE=off (훅 자체가 주입되지 않음)
# ─────────────────────────────────────────────
set -uo pipefail

# 스크립트 위치는 **cd 전에** 확정한다(훅은 stdin 의 cwd 로 이동한다).
# 파라미터 확장으로 푼다: 이 훅은 Bash 도구 호출마다 도므로 포크를 늘리지 않는다.
case "${BASH_SOURCE[0]}" in
    /*)  GATE_DIR="${BASH_SOURCE[0]%/*}" ;;
    */*) GATE_DIR="$PWD/${BASH_SOURCE[0]%/*}" ;;
    *)   GATE_DIR="$PWD" ;;
esac
IMPACT="$GATE_DIR/impact-score.sh"

# ── 게이트 상태는 워킹트리에 두지 않는다 ────────────────
# 왜: .gitignore 는 `git add -f` 를 막지 못한다. 적대적 브랜치가 원장과 커버리지를 위조해
# 커밋해 두면, 그 브랜치를 checkout 한 사람의 워킹트리에 그대로 배달된다. 터미널 경로
# (do_prepush)는 세션 ID 가 없어 디스크의 원장을 그대로 믿으므로, **리뷰를 한 번도 돌리지
# 않고 공유가 통과한다**(실증됨: 위조 원장을 실은 브랜치에서 종료코드 0).
# .git/ 아래는 checkout 이 절대 쓰지 않으므로 이 경로 자체가 사라진다. 링크드 worktree 에서는
# git-dir 이 worktree 별로 갈리는데, 리뷰 상태도 worktree 별인 것이 맞다.
# 비-git 디렉토리에서는 빈 값이 되고, 그때는 어차피 게이트가 fail-open 한다.
_ml_state_dir() {
    local g; g="$(git rev-parse --absolute-git-dir 2>/dev/null)" || return 0
    [ -n "$g" ] || return 0
    printf '%s/mangolove' "$g"
}
# 경로는 **cd 이후에** 확정해야 한다. 훅은 stdin 의 cwd 로 이동하므로, 로드 시점에 계산하면
# 엉뚱한 레포의 .git 을 가리킨다. 여기서는 기본값만 두고 _ml_init_state 로 다시 잡는다.
STATE_DIR=""

# 추적되는 게이트 상태는 브랜치가 실어 온 위조본이다. 이 파일들은 일시 상태라 절대
# 추적되지 않으며, 추적된 사본이 있다는 것 자체가 변조 신호다.
_ml_tracked() { git ls-files --error-unmatch -- "$1" >/dev/null 2>&1; }

LEDGER_REL=".mangolove/.review-ledger"
# 원장과 커버리지는 세션이나 HEAD 로 무효화하지 않는다. 세션으로 무효화하던 시절, 같은 worktree 에서
# 다른 세션이 스킬을 부르면 이 세션이 돌린 리뷰가 통째로 지워져 리뷰를 다 돌린 push 가 막혔다.
# 커버리지는 내용 주소(blob 해시)라, 리뷰가 본 내용과 올리는 내용이 같으면 누가 언제 돌렸든 리뷰된 것이다.
# 리뷰가 본 내용: "<스킬>\t<blob 해시>\t<경로>" 줄들. 내용 주소 기준이라 세션과 무관하다.
COVERED_REL=".mangolove/.review-covered"
NOSCOPE_REL=".mangolove/.review-noscope"
# 우회를 방금 썼다는 표시(찍힌 시각). 게이트 둘이 직렬로 걸리는데(에이전트 경로,
# 터미널 경로) 앞쪽이 마커를 소비하면 뒤쪽이 근거 없이 다시 막아 한 번의 공유에 우회가
# 두 번 든다. 시도한 대안과 그 결말:
#   - "마지막 게이트가 소비한다": 하위 게이트가 없는 경로(gh pr create)나 실패한 push 에서
#     마커가 살아남아 1회용이 아니게 된다. 남의 pre-push(husky 등)도 우리 것으로 셌다.
#   - "push sha 를 식별자로": PreToolUse 는 **명령 실행 전에** 발화하므로,
#     `git add && git commit && git push` 한 줄에서 찍히는 HEAD 가 실제 push 되는 sha 와
#     다르다. 가장 흔한 형태에서 깨진다(실증됨).
# 그래서 아주 좁은 시간 창으로 둔다. 남는 한계: 우회 직후 창 안에 들어온 **다른** push 도
# 이어받는다. 창이 한 번의 git push 안에서 두 훅이 이어 도는 간격(보통 1초 미만)만
# 덮으면 되므로 좁게 잡는다.
USED_REL=".mangolove/.review-skip.used"
SKIP_HANDOFF_SECONDS=20
# 세션 도중 쓸 수 있는 1회용 우회 파일. 환경변수 우회는 훅에 닿지 않기 때문에 필요하다.
# 이것만은 워킹트리에 남긴다: 사람이 직접 touch 하는 경로라 안내문에 적히기 때문이다.
# 대신 추적된 사본은 신뢰하지 않는다(_ml_tracked).
SKIP_REL=".mangolove/.review-skip"

# cwd 가 정해진 뒤 상태 경로를 확정한다. 호출자가 git-dir 을 이미 구했으면 넘겨 git 호출을 아낀다.
# git-dir 을 못 구하면(비-git) 워킹트리 기본값을 그대로 쓰는데, 그 경우는 어차피 게이트가 fail-open 한다.
_ml_init_state() {
    local top="${2:-}"
    STATE_DIR="${1:+$1/mangolove}"
    [ -n "$STATE_DIR" ] || STATE_DIR="$(_ml_state_dir)"
    [ -n "$STATE_DIR" ] || return 0
    # 우회 파일은 워크트리 루트에 고정한다. cwd 상대로 두면 하위 디렉토리에서 남긴 우회를 루트에서 판정하는
    # 게이트가 못 찾아, 안내대로 우회했는데 다시 막혔다.
    [ -n "$top" ] || top="$(git rev-parse --show-toplevel 2>/dev/null)"
    [ -n "$top" ] && SKIP_REL="$top/.mangolove/.review-skip"
    LEDGER_REL="$STATE_DIR/.review-ledger"
    COVERED_REL="$STATE_DIR/.review-covered"
    NOSCOPE_REL="$STATE_DIR/.review-noscope"
    USED_REL="$STATE_DIR/.review-skip.used"
}

# .mangolove/ 는 프로젝트가 버전관리할 수도 있는 디렉토리다(.mangolove/hooks/ 는 감사 대상).
# 그러니 통째로 무시하지 않고, 게이트가 만드는 **일시 파일만** 자기 자신을 무시하게 한다.
# 없으면 만들고, 있으면 **빠진 줄만 덧붙인다**: "없을 때만 생성"이던 옛 동작은 먼저 심은
# 게이트가 이겨서, 나중에 추가된 패턴(.review-skip)이 그 레포에서 영영 누락됐다. 누락된
# 일시 파일은 untracked 로 떠서 "커밋되지 않은 변경 없음" 류의 DoD 를 게이트가 깨뜨린다.
# (review-gate.sh 에 같은 함수가 있다. 훅 스크립트는 서로를 source 하지 않는다: 한 파일이
#  없거나 깨져도 다른 게이트가 같이 죽지 않게 하는 기존 설계를 따른다. 두 사본이 같은 목록을
#  심는지는 tests/dod-gate.bats 의 경계 테스트가 강제한다.)
# 게이트가 쓰는 상태 파일이 심볼릭 링크면 쓰지 않는다.
# 적대적 브랜치가 .mangolove/.review-covered 를 레포 밖(셸 rc, 훅 스크립트 등)으로 향하는
# 링크로 커밋해 두면, 리뷰 스킬을 한 번 돌리는 것만으로 그 파일에 공격자가 정한 경로 문자열이
# append 된다(커버리지 줄에 파일 경로가 그대로 들어가므로 내용까지 공격자 통제다).
# 링크면 지우고 정규 파일로 다시 만든다: 게이트 상태는 언제든 재생성 가능한 일시 파일이다.
_ensure_regular_file() {
    local f="$1"
    if [ -L "$f" ]; then
        rm -f "$f" 2>/dev/null || return 1
    fi
    return 0
}

_ml_seed_gitignore() {
    local d="${SKIP_REL%/*}" f p
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
    for p in .gitignore dod.sh .dod-gate-attempts .review-skip; do
        grep -qxF "$p" "$f" 2>/dev/null || printf '%s\n' "$p" >> "$f" 2>/dev/null || true
    done
}


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
_cd_to_hook_cwd() {
    local c; c="$(_json_str "$1" cwd)"
    if [ -n "$c" ] && [ -d "$c" ]; then cd "$c" 2>/dev/null || true; fi
}

# 문자열이 push 모양인가(git 을 단어 경계로 잡고 옵션 토큰을 건너뛴 뒤 push 서브커맨드).
# 구조 파서가 git 낱말을 찾지 못한 명령에서만 쓰는 하한이다(_push_targets).
GIT_PUSH_RE='(^|[^[:alnum:]_])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-][^[:space:]]*)?)*[[:space:]]+push([[:space:]]|$)'
# heredoc 본문을 매칭 대상에서 뺀다. 게이트는 셸을 파싱하지 않고 명령 **문자열**을 보므로,
# `python3 - <<PY ... PY` 로 넘긴 스크립트 본문에 "git push" 라는 글자가 있으면 그것을
# 명령으로 오인해 무관한 작업을 막는다(실제로 다른 레포 작업 중에 반복해서 걸렸다).
#
# 다만 **셸이 소비하는 heredoc 은 벗기지 않는다**: `bash <<EOF ... EOF` 의 본문은 데이터가
# 아니라 실행되는 코드라, 벗기면 진짜 push 가 통째로 새어 나간다. 소비하는 명령이 셸인지로
# 가른다. 판별이 애매하면 벗기지 않는다(막는 쪽 = 안전한 쪽).
# 본문이 데이터인 소비자. 모르는 소비자는 벗기지 않는다(막는 쪽이 안전하다).
HEREDOC_DATA_SINKS='(^|[^[:alnum:]_/])(cat|tee|python|python3|node|jq|sed|awk|perl|ruby|php|tr|sort|head|tail|grep|diff|patch)([ \t]|$)'
_strip_heredocs() {
    printf '%s\n' "$1" | awk -v sink="$2" '
        {
            if (in_hd) {
                line = $0
                if (dash) sub(/^\t+/, "", line)
                if (line == marker) { in_hd = 0; print; next }
                if (strip) next
                print; next
            }
            # << 를 **따옴표 밖에서만** 찾는다. 텍스트만 보면 echo "see <<EOF" 의 <<EOF 를
            # 진짜 리다이렉션으로 오인하고, 닫는 마커가 영영 안 나오므로 그 뒤 명령이 통째로
            # 사라진다(실증됨: 무해한 한 줄을 앞에 붙이면 두 훅이 모두 침묵했다).
            n = length($0); inq = ""; tok = ""
            for (i = 1; i <= n; i++) {
                c = substr($0, i, 1)
                if (inq != "") { if (c == inq) inq = ""; continue }
                if (c == "\"" || c == "\047") { inq = c; continue }
                if (c == "<" && substr($0, i + 1, 1) == "<") {
                    rest = substr($0, i + 2)
                    if (match(rest, /^-?[ \t]*("[^"]+"|\047[^\047]+\047|[A-Za-z_][A-Za-z0-9_]*)/)) {
                        tok = substr(rest, RSTART, RLENGTH)
                    }
                    break
                }
            }
            if (tok != "") {
                dash = (tok ~ /^-/)
                m = tok
                sub(/^-?[ \t]*/, "", m)
                gsub(/["\047]/, "", m)
                marker = m
                in_hd = 1
                # 본문을 벗기는 것은 **데이터 싱크로 알려진 소비자일 때만**이다. 셸만
                # 제외했더니 psql/mysql/ssh 처럼 본문을 실행하는 소비자의 heredoc 이
                # 검사에서 사라졌다(DROP TABLE, rm -rf 가 통과했다). 모르는 소비자는
                # 남긴다: 막는 쪽이 안전하다.
                strip = ($0 ~ sink) ? 1 : 0
            }
            print
        }'
}

# 원격 트렁크(origin/HEAD, 없으면 origin/main|master). 빈 출력 = 정할 수 없음.
# 판정 범위의 기준으로 쓰지 않는다(아래 _push_scope). 원격과 공통 조상이 없는 이력의 폴백이다.
_default_base() {
    local def c
    def="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"
    if [ -z "$def" ]; then
        for c in origin/main origin/master; do
            if git rev-parse --verify --quiet "$c" >/dev/null 2>&1; then def="$c"; break; fi
        done
    fi
    printf '%s' "$def"
}

# ── 판정 범위: 이 push 로 원격에 처음 가는 커밋이 더하는 변경 ──────────────
# 기준 브랜치를 추정하지 않는다. 추정하던 시절의 오탐이 전부 여기서 나왔다.
#   - origin/HEAD(대개 main) 기준: develop 이나 통합 브랜치(HUB2-312)에서 딴 작업은 그 기준
#     브랜치에만 있는 **남의 커밋**까지 범위에 들어온다. 그 파일들은 이 트리의 어떤 리뷰도 볼
#     수 없어서(리뷰는 자기 변경만 본다) 리뷰를 몇 번 다시 돌려도 풀리지 않는 차단이 된다.
#     2026-09-10 하루에 CRS-1030/1031(develop 에만 있는 17개), HUB2-380/390(HUB2-312 에만 있는
#     65~75개)이 전부 이것으로 막혔다.
#   - upstream 기준: 첫 push 의 -u 뒤에는 upstream 이 자기 원격 브랜치로 바뀌고, 명시
#     refspec(git push origin X)은 upstream 을 보지 않는다. rebase 뒤에는 옛 원격 브랜치와의
#     merge base 가 옛 분기점이라 그사이 develop 에 들어온 남의 커밋이 다시 범위에 들어온다.
#
# 대신 git 에게 묻는다. `<rev> --not --remotes` 는 어떤 원격 추적 ref 에도 없는 커밋, 즉 이
# push 로 처음 공유되는 커밋이다. 그 경계(원격이 이미 가진 부모)가 기준이다.
#   - 경계가 하나: <경계>...<rev> 가 곧 새 커밋들의 순변경이다.
#   - 경계가 여럿(원격 브랜치를 머지): **모든** 경계와 내용이 다른 파일만 새 것이다. 원격
#     브랜치에서 통째로 가져온 파일은 그 경계와 같아 빠지고, 충돌 해결로 새로 쓴 파일은 남는다.
#   - 새 커밋이 없음: 공유할 내용이 없다(<rev>...<rev>, 빈 범위).
#   - 원격과 공통 조상이 없음: 트렁크 기준으로 폴백한다. 원격 추적 ref 가 아예 없으면 정할
#     근거가 없으므로 빈 값(호출자가 fail-open 하고 감사를 남긴다).
# 원격에 없는 브랜치를 머지하면 그 커밋도 원격에 없으므로 범위에 남는다(미검토 코드가 머지로
# 숨지 못한다). 원격에 있다는 것은 그 push 가 이미 이 게이트를 지났다는 뜻이다.
#
# 결과는 전역으로 돌려준다(_coverage_scope 와 같은 이유: 경로 배열을 문자열에 싣지 않는다).
SCOPE_RANGE=""        # "<기준>...<rev>". 빈 값 = 정할 수 없음
SCOPE_PATHS=()        # 비면 범위 전체. 경계가 여럿일 때만 새 파일로 좁힌다
_push_scope() {
    local rev="${1:-HEAD}" exclude="${2:-}" out line b
    local bounds=() excl=()
    SCOPE_RANGE=""; SCOPE_PATHS=()
    [ -n "$(git for-each-ref --count=1 --format=x refs/remotes 2>/dev/null)" ] || return 0
    # pre-push 가 준 원격 sha 는 fetch 전이라 추적 ref 에 없을 수 있어 따로 뺀다.
    # ^ 는 --not 앞에 둔다: --not 뒤에서는 뜻이 뒤집혀 오히려 포함된다.
    if [ -n "$exclude" ] && git cat-file -e "${exclude}^{commit}" 2>/dev/null; then
        excl=("^$exclude")
    fi
    # rev 가 없으면 rev-list 가 실패한다(따로 검증하지 않는다).
    out="$(git rev-list --boundary "$rev" ${excl[@]+"${excl[@]}"} --not --remotes -- 2>/dev/null)" || return 0
    if [ -z "$out" ]; then SCOPE_RANGE="${rev}...${rev}"; return 0; fi
    while IFS= read -r line; do
        case "$line" in -*) bounds+=("${line#-}") ;; esac
    done <<EOF
$out
EOF

    case "${#bounds[@]}" in
        0)  b="$(_default_base)"
            [ -n "$b" ] && SCOPE_RANGE="${b}...${rev}"
            return 0 ;;
        1)  SCOPE_RANGE="${bounds[0]}...${rev}"
            return 0 ;;
    esac
    # 경계가 여럿: 모든 경계와 내용이 다른 파일만 새 것이다. git 결합 diff 가 정확히 그 집합을 준다.
    while IFS= read -r line; do
        [ -n "$line" ] && SCOPE_PATHS+=("$line")
    done < <(git -c core.quotePath=false diff --name-only "$rev" "${bounds[@]}" 2>/dev/null)
    if [ "${#SCOPE_PATHS[@]}" -eq 0 ]; then SCOPE_RANGE="${rev}...${rev}"; return 0; fi
    SCOPE_RANGE="${bounds[0]}...${rev}"
    return 0
}

# ── push 가 도는 레포와 올라가는 커밋 ────────────────────────────────
# 훅의 cwd 는 세션이 서 있는 곳일 뿐이다. `git -C <다른 레포> push`, `cd <다른 레포> && git push`,
# `W=<경로>; git -C "$W" push` 는 **다른 레포**를 올린다. cwd 로 판정하면 엉뚱한 레포의 범위와
# 원장을 본다(2026-09-10: crs 세션에서 crs-admin-web push 가 crs 기준으로 판정됐다).
#
# 명령 전체를 awk 하나로 한 번만 읽는다. 따옴표와 $( ) 밖의 연산자에서 단순 명령으로 가르고(따옴표를
# 무시하고 가르면 `git commit -m "wip; git push"` 의 메시지가 push 가 된다), 단순 명령마다 디렉토리
# 이동과 변수를 따라가 push 인자까지 푼다. 레포, dry-run/삭제 여부, refspec 을 서로 다른 토크나이저로
# 따로 읽으면 규칙이 갈라진다(한쪽만 변수를 풀어 조용히 샜다).
#
# 출력: 판정할 push 마다 "<디렉토리>\t<rev>". 입력 끝의 PARSER_END 줄까지 읽었으면 마지막에 "!\tEND"
# 를 낸다(앞 단계 어디서 죽어도 표시가 없어 호출자가 감사로 돌린다). git 도 셸도 못 찾았는데 문자열이
# push 모양이면 "?\t?" 를 낸다(호출자가 막지 않고 감사한다).
# 따라가는 것: cd/pushd, git -C(누적), NAME=값(export 포함), 명령 밖에서 정해진 환경변수, for NAME in
#   값들, ~, $HOME, $PWD, sh/bash -c(옵션과 래퍼가 붙어도), eval, $( ). 서브셸 ( ), 파이프라인,
#   백그라운드, $( ), sh -c 안의 cd 는 밖으로 새지 않게 한다. dry-run(-n)과 삭제(-d, :dst)는 내지 않는다.
# 풀 수 없는 것은 **바뀌지 않은 것으로 본다**: 풀 수 없는 cd/-C("$(git rev-parse --show-toplevel)",
#   cd -)는 디렉토리를 그대로 두고, 명령치환 refspec("$(git branch --show-current)")은 HEAD 로 본다.
#   흔한 형태가 세션 레포와 현재 브랜치를 가리키고, 옛 게이트도 같은 추정으로 판정했다(판정 불가로
#   통과시키면 미검토 push 가 샌다).
# LC_ALL=C: 바이트 단위로 돈다. UTF-8 로케일의 awk 는 잘못된 바이트열에서 멈춘다.
PARSER_END="#MANGOLOVE_PARSER_END"
_push_targets() {
    _strip_heredocs "$1" "$HEREDOC_DATA_SINKS" \
        | LC_ALL=C awk -v cwd="$2" -v home="$HOME" -v push_re="$GIT_PUSH_RE" \
              -v sink="$HEREDOC_DATA_SINKS" -v endmark="$PARSER_END" '
        BEGIN { U = "\001?"; S = "\034"; DIR = cwd; DEPTH = 0; SEEN = 0 }
        $0 == endmark { SEEN = 1; next }
        { if (sub(/\\$/, "")) buf = buf $0 " "; else buf = buf $0 "\n" }
        END { process(buf); if (SEEN) print "!\tEND" }

        # 따옴표와 $( ) 밖의 연산자에서 단순 명령으로 가르고, 가르는 즉시 순서대로 해석한다. 해석했으면 1.
        # $( ) 는 인용을 새로 시작한다: 바깥 "..." 안의 $( 에서도 따옴표와 괄호는 안쪽 기준으로 짝을 맞춘다.
        # $( ) 안에서 데이터 싱크가 받는 heredoc 은 본문을 읽지 않는다: 커밋 메시지 본문의 짝 안 맞는 따옴표,
        # 괄호, "git push" 글자가 해석을 흔들어 커밋 명령이 push 로 읽혔다(맨 바깥 본문은 _strip_heredocs 가 벗긴다).
        # 파이프라인(원소가 둘 이상), 백그라운드 &, 서브셸 ( ) 은 자식 셸에서 돌므로 그 안의 cd 는 밖으로
        # 새지 않는다. 원소가 { }, for, if 같은 복합 명령일 수 있어, 복합 명령 깊이마다 파이프라인 시작
        # 디렉토리를 기억했다가 끝에서 되돌린다. 리다이렉션의 & 와 | 는 연산자가 아니다(2>&1, &>, >|).
        function process(s,    n, i, c, nx, q, dp, qs, ist, cur, stk, sp, depth, pst, pip, hm, hd, e, t) {
            if (++DEPTH > 8) { DEPTH--; return 0 }
            n = length(s); cur = ""; q = ""; dp = 0; sp = 0; depth = 0; pst[0] = DIR; pip[0] = 0; hm = ""
            for (i = 1; i <= n; i++) {
                c = substr(s, i, 1); nx = substr(s, i + 1, 1)
                if (c == "\n" && hm != "") {
                    cur = cur c
                    while (i < n) {
                        e = index(substr(s, i + 1), "\n"); if (e == 0) { i = n; break }
                        t = substr(s, i + 1, e - 1); i += e
                        if (hd) sub(/^\t+/, "", t)
                        if (t == hm) break
                    }
                    hm = ""; continue
                }
                if (q == "\047") { cur = cur c; if (c == "\047") q = ""; continue }
                if (c == "\\") { cur = cur c nx; i++; continue }
                if (c == "$" && nx == "(") { qs[++dp] = q; q = ""; ist[dp] = length(cur) + 3; cur = cur "$("; i++; continue }
                if (c == ")" && dp > 0 && q == "") { q = qs[dp--]; cur = cur c; continue }
                if (c == "\047" || c == "\"") { if (q == "") q = c; else if (q == c) q = ""; cur = cur c; continue }
                if (c == "<" && nx == "<" && q == "" && dp > 0 && hm == "" && substr(cur, ist[dp]) ~ sink \
                    && match(substr(s, i + 2), /^-?[ \t]*("[^"]+"|\047[^\047]+\047|[A-Za-z_][A-Za-z0-9_]*)/)) {
                    hm = substr(s, i + 2, RLENGTH); hd = (hm ~ /^-/); sub(/^-?[ \t]*/, "", hm); gsub(/["\047]/, "", hm)
                    cur = cur "<<"; i++; continue
                }
                if (q != "" || dp > 0 || !index(";|&()\n", c)) { cur = cur c; continue }
                if ((c == "&" || c == "|") && (substr(s, i - 1, 1) ~ /[<>]/ || (c == "&" && nx == ">"))) { cur = cur c; continue }
                depth = run(cur, depth, pst, pip); cur = ""
                if (c == "|" && nx != "|") { pip[depth] = 1; if (nx == "&") i++; continue }
                if (c == "&" && nx != "&") pip[depth] = 1
                else if (c == "|" || c == "&") i++
                endpipe(depth, pst, pip)
                if (c == "(") stk[++sp] = DIR
                else if (c == ")" && sp > 0) { DIR = stk[sp--]; pst[depth] = DIR }
            }
            depth = run(cur, depth, pst, pip)
            endpipe(depth, pst, pip)
            DEPTH--
            return 1
        }
        # 단순 명령 하나를 해석한다. 앞에 이어진 복합 명령 키워드를 전부 훑어 깊이를 맞춘다
        # (`then {`, `do {` 의 { 를 놓치면 짝인 } 가 바깥 if 의 깊이를 닫아 엉뚱한 디렉토리로 되돌렸다).
        function run(cmd, depth, pst, pip,    T, m, k) {
            if (cmd !~ /[^ \t\n]/) return depth
            m = split(cmd, T, /[ \t\n]+/)
            for (k = 1; k <= m; k++) {
                if (T[k] == "" || T[k] ~ /^(then|do|else|elif|time|!)$/) continue
                if (T[k] ~ /^(\}|fi|done|esac)([0-9]*[<>&].*)?$/) { if (depth > 0) { endpipe(depth, pst, pip); depth-- }; continue }
                if (T[k] ~ /^(\{|if|for|while|until|case|select)$/) { depth++; pst[depth] = DIR; pip[depth] = 0; continue }
                break
            }
            simple(cmd)
            return depth
        }
        # 파이프라인이 끝났다. 원소가 둘 이상이었거나 백그라운드였으면 그 안의 cd 는 자식 셸의 것이다.
        function endpipe(depth, pst, pip) {
            if (pip[depth]) DIR = pst[depth]
            pip[depth] = 0; pst[depth] = DIR
        }
        # 셸 낱말 분리. 작은따옴표 안의 $ 는 확장하지 않도록 \002 로 표시해 둔다.
        # $( ) 안의 글자는 그대로 둔다(안쪽 명령을 subst 가 다시 해석한다): 짝만 안쪽 인용 기준으로 맞춘다.
        function words(s, W,    n, len, i, c, tok, q, has, dp, iq) {
            n = 0; tok = ""; q = ""; has = 0; dp = 0; iq = ""; len = length(s)
            for (i = 1; i <= len; i++) {
                c = substr(s, i, 1)
                if (dp > 0) {
                    tok = tok c
                    if (iq == "\047") { if (c == "\047") iq = ""; continue }
                    if (c == "\\") { tok = tok substr(s, i + 1, 1); i++; continue }
                    if (c == "\047" || c == "\"") { if (iq == "") iq = c; else if (iq == c) iq = ""; continue }
                    if (iq == "" && c == "$" && substr(s, i + 1, 1) == "(") { tok = tok "("; i++; dp++; continue }
                    if (iq == "" && c == ")") dp--
                    continue
                }
                if (q == "\047") { if (c == "\047") q = ""; else tok = tok (c == "$" ? "\002" : c); continue }
                if (c == "\\" && q == "") { tok = tok substr(s, i + 1, 1); i++; continue }
                if (c == "$" && substr(s, i + 1, 1) == "(") { dp = 1; iq = ""; tok = tok "$("; i++; continue }
                if (q == "\"") { if (c == "\"") q = ""; else tok = tok c; continue }
                if (c == "\047" || c == "\"") { q = c; has = 1; continue }
                if (c == " " || c == "\t") { if (tok != "" || has) { W[++n] = tok; tok = ""; has = 0 }; continue }
                tok = tok c
            }
            if (tok != "" || has) W[++n] = tok
            return n
        }
        # 낱말 안의 $( ... ) 명령도 본다(out=$(git push 2>&1)). 명령치환은 자식 셸이라 cd 가 새지 않는다.
        # 해석한 명령치환 수를 돌려준다(simple 이 "무엇이든 해석했는가"를 판단한다).
        function subst(w,    len, i, c, dp, iq, st, saved, ran) {
            dp = 0; iq = ""; ran = 0; len = length(w)
            for (i = 1; i <= len; i++) {
                c = substr(w, i, 1)
                if (dp == 0) { if (c == "$" && substr(w, i + 1, 1) == "(") { dp = 1; iq = ""; st = i + 2; i++ }; continue }
                if (iq == "\047") { if (c == "\047") iq = ""; continue }
                if (c == "\\") { i++; continue }
                if (c == "\047" || c == "\"") { if (iq == "") iq = c; else if (iq == c) iq = ""; continue }
                if (iq == "" && c == "$" && substr(w, i + 1, 1) == "(") { dp++; i++; continue }
                if (iq == "" && c == ")" && --dp == 0) { saved = DIR; ran += process(substr(w, st, i - st)); DIR = saved }
            }
            return ran
        }
        # 낱말 하나를 확장한다. 값이 여럿이면 S 로 잇고, 풀 수 없으면 U.
        function expand(w,    pre, rest, name, vals, r, nv, nr, V, R, k, j, out) {
            if (w == U || w ~ /`/ || w ~ /\$\(/) return U
            if (w == "~" || substr(w, 1, 2) == "~/") w = home substr(w, 2)
            if (!match(w, /\$\{[A-Za-z_][A-Za-z0-9_]*\}|\$[A-Za-z_][A-Za-z0-9_]*/)) {
                if (w ~ /\$/) return U
                gsub(/\002/, "$", w)
                return w
            }
            pre = substr(w, 1, RSTART - 1); rest = substr(w, RSTART + RLENGTH)
            name = substr(w, RSTART, RLENGTH); gsub(/[${}]/, "", name)
            if (name == "HOME") vals = home
            else if (name == "PWD") vals = DIR
            else if (name in VAR) vals = VAR[name]
            else if (name in ENVIRON) vals = ENVIRON[name]          # $CLAUDE_PROJECT_DIR 처럼 명령 밖에서 정해진 값
            else return U
            if (vals == U || pre ~ /\$/) return U
            r = expand(rest)
            if (r == U) return U
            nv = split(vals, V, S); nr = split(r, R, S)
            if (nr == 0) { nr = 1; R[1] = "" }
            out = ""
            for (k = 1; k <= nv; k++) for (j = 1; j <= nr; j++) out = out (out == "" ? "" : S) pre V[k] R[j]
            gsub(/\002/, "$", out)
            return out
        }
        # base(여럿일 수 있다) 기준으로 p(여럿일 수 있다)를 푼다. p 를 풀 수 없으면 base 를 그대로 둔다.
        function resolve(base, p,    nb, np, B, P, k, j, out) {
            if (p == U || p == "") return base
            nb = split(base, B, S); np = split(p, P, S); out = ""
            for (k = 1; k <= nb; k++) for (j = 1; j <= np; j++)
                out = out (out == "" ? "" : S) (substr(P[j], 1, 1) == "/" ? P[j] : B[k] "/" P[j])
            return out
        }
        function emit(d, rev,    n, D, k) {
            if (d == U || rev == U) { print "?\t?"; return }
            n = split(d, D, S)
            for (k = 1; k <= n; k++) print D[k] "\t" rev
        }
        function simple(s,    W, n, i, k, e, v, name, arg, g, d, sc, ran) {
            n = words(s, W); ran = 0
            for (k = 1; k <= n; k++) if (index(W[k], "$(")) ran += subst(W[k])
            i = 1
            while (i <= n && W[i] ~ /^(if|then|else|elif|do|while|until|time|!|\{|\})$/) i++
            if (i > n) return
            if (W[i] == "for" && i + 2 <= n && W[i + 2] == "in") {
                v = ""
                for (k = i + 3; k <= n; k++) { e = expand(W[k]); if (e == U) { v = U; break }; v = v (v == "" ? "" : S) e }
                VAR[W[i + 1]] = v
                return
            }
            if (W[i] ~ /^(export|local|declare|readonly|typeset|env)$/) i++
            while (i <= n && W[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) {
                name = W[i]; sub(/=.*/, "", name)
                VAR[name] = expand(substr(W[i], length(name) + 2))
                i++
            }
            if (i > n) return
            if (W[i] == "cd" || W[i] == "pushd") {
                arg = ""
                for (k = i + 1; k <= n; k++) { if (W[k] == "--" || W[k] ~ /^-[LPe@]+$/) continue; arg = W[k]; break }
                if (arg == "") DIR = home
                else if (arg != "-") DIR = resolve(DIR, expand(arg))
                return
            }
            if (W[i] == "popd") return
            if (W[i] == "eval") { arg = ""; for (k = i + 1; k <= n; k++) arg = arg " " W[k]; process(arg); return }
            # 셸과 git 은 아무 위치에서나 찾는다(timeout 60 bash -c ..., nohup git push ...).
            for (g = i; g <= n; g++) if (W[g] ~ /(^|\/)(ba|z|da|k)?sh$/ && shellcmd(W, g, n)) return
            for (g = i; g <= n; g++) if (W[g] == "git" || W[g] ~ /\/git$/) break
            # git 을 찾았는데 서브커맨드가 push 가 아니면 push 가 아니다(커밋 메시지 속 "git push" 글자).
            # git 도 셸도 명령치환도 해석하지 못했는데 문자열이 push 모양이면 판정 불가로 감사한다.
            if (g > n) { if (!ran && s ~ push_re) emit(U, U); return }
            d = DIR; sc = 0
            for (k = g + 1; k <= n; k++) {
                if (W[k] == "-C") { k++; d = resolve(d, expand(W[k])); continue }
                if (W[k] == "-c" || W[k] == "--namespace" || W[k] == "--super-prefix") { k++; continue }
                if (W[k] ~ /^--(git-dir|work-tree)/) { if (W[k] !~ /=/) k++; continue }
                if (W[k] ~ /^-/) continue
                sc = k; break
            }
            if (sc && W[sc] == "push") pushargs(d, W, sc + 1, n)
        }
        # W[g] 가 셸이고 뒤에 c 가 든 옵션이 오면(-c, -lc, --login -c, -e -o pipefail -c, --rcfile f -c)
        # 그 명령 문자열을 해석하고 1 을 돌려준다. 자식 셸이라 cd 가 새지 않는다.
        function shellcmd(W, g, n,    k, hasc, saved) {
            hasc = 0
            for (k = g + 1; k <= n; k++) {
                if (W[k] ~ /^([-+][oO]|--rcfile|--init-file)$/) { k++; continue }
                if (W[k] ~ /^--/) continue
                if (W[k] ~ /^[-+][A-Za-z]+$/) { if (W[k] ~ /c/) hasc = 1; continue }
                break
            }
            if (!hasc || k > n) return 0
            saved = DIR; process(W[k]); DIR = saved
            return 1
        }
        # push 인자: 첫 비-옵션은 원격, 나머지가 refspec. `+src:dst` 의 src 만 본다.
        function pushargs(d, W, from, n,    k, t, seen, any, e, m, V, j, src) {
            seen = 0; any = 0
            for (k = from; k <= n; k++) {
                t = W[k]
                if (t ~ /^([0-9]*|&)?[<>]/) { if (t ~ /^([0-9]*|&)?[<>]+&?$/) k++; continue }
                if (t == "--dry-run" || t ~ /^-[A-Za-z]*n[A-Za-z]*$/) return
                if (t == "--delete" || t ~ /^-[A-Za-z]*d[A-Za-z]*$/) return
                if (t == "-o" || t == "--push-option" || t == "--repo" || t == "--receive-pack" || t == "--exec") { k++; continue }
                if (t ~ /^-/) continue
                if (!seen) { seen = 1; continue }
                any = 1
                e = expand(t)
                if (e == U) { emit(d, "HEAD"); continue }
                m = split(e, V, S)
                for (j = 1; j <= m; j++) {
                    src = V[j]; sub(/^\+/, "", src); sub(/:.*/, "", src)
                    if (src != "") emit(d, src)
                }
            }
            if (!any) emit(d, "HEAD")
        }'
}

# JSON 문자열 이스케이프를 되돌린다. args 와 command 는 훅에 \" \\ \n 형태로 escape 되어 도착한다.
#   args:    되돌리지 않으면 `/code-review "a b.js"` 의 토큰이 실제 파일명과 영영 달라 경로
#            지정이 무시되고, 그러면 **전체가 covered 된다**(조용한 통과).
#   command: 되돌리지 않으면 git -C "$W" push 의 경로가 \"...\" 로 깨져 대상 레포를 못 찾는다.
# \n 의 목적지는 호출자가 고른다(두 번째 인자 nl). args 는 **공백**이어야 한 줄 토큰 흐름이 되고,
# command 는 **실제 개행**이어야 멀티라인 명령을 줄 단위로 나눌 수 있다. 둘째 줄 git 앞에
# 역슬래시+n 두 글자가 남으면 'n' 이 단어 경계를 지워, 멀티라인 명령이 통째로 게이트를
# 빠져나갔다(실측: 이 머신의 실제 커밋 호출 411건 중 84건, 20%).
# 한 번의 좌->우 스캔으로 처리한다: \\n 을 개행으로 오해하지 않으려면 순차 치환이 아니어야 한다.
_json_unescape() {
    printf '%s' "$1" | LC_ALL=C awk -v nl="${2:-}" '{
        out = ""; n = length($0)
        for (i = 1; i <= n; i++) {
            c = substr($0, i, 1)
            if (c == "\\" && i < n) {
                i++; d = substr($0, i, 1)
                if (d == "n") out = out (nl == "nl" ? "\n" : " ")
                else if (d == "t" || d == "r") out = out " "
                else out = out d
            } else out = out c
        }
        print out
    }'
}

# args 를 셸처럼 토큰으로 쪼갠다. 한 줄에 원형, 정리형, 경로형을 \034 로 이어 낸다(탭으로 이으면
# read 가 연속된 공백 구분자를 하나로 접어, 정리형이 빈 한글 낱말에서 경로형이 정리형 자리로 밀린다). 인용부호는 묶음으로
# 인정하고 제거한다. 단순 공백 분리로는 `/code-review "a b.js"` 가 세 토막으로 갈라져 경로 지정이
# 무시된다(그 결과는 위 _json_unescape 주석 참조). eval 하지 않는다: args 는 외부 입력이고, 여기서
# 필요한 것은 실행이 아니라 분해뿐이다.
#   원형:   손대지 않은 값. 순수 숫자와 URL 판정용("(1)" 같은 목록 번호를 PR 번호로 읽지 않는다).
#   정리형: 앞의 여는 괄호와 따옴표, 뒤의 구두점과 한글 조사를 뗀 값. ref 와 PR 번호 판정용
#           ("origin/develop의", "#1891)").
#   경로형: 앞의 여는 괄호와 따옴표만 떼고 ~/ 를 $HOME 으로 편 값. 뒤는 _path_hit 이 실재를 확인하며
#           한 글자씩 뗀다(한꺼번에 떼면 한글 경로 이름까지 먹혀 부모 디렉토리로 넓어진다).
# LC_ALL=C: 조사는 바이트 단위로 떼야 한다. UTF-8 로케일의 awk 는 반쯤 뗀 글자에서 멈춘다.
_arg_tokens() {
    printf '%s' "$1" | LC_ALL=C awk -v home="$HOME" '
        function out(t,    c, p) {
            if (t == "") return
            p = t
            while (p ~ /^[([{<"\047]/) p = substr(p, 2)
            if (substr(p, 1, 2) == "~/") p = home substr(p, 2)
            c = p
            while (c ~ /[])}>,.;:"\047!?]$/ || c ~ /[^ -~]$/) c = substr(c, 1, length(c) - 1)
            print t "\034" c "\034" p
        }
        {
            n = length($0); tok = ""; inq = ""
            for (i = 1; i <= n; i++) {
                ch = substr($0, i, 1)
                if (inq != "") {
                    if (ch == inq) inq = ""; else tok = tok ch
                } else if (ch == "\"" || ch == "\047") {
                    inq = ch
                } else if (ch == " " || ch == "\t") {
                    out(tok); tok = ""
                } else tok = tok ch
            }
            out(tok)
        }'
}

# ── 커버리지 범위: 이 스킬이 무엇을 봤는가 ─────────────────────
# 스킬 호출의 args 는 모델의 자기보고가 아니라 도구 호출 사실이라 근거로 쓸 수 있다.
# 실측한 실제 호출 형태: "high" / "1952" / "https://.../pull/710" /
# "high /다른/worktree/경로" / "high a.html b.html" / 자유 서술.
#
# 왜 필요한가: `/code-review 1952` 는 **원격 PR** 을 리뷰한다. 이 워킹트리를 쳐다보지도
# 않는다. 그런데 args 를 무시하면 그 리뷰에게 현재 레포의 변경 파일 전부를 credit 하게 되어,
# 이 코드를 본 적 없는 리뷰가 이 코드를 통과시킨다. 다른 worktree 를 지정한 경우도 같다.
#
# 판정은 **코드가 검증할 수 있는 사실**로만 한다: 경로가 실재하는가, 순수 숫자인가,
# PR URL 인가. 자유 서술은 해석하지 않는다(해석하면 그게 다시 모델 판단이다).
#
# 트랜스크립트에서 "이 스킬이 실제로 Read 한 파일"을 뽑는 쪽이 더 일반적인 신호이지만
# 쓰지 않는다. **이유는 상관 짓기가 어려워서가 아니다**(서브에이전트 트랜스크립트는
# ~/.claude/projects/<프로젝트>/<세션>/subagents/ 에 실제로 있고, tool_result 의 agentId 가
# 결정적 조인 키다). 타이밍이 안 맞는다: fork 되는 스킬은 4초 만에 "background 로 시작함"을
# 돌려주고 PostToolUse 는 **그때** 발화하는데, 실제 리뷰는 그 뒤로 10분을 더 돈다. 훅이 볼
# 시점에 그 파일에는 리뷰의 도구 호출이 하나도 없다(실측: SubagentStop 은 이 실행 모드에서
# 한 번도 발화하지 않았다). 게다가 실측한 /code-review 는 Read 0회, Bash 21회였다.
# "무엇을 봤나"를 알려면 임의의 셸 파이프라인을 파싱해야 하고, 그건 이 파일이 git push
# 감지에서 이미 싸우고 있는 문제의 더 어려운 판본이다. args 가 지금 훅이 볼 수 있는 근거다.
# 결과는 **전역으로** 돌려준다. 문자열 하나로 "전체/없음/경로목록"을 다 실어 보내면 그 세
# 도메인이 겹친다: 실제로 __all__ 이라는 이름의 파일을 짚으면 목록이 그 한 줄이 되고,
# 명령치환이 끝의 개행을 떼어내 "전체"를 뜻하던 값과 바이트가 같아진다. 그러면 그 한 파일만
# 인정하려던 호출이 **범위 전체를 인정**한다(실증됨). 경로는 배열로 담아 그 부류를 구조적으로
# 없앤다. (이 파일의 _analyze 도 같은 이유로 전역을 쓴다: 명령치환으로 부르지 않는다.)
COVERAGE_MODE=""      # all | none | paths
COVERAGE_PATHS=()     # paths 일 때만 채운다. 이 트리 루트 기준 경로("." 은 전체)
COVERAGE_TREES=()     # 인자가 짚은 **다른** git 작업 트리: "<루트><탭><그 루트 기준 경로>"
ML_TOP=""             # 이 트리의 루트(물리 경로). 호출자가 구해 두면 다시 묻지 않는다

# 원격 PR 을 본 호출: 어떤 트리도 커버하지 않는다. 다른 트리 기록도 버린다(남기면 원격 리뷰가
# do_record 의 트리 루프를 타고 다른 트리에 커버리지로 기록된다).
_coverage_remote() { COVERAGE_MODE="none"; COVERAGE_TREES=(); }

_coverage_scope() {
    local args root raw clean path abs t pre d leaf re
    local elsewhere=0 here=0 saw_pr=0 saw_num=0 prev="" refs=""
    COVERAGE_MODE=""; COVERAGE_PATHS=(); COVERAGE_TREES=(); REF_CUR=""; REF_UP=""; REF_FROM="-"
    args="$(_json_unescape "${1:-}")"
    [ -z "${args//[[:space:]]/}" ] && { COVERAGE_MODE="all"; return 0; }
    root="${ML_TOP:-$(git rev-parse --show-toplevel 2>/dev/null)}"
    [ -n "$root" ] || root="$PWD"

    # 신호를 세 층으로 가른다. 한 호출이 **여러 대상**을 함께 보는 일이 흔하기 때문이다
    # ("두 워크트리의 origin/develop 대비 변경: <이 트리> 및 <다른 트리>").
    #   확정(원격 PR 을 봤다): PR 번호, URL, #번호, 값을 품은 --옵션 → 즉시 미커버.
    #   다른 대상: 이 트리의 기준이 아닌 ref, 다른 git 작업 트리 안의 경로, PR 낱말+숫자.
    #   이 트리: 이 레포 안의 실재하는 경로, 또는 이 트리를 가리키는 지시어.
    # 이 트리 신호가 있으면 다른 대상 신호는 그 인정을 지우지 못한다. 옛 규칙은 다른 대상이 하나라도
    # 보이면 통째로 미커버로 봐서, 두 레포를 한 번에 리뷰한 호출이 **어느 쪽에서도** 인정받지 못했다
    # (2026-09-10 CRS-1031). 다른 트리 경로는 그 트리 몫으로 COVERAGE_TREES 에 모은다.
    #
    # 모르는 낱말(강도, 산문)은 범위를 좁히지도 넓히지도 않는다. 한때 모르는 토큰이 하나라도 있으면
    # 아무 것도 인정하지 않았는데, 실측이 뒤집었다: 실사용 args 35종 중 33종(94%)이 커버리지 0 이
    # 됐다. 남는 한계: "lib 는 빼고" 같은 부정문의 경로와 "이 워크트리 말고" 같은 부정문의 지시어는
    # 인정 쪽으로 읽힌다. 산문의 의미를 해석하지 않는 대가다.
    while IFS=$'\034' read -r raw clean path; do
        [ -n "$raw" ] || continue
        case "$raw" in
            --|--fix|--comment|--post|--no-post) continue ;;
            --*=*) _coverage_remote; return 0 ;;          # --pr=1952
            --*) continue ;;                               # 산문 속 --cached)
        esac
        # 확정 신호는 경로 검사보다 먼저 본다. 뒤집으면 이름이 겹치는 로컬 경로가 원격 참조를 가린다
        # (브랜치에 1952/ 를 심어 두면 /code-review 1952 가 그걸 봤다고 기록된다).
        case "$raw" in *://*) _coverage_remote; return 0 ;; esac
        if [[ "$raw" =~ ^[0-9]+$ ]]; then _coverage_remote; return 0; fi
        # 이 트리를 가리키는 지시어("이 워크트리", "현재 브랜치", "this worktree")는 이 트리를 본 근거다.
        # 다른 트리를 맥락으로 곁들인 산문("프론트는 <다른 워크트리> 에 있음")이 그 경로 하나 때문에
        # 통째로 미커버가 되지 않게 한다(HUB2-390). 닫힌 목록만 본다.
        case "$prev" in
            이|이번|현재|지금|해당|[Tt]his|[Cc]urrent)
                case "$raw" in
                    워크트리*|워킹트리*|작업트리*|트리*|브랜치*|레포*|저장소*|[Ww]orktree*|[Ww]orking*|[Tt]ree*|[Bb]ranch*|[Rr]epo*) here=1 ;;
                esac ;;
        esac
        prev="$raw"
        _path_hit "$path"

        # 한글만으로 된 낱말은 정리형이 비어 버린다. 빈 정리형은 ref 목록의 빈 줄과 맞아 "다른 브랜치"로
        # 읽히므로 ref, PR 판정에 태우지 않는다. 그래도 실재하는 경로("회의록")면 아래에서 경로로 본다.
        if [ -n "$clean" ]; then
            case "$clean" in
                *'#'[0-9]*) case "${clean##*#}" in *[!0-9]*) ;; *) _coverage_remote; return 0 ;; esac ;;
            esac
            # 경로로 풀리지 않는 /pull/ /merge_requests/ 는 원격 링크다(스킴이 없어도).
            if [ -z "$HIT" ]; then
                case "$clean" in */pull/*|*/merge_requests/*) _coverage_remote; return 0 ;; esac
            fi
            case "$clean" in PR|pr|Pr|MR|mr|Mr) saw_pr=1 ;; esac
            case "$clean" in *[0-9]*) [ -n "$HIT" ] || saw_num=1 ;; esac

            # ref 도 경로보다 먼저 본다(같은 이름의 디렉토리로 브랜치 리뷰를 경로 리뷰로 바꾸지 못하게).
            # 목록은 첫 필요 시점에 **한 번만** 뜨고, 현재 브랜치와 upstream 도 그 호출에서 함께 받는다.
            # HEAD 는 for-each-ref 에 없으므로 직접 넣는다.
            if [ -z "$refs" ]; then
                # 현재 브랜치 줄에만 "<이름>\t<upstream>" 을 붙여 한 번에 받는다. 줄마다 read 로 돌면 ref 가
                # 수백 개인 레포에서 기록 한 번이 100ms 넘게 늘었다.
                refs="HEAD"$'\n'"$(git for-each-ref \
                    --format='%(refname:short)%(if)%(HEAD)%(then)%09%(upstream:short)%(end)' \
                    refs/heads refs/tags refs/remotes 2>/dev/null)"
                re=$'\n([^\t\n]+)\t([^\n]*)'
                if [[ "$refs" =~ $re ]]; then REF_CUR="${BASH_REMATCH[1]}"; REF_UP="${BASH_REMATCH[2]}"; fi
            fi
            case $'\n'"$refs"$'\n' in
                *$'\n'"$clean"$'\n'*|*$'\n'"$clean"$'\t'*) _ref_is_base "$clean" || elsewhere=1; continue ;;
            esac
        fi

        [ -n "$HIT" ] || continue
        case "$HIT" in /*) abs="$HIT" ;; *) abs="$PWD/$HIT" ;; esac
        if [ -d "$abs" ]; then d="$abs"; leaf=""; else d="${abs%/*}"; d="${d:-/}"; leaf="${abs##*/}"; fi
        # 이 트리 안의 평범한 경로는 문자열로 끝낸다: 루트 아래이고 ../ 가 없고, 올라가며 중첩된 작업
        # 트리(.git)나 심볼릭 링크를 만나지 않을 때만. 그 밖(다른 트리, 심볼릭 표기, ../, 중첩 worktree)은
        # git 에게 묻는다. 문자열 접두사만 믿으면 .claude/worktrees/<ID> 를 이 트리 경로로 읽어 그 트리에
        # 기록을 안 남기고, ../ 가 섞인 경로에서 git 이 "outside repository" 로 죽어 기록 전체가 사라졌다.
        case "$abs" in
            */../*|*/..|*/./*|*/.) ;;
            "$root"|"$root"/*)
                t="$d"
                while [ "${#t}" -gt "${#root}" ] && [ ! -e "$t/.git" ] && [ ! -L "$t" ]; do t="${t%/*}"; done
                if [ "${#t}" -le "${#root}" ]; then
                    pre="${abs#"$root"}"; pre="${pre#/}"
                    COVERAGE_PATHS+=("${pre:-.}")
                    continue
                fi ;;
        esac
        # --show-toplevel 은 물리 경로를, --show-prefix 는 그 루트 기준 위치를 준다.
        t=""; pre=""
        { read -r t; read -r pre; } < <(git -C "$d" rev-parse --show-toplevel --show-prefix 2>/dev/null)
        [ -n "$t" ] || continue
        pre="${pre}${leaf}"
        if [ "$t" = "$root" ]; then
            COVERAGE_PATHS+=("${pre:-.}")
        else
            elsewhere=1                       # 레포 밖이라도 git 트리가 아닌 곳(스크래치 파일)은 신호가 아니다
            COVERAGE_TREES+=("${t}"$'\t'"${pre:-.}")
        fi
    done < <(_arg_tokens "$args")

    # PR 낱말과 숫자 낱말의 공존("크스-1952 관련 PR 검토")은 산문 추정이라 다른 대상 신호로만 쓴다.
    [ "$saw_pr" = 1 ] && [ "$saw_num" = 1 ] && elsewhere=1
    # 이 트리를 가리키는 지시어가 있으면 다른 트리 경로는 맥락이다. 그 트리에 리뷰 기록을 남기지 않는다:
    # 남기면 맥락으로 적은 프론트 레포가 통째로 리뷰된 것으로 기록돼, 한 번도 안 본 레포의 push 가 통과한다.
    if [ "$here" = 1 ]; then COVERAGE_TREES=(); fi
    if [ "${#COVERAGE_PATHS[@]}" -gt 0 ]; then COVERAGE_MODE="paths"; return 0; fi
    if [ "$elsewhere" = 1 ] && [ "$here" = 0 ]; then COVERAGE_MODE="none"; return 0; fi
    # 강도뿐이거나 산문뿐이다 = 스킬 기본 범위(워킹트리 전체 diff)를 본 것이다.
    COVERAGE_MODE="all"
    return 0
}

# 산문에 붙은 것을 떼어 낸 실재하는 경로를 HIT 에 둔다(없으면 빈 값). 입력은 _arg_tokens 의 경로형이다
# (앞 괄호를 떼고 ~/ 를 편 값). 뒤에서 구두점과 한글 조사를 **한 글자씩** 떼며 실재하는지 본다.
# 바이트 부류로 한꺼번에 떼면 한글 경로 이름까지 먹혀 부모 디렉토리로 넓어진다("docs/회의록을" 이
# docs/ 가 됐다). 그래서 떼다가 / 로 끝나면 포기한다: 짚은 것보다 넓게 인정하지 않는다.
# 명령치환 없이 전역으로 돌려준다(fork 없음).
HIT=""
_path_hit() {
    local t="$1" n=0
    HIT=""
    while [ -n "$t" ] && [ "$n" -le 16 ]; do
        if [ -e "$t" ]; then
            # 떼어 낸 끝이 . 이나 .. 이면 짚은 적 없는 디렉토리다("..." 이 .. 이 되어 레포 루트를 인정했다).
            case "$n/$t" in 0/*) ;; */.|*/..) return 0 ;; esac
            HIT="$t"; [ "$HIT" = "/" ] || HIT="${HIT%/}"; return 0
        fi
        case "$t" in */) return 0 ;; esac
        # 구두점과 비-ASCII(한글 조사)만 뗀다. 영숫자까지 떼면 lib2 가 lib 로 넓어진다.
        case "${t: -1}" in [abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-]) return 0 ;; esac
        t="${t%?}"; n=$((n + 1))
    done
    return 0
}

# ref 낱말이 이 트리의 기준인가: HEAD, 현재 브랜치, upstream, 이 브랜치를 딴 지점, HEAD 의 조상.
# "origin/develop 대비 변경" 의 origin/develop 은 다른 대상이 아니라 비교 기준이다. 이런 낱말을
# 다른 브랜치 리뷰로 읽으면 가장 흔한 산문이 전부 미커버가 된다. 갈라진 형제 브랜치를 짚은
# 호출(/code-review other-feature)은 여전히 다른 대상이다.
# 현재 브랜치와 upstream 은 _coverage_scope 가 ref 목록을 뜰 때 함께 받아 둔다(REF_CUR, REF_UP).
# 첫 push 의 -u 뒤에는 upstream 이 자기 원격 브랜치로 바뀌고, 기준 브랜치가 앞서 나가면 조상도 아니게
# 된다. 딴 지점은 브랜치 reflog 의 첫 줄에 남아 있다("branch: Created from origin/develop"). reflog 는
# 문자열 비교가 모두 빗나갔을 때 한 번만 읽는다.
_ref_is_base() {
    local r="$1"
    case "$r" in HEAD|"$REF_CUR"|"$REF_UP"|"${REF_UP#*/}") return 0 ;; esac
    if [ "$REF_FROM" = "-" ]; then
        REF_FROM=""
        if [ -n "$REF_CUR" ]; then
            REF_FROM="$(git reflog show --format=%gs "refs/heads/$REF_CUR" 2>/dev/null | tail -1)"
            case "$REF_FROM" in
                "branch: Created from "*)
                    REF_FROM="${REF_FROM#branch: Created from }"
                    REF_FROM="${REF_FROM#refs/remotes/}"; REF_FROM="${REF_FROM#refs/heads/}" ;;
                *) REF_FROM="" ;;
            esac
        fi
    fi
    case "$r" in "$REF_FROM"|"${REF_FROM#*/}") return 0 ;; esac
    git merge-base --is-ancestor "$r" HEAD 2>/dev/null
}

# 경로 제한(sp)이 있으면 pathspec 으로 붙여 git 을 부른다. 빈 배열 확장은 set -u 아래서
# 위험하므로 개수를 세고 분기한다. quotePath=false 는 비-ASCII 경로가 C-quote 되어
# push 시점 경로와 영영 어긋나는 것을 막는다(그러면 그 파일은 절대 covered 로 안 잡힌다).
_git_names() {
    # 레포 루트에서 돈다. 하위 디렉토리에서 부르면 ls-files 가 **cwd 기준** 경로를 주고,
    # diff 는 루트 기준을 주어 두 목록이 섞인다. 섞이면 그 파일은 영영 _absent 로 기록된다.
    # top 도 sp 와 같이 호출자가 선언한다(미선언이면 현재 위치를 쓴다).
    # sp 는 호출자(_snapshot_covered)가 선언하는 pathspec 배열이다. 선언되지 않은 채로
    # 불리면 set -u 아래서 ${#sp[@]} 가 함수를 조용히 끝내고, 빈 출력은 "변경 파일 없음"과
    # 구별되지 않아 커버리지가 통째로 비게 된다(shellcheck 도 못 잡는다). 그래서 방어한다.
    local n=0
    [ "${sp+set}" = "set" ] && n="${#sp[@]}"
    local at="${top:-.}"
    if [ "$n" -gt 0 ]; then git -C "$at" -c core.quotePath=false "$@" -- "${sp[@]}" 2>/dev/null
    else git -C "$at" -c core.quotePath=false "$@" 2>/dev/null; fi
}

# 리뷰가 실제로 본 파일 내용을 blob 해시로 붙잡는다 (record 시점 = 스킬이 막 끝난 시점).
# 워킹트리 기준으로 해시를 뜬다: 리뷰는 커밋된 것이 아니라 지금 눈앞의 내용을 본다.
# 그 내용이 나중에 그대로 커밋되면 push 시점 HEAD blob 해시와 일치해 covered 로 잡힌다.
#
# **스킬 이름을 함께 적는다.** 내용만 적으면 스킬 하나만 돌려도 그 내용이 통째로 covered 가
# 되어, /simplify 만 돌리고 /code-review 를 건너뛴 push 가 통과한다(실제로 그랬다).
_snapshot_covered() {
    local skill="$1" range files present hashes f
    local sp=()
    # 범위(COVERAGE_MODE/COVERAGE_PATHS)는 호출자가 정한다(do_record 가 인자를 한 번만 해석한다).
    # 이 스킬이 이 트리를 보지 않았다면 아무 것도 인정하지 않는다.
    if [ "$COVERAGE_MODE" = "none" ]; then
        _ensure_regular_file "$NOSCOPE_REL" || return 0
        # 왜 마커를 남기나: 이 스킬이 "돌긴 했지만 이 트리를 안 봤다"는 사실을 push 시점에
        # 알아야 차단 사유를 가를 수 있다. 원장 등재 여부만 보면 이 경우와 "리뷰 뒤에 코드를
        # 더 쓴 경우"(가장 흔한 차단)가 한 덩어리가 되어, 그 수치로는 판정이 엄격한지 알 수 없다.
        grep -qxF "$skill" "$NOSCOPE_REL" 2>/dev/null \
            || printf '%s
' "$skill" >> "$NOSCOPE_REL" 2>/dev/null || true
        return 0
    fi
    # 이번엔 실제로 봤다. 지난 미커버 표시를 걷어낸다: 남겨 두면 그 스킬은 영영 "딴 데를
    # 봤다"로 분류되어, 정작 가장 흔한 사유(보고 나서 더 씀)가 통계에서 사라진다.
    if [ -s "$NOSCOPE_REL" ] 2>/dev/null; then
        # grep -v 는 **출력이 비면 exit 1** 이다. 종료코드로 분기하면 마지막 한 줄이
        # 영영 안 지워지고, 그 스킬은 계속 "딴 데를 봤다"로 분류된다(실측으로 걸렸다).
        grep -vxF "$skill" "$NOSCOPE_REL" > "$NOSCOPE_REL.tmp" 2>/dev/null || true
        mv -f "$NOSCOPE_REL.tmp" "$NOSCOPE_REL" 2>/dev/null || rm -f "$NOSCOPE_REL.tmp" 2>/dev/null || true
    fi
    # 짚은 경로가 있으면 git pathspec 으로 넘긴다. 손으로 "이 파일이 이 경로 아래인가"를
    # 짜면 후행 슬래시(lib/ -> lib//*)에서 아무것도 안 맞는 식으로 조용히 틀린다.
    # git 은 정확한 경로 또는 그 디렉토리 하위만 매칭하며(li 가 lib/ 를 오염시키지 않는다),
    # 없는 경로는 빈 결과로 조용히 끝난다.
    if [ "$COVERAGE_MODE" = "paths" ]; then
        sp=("${COVERAGE_PATHS[@]}")
        [ "${#sp[@]}" -eq 0 ] && return 0
    fi
    # git 이 주는 경로는 **레포 루트 기준**인데 [ -f ] 와 hash-object 는 cwd 기준이라,
    # 하위 디렉토리에서 세션이 돌면 모든 파일이 _absent 로 기록되고 커버리지가 영원히
    # 맞지 않는다(해소 불가능한 차단 루프). 루트를 앞에 붙여 맞춘다.
    local top="${ML_TOP:-$PWD}"
    # 판정과 같은 범위 정의를 쓴다. 기록 범위가 판정 범위보다 좁으면 그 차이는 영영 미검토다.
    _push_scope HEAD
    range="$SCOPE_RANGE"
    # quotePath=false: 위 _range_signature 와 같은 이유다. 여기서 따옴표 붙은 경로를 적으면
    # push 시점 경로와 영원히 어긋나 그 파일은 절대 covered 로 잡히지 않는다.
    files="$( {
        [ "${range%%...*}" != "${range##*...}" ] && _git_names diff --name-only "$range"
        _git_names diff --name-only HEAD
        _git_names ls-files --others --exclude-standard
    } | sort -u | grep -v '^$' )"
    [ -z "$files" ] && return 0

    # 존재하는 것과 사라진 것을 가른다(루프는 builtin 만 쓴다: fork 없음).
    present=""
    while IFS= read -r f; do
        [ -f "$top/$f" ] && present="${present}${top}/${f}
"
    done <<EOF
$files
EOF

    # 존재하는 파일은 --stdin-paths 로 **한 번에** 해시한다. 파일마다 git hash-object 를
    # 부르면 스킬 호출마다 파일 수만큼 fork 가 난다.
    if [ -n "$present" ]; then
        hashes="$(printf '%s' "$present" | git hash-object --stdin-paths 2>/dev/null)"
        # 줄 수가 어긋나면 paste 가 해시와 경로를 엇갈리게 붙여 **틀린 커버리지**를 적는다.
        # (검사와 해싱 사이에 파일이 사라지면 실제로 난다.) 그럴 땐 통째로 버린다:
        # 커버리지가 비면 불필요한 차단이지만, 어긋나면 조용한 통과다.
        if [ "$(printf '%s' "$hashes" | grep -c '')" -eq "$(printf '%s' "$present" | grep -c '')" ]; then
            paste <(printf '%s' "$hashes") <(printf '%s' "$present") \
                | awk -v s="$skill" -v top="$top/" -F'\t' \
                      'NF>=2 { p = $2; sub("^" top, "", p); print s "\t" $1 "\t" p }' \
                >> "$COVERED_REL" 2>/dev/null || true
        fi
    fi
    # 사라진 파일은 push 시점에도 _absent 로 계산되므로 같은 표기로 남긴다.
    printf '%s\n' "$files" | grep -vxF -f <(printf '%s' "$present" | sed "s|^$top/||") 2>/dev/null \
        | awk -v s="$skill" 'NF {print s "\t_absent\t" $0}' >> "$COVERED_REL" 2>/dev/null || true

    # 여러 스킬이 같은 내용을 보므로 중복이 쌓인다. 집합으로 유지한다.
    # sort 가 실패하면 원본을 남긴다: 커버리지 유실은 곧 불필요한 차단이다.
    if [ -f "$COVERED_REL" ]; then
        if sort -u "$COVERED_REL" 2>/dev/null > "$COVERED_REL.tmp"; then
            mv -f "$COVERED_REL.tmp" "$COVERED_REL" 2>/dev/null || true
        fi
        rm -f "$COVERED_REL.tmp" 2>/dev/null || true
    fi
    return 0
}

# 범위의 "<HEAD blob 해시>\t<경로>" 줄들. git diff --raw 가 dst blob sha 를 그대로 주므로
# 한 번의 fork 로 끝난다(파일마다 git rev-parse HEAD:<경로> 를 부르면 파일 수만큼 fork).
_range_signature() {
    # core.quotePath=false 가 필수다. 기본값이면 git 이 비-ASCII 경로를 "\355\225\234..." 로
    # C-quote 해서 내보내고, 그 문자열을 pathspec 으로 넘기면 아무 파일도 매칭되지 않는다.
    # 그러면 잔여가 0건이 되어 **미검토 한글 파일이 조용히 통과한다**(실측으로 확인된 우회).
    local sp=()
    [ "${#SCOPE_PATHS[@]}" -gt 0 ] && sp=(-- "${SCOPE_PATHS[@]}")
    git -c core.quotePath=false diff --raw --abbrev=40 "$1" ${sp[@]+"${sp[@]}"} 2>/dev/null | awk -F'\t' '
        {
            split($1, a, " ")
            sha = a[4]
            if (sha ~ /^0+$/) sha = "_absent"       # 삭제는 dst sha 가 0으로 채워진다
            path = ($3 != "" ? $3 : $2)             # rename 은 dst 경로가 세 번째 필드다
            if (path != "") print sha "\t" path
        }'
}

# 위 서명 중 **이 스킬이** 아직 보지 않은 것의 경로만 출력한다.
# 파일 단위로 판정한다: 리뷰 후 한 줄만 고쳐도 그 파일 전체가 미검토다(안전한 쪽으로 틀린다).
# 커버리지 파일은 awk 안에서 한 번만 읽는다(파일마다 grep 을 부르지 않는다).
_uncovered_paths() {
    printf '%s\n' "$2" | awk -v skill="$1" -v cov="$COVERED_REL" '
        BEGIN { while ((getline line < cov) > 0) seen[line] = 1 }
        NF {
            if (!((skill "\t" $0) in seen)) { p = $0; sub(/^[^\t]*\t/, "", p); print p }
        }'
}

# 플러그인 스킬은 "<plugin>:<skill>" 로 들어온다(code-review:code-review).
# 마지막 콜론 뒤만 취해 내장/플러그인 경로를 같은 이름으로 취급한다.
_normalize_skill() { printf '%s' "${1##*:}"; }

# JSON 1줄에서 스칼라 필드 하나 (문자열/불리언 공용).
_json_field() { printf '%s' "$1" | sed -E "s/.*\"$2\":\"?([^,\"}]+)\"?.*/\1/"; }

# ── 정책 단일 출처 ──────────────────────────────────────────────
# 트랙별 필수 리뷰. strict.md 의 표와 이 함수가 어긋나면 tests/review-gate.bats 가 RED.
#   Trivial / Small : 없음 (셀프 리뷰는 산문 규율로 충분: 게이트를 걸지 않는다)
#   Medium          : simplify + code-review
#   Large           : simplify + code-review + security-review
#   + DB/인증/외부API 신호가 있으면 트랙과 무관하게 security-review 추가
required_skills() {
    local track="$1" db="${2:-false}" auth="${3:-false}" ext="${4:-false}" out=""
    case "$track" in
        Medium) out="simplify code-review" ;;
        Large)  out="simplify code-review security-review" ;;
        *)      return 0 ;;
    esac
    if [ "$db" = "true" ] || [ "$auth" = "true" ] || [ "$ext" = "true" ]; then
        case " $out " in
            *" security-review "*) : ;;
            *) out="$out security-review" ;;
        esac
    fi
    printf '%s' "$out"
}

# ── record: 리뷰 스킬 실행을 원장에 append (PostToolUse). 절대 실패로 turn 을 막지 않는다.
do_record() {
    local input skill args gd t line roots
    # read -d '' 는 builtin 이라 cat 의 포크를 없앤다. NUL 이 없으면 1 을 반환하나
    # 그때도 읽은 내용은 input 에 담긴다.
    IFS= read -r -d '' input || true
    # 필드 이름은 런타임에서 실측했다: Skill 도구의 tool_input 은 {"skill":"simplify"} 다.
    # 훅 문서는 skill_name 이라고 적고 있어 양쪽을 다 받는다: 한쪽만 읽고 맞췄다가는
    # 원장이 영영 비어 Medium 이상 push 가 전부 막힌다(경계면 교차검증).
    # 두 패턴은 서로 오탐하지 않는다: "skill" 뒤에 곧바로 콜론이 와야 매칭된다.
    skill="$(_json_str "$input" skill)"
    [ -z "$skill" ] && skill="$(_json_str "$input" skill_name)"
    [ -z "$skill" ] && exit 0
    skill="$(_normalize_skill "$skill")"
    # 정책에 없는 스킬은 기록하지 않는다. 판정은 필수 리뷰 스킬의 원장과 커버리지만 읽으므로, 나머지
    # 기록은 Skill 호출마다 범위 계산과 파일 해시를 돌고 버려졌다(호출당 170~250ms).
    case " $(required_skills Large true true true) " in *" $skill "*) ;; *) exit 0 ;; esac

    _cd_to_hook_cwd "$input"
    args="$(_json_str "$input" args)"
    # 레포 식별은 git 한 번으로 한다: git-dir 은 상태 경로, toplevel 은 경로 판정의 기준이다.
    gd=""; ML_TOP=""
    { read -r gd; read -r ML_TOP; } < <(git rev-parse --absolute-git-dir --show-toplevel 2>/dev/null)
    _ml_init_state "$gd" "$ML_TOP"
    # 인자는 여기서 **한 번만** 해석한다. 트리마다 다시 해석하면 같은 낱말이 트리마다 다른 역할이
    # 된다(이 트리에서는 맥락이던 경로가 다른 트리에서는 대상이 되고, 상대경로가 엉뚱한 트리에 붙는다).
    _coverage_scope "$args"
    _record_skill "$skill"

    # 한 호출이 여러 작업 트리를 리뷰하는 일이 흔하다("crs 와 crs-admin-web 워크트리의 변경"). 훅은
    # 세션 cwd 한 곳에서만 뜨므로, 인자가 짚은 다른 트리에도 그 트리 몫의 경로로 기록한다. 안 남기면
    # 리뷰를 돌렸는데도 그 레포의 push 가 "리뷰 미실행"으로 막힌다.
    [ "${#COVERAGE_TREES[@]}" -gt 0 ] || exit 0
    roots="$(printf '%s\n' "${COVERAGE_TREES[@]}" | cut -f1 | sort -u)"
    while IFS= read -r t; do
        [ -n "$t" ] || continue
        ( cd "$t" 2>/dev/null || exit 0
          COVERAGE_MODE="paths"; COVERAGE_PATHS=()
          for line in "${COVERAGE_TREES[@]}"; do
              [ "${line%%$'\t'*}" = "$t" ] && COVERAGE_PATHS+=("${line#*$'\t'}")
          done
          ML_TOP="$t"
          _ml_init_state "" "$t"
          _record_skill "$skill" )
    done <<EOF
$roots
EOF
    exit 0
}

# 현재 디렉토리의 트리에 스킬 실행을 기록한다(원장 + 커버리지). 상태 경로와 범위
# (COVERAGE_MODE/COVERAGE_PATHS)는 호출자가 정해 둔다.
_record_skill() {
    local skill="$1"
    mkdir -p "$(dirname "$LEDGER_REL")" 2>/dev/null || return 0
    mkdir -p "${SKIP_REL%/*}" 2>/dev/null || true
    _ensure_regular_file "$LEDGER_REL" || return 0
    _ensure_regular_file "$COVERED_REL" || return 0
    _ensure_regular_file "$COVERED_REL.tmp" || return 0
    _ml_seed_gitignore
    # 같은 스킬을 여러 번 호출해도 한 줄만 남긴다: 원장은 집합이지 호출 로그가 아니다.
    grep -qxF "$skill" "$LEDGER_REL" 2>/dev/null || printf '%s\n' "$skill" >> "$LEDGER_REL" 2>/dev/null || true
    # 이 스킬이 무엇을 봤는지 내용 주소로 붙잡는다. 원장(무엇을 돌렸나)만으로는
    # "리뷰 한 번 돌리고 그 뒤로 계속 쓰기" 를 구분할 수 없다.
    _snapshot_covered "$skill"
}

# ── 변경을 분석해 전역에 채운다. **명령치환으로 호출하지 않는다**: 서브셸이면 전역이 안 남는다.
#    반환 1 = 범위를 정할 수 없거나 impact 계산 실패 → 호출자는 fail-open 한다.
# impact-score JSON 한 줄 → "<track> <필수 스킬들>". 트랙 추출과 정책 적용이 두 군데로
# 갈라지지 않게 한 곳에 둔다(전체 범위와 미검토분에 같은 기준을 쓴다).
_track_and_required() {
    local j="$1" t
    t="$(_json_field "$j" track_floor)"
    printf '%s\t%s' "$t" \
        "$(required_skills "$t" "$(_json_field "$j" db)" "$(_json_field "$j" auth)" "$(_json_field "$j" ext)")"
}

REVIEW_TRACK=""; REVIEW_JSON=""; REVIEW_REQUIRED=""; REVIEW_MISSING=""; REVIEW_RANGE=""; REVIEW_DETAIL=""
# 차단 사유. 효능 원장에서 둘을 갈라 봐야 "엄격해진 기본값이 오탐 차단을 늘리고 있는가"를
# 논쟁이 아니라 데이터로 답할 수 있다. 그게 안 보이면 safe-by-default 가 조용히
# ignored-by-default 로 바뀌는 것(우회 파일의 상습 사용)을 알아채지 못한다.
#   missing = 그 스킬이 이 작업 트리에서 돈 기록이 없다
#   scope   = 돌긴 했는데 그 호출이 이 트리를 보지 않았다(원격 PR, 다른 worktree 등)
#   stale   = 보긴 했는데 그 뒤에 코드를 더 썼다 (가장 흔하다. 이걸 scope 와 섞으면
#             "커버리지 판정이 엄격한가"를 그 수치로 판단할 수 없다)
REVIEW_BLOCK_KIND=""
_analyze() {
    local ref="${1:-}" json tr s missing="" detail="" p sp=()
    local sig total paths=() key rj rt rreq cache_key="" cache_rt="" cache_rreq=""
    REVIEW_BLOCK_KIND=""
    # 범위와 경로 제한(SCOPE_PATHS)은 호출자가 _push_scope 로 정한다. 여기서 다시 구하지 않는다.
    [ -z "$ref" ] && return 1
    REVIEW_RANGE="$ref"
    [ "${#SCOPE_PATHS[@]}" -gt 0 ] && sp=(-- "${SCOPE_PATHS[@]}")

    # 트랙은 **범위 전체**로 정한다. 이 push 가 공유하는 작업 전체가 요구 수준을 정한다.
    json="$(bash "$IMPACT" score "$ref" ${sp[@]+"${sp[@]}"} 2>/dev/null)" || return 1
    [ -z "$json" ] && return 1
    tr="$(_track_and_required "$json")"
    REVIEW_JSON="$json"
    REVIEW_TRACK="${tr%%	*}"
    REVIEW_REQUIRED="${tr#*	}"

    # 범위 파일과 그 HEAD blob 해시는 스킬 수와 무관하게 한 번만 구한다.
    sig="$(_range_signature "$ref")"
    total="$(printf '%s' "$sig" | grep -c '' 2>/dev/null || echo 0)"

    # 충족 여부는 스킬마다 따로 본다. 원장(무엇을 돌렸나)만 대조하면 두 가지가 샌다:
    #   - /simplify 만 돌리고 /code-review 를 건너뛴 push
    #   - 리뷰를 한 번 돌린 뒤 계속 새로 써서 push
    for s in $REVIEW_REQUIRED; do
        paths=()
        while IFS= read -r p; do [ -n "$p" ] && paths+=("$p"); done < <(_uncovered_paths "$s" "$sig")
        [ "${#paths[@]}" -eq 0 ] && continue

        # 미검토분 자체가 그 스킬을 요구하지 않는 수준(Trivial/Small)이면 통과시킨다.
        # 리뷰 지적을 반영한 한 줄까지 재리뷰를 요구하면 옛 게이트의 소음이 그대로 돌아온다.
        # 판정 기준은 required_skills 그대로다: 정책의 단일 출처를 여기서도 재사용한다.
        if [ "${#paths[@]}" -eq "$total" ]; then
            # 아무것도 검토되지 않았다: 미검토분 = 범위 전체라 이미 계산한 값과 같다.
            rt="$REVIEW_TRACK"; rreq="$REVIEW_REQUIRED"
        else
            # 스킬들은 대개 같은 미검토 집합을 갖는다. 직전 결과를 재사용해 중복 실행을 막는다.
            key="$(printf '%s\n' "${paths[@]}")"
            if [ "$key" = "$cache_key" ]; then
                rt="$cache_rt"; rreq="$cache_rreq"
            else
                rj="$(bash "$IMPACT" score "$ref" -- "${paths[@]}" 2>/dev/null)" || return 1
                tr="$(_track_and_required "$rj")"
                rt="${tr%%	*}"; rreq="${tr#*	}"
                cache_key="$key"; cache_rt="$rt"; cache_rreq="$rreq"
            fi
        fi
        case " $rreq " in
            *" $s "*) ;;
            *) continue ;;
        esac

        missing="$missing $s"
        # 사유는 엄격한 순으로 덮어쓴다: missing > scope > stale.
        if ! grep -qxF "$s" "$LEDGER_REL" 2>/dev/null; then
            REVIEW_BLOCK_KIND="missing"                       # 아예 안 돌았다
        elif grep -qxF "$s" "$NOSCOPE_REL" 2>/dev/null; then
            [ "$REVIEW_BLOCK_KIND" = "missing" ] || REVIEW_BLOCK_KIND="scope"   # 돌았으나 딴 데를 봤다
        else
            [ -n "$REVIEW_BLOCK_KIND" ] || REVIEW_BLOCK_KIND="stale"            # 보고 나서 더 썼다
        fi
        detail="${detail}  - /${s}: 이 스킬이 보지 않은 파일 ${#paths[@]}개 (그 자체로 ${rt})
"
    done
    REVIEW_MISSING="${missing# }"
    REVIEW_DETAIL="$detail"
    return 0
}

# 게이트가 판정을 못 해 그냥 통과시킨 순간을 원장에 남긴다.
# 의도적 우회(_bypassed)만 감사하고 이쪽을 침묵시키면, 가장 감사가 필요한 경우
# ("게이트가 조용히 아무 일도 하지 않았다")가 "리뷰가 필요 없었다"와 구별되지 않는다.
_record_fail_open() {
    local rec="$GATE_DIR/efficacy-recorder.sh"
    echo "MangoLove review gate: 판정 범위를 정할 수 없어 통과시킵니다 (fail-open, 감사 대상)${1:+: $1}" >&2
    if [ -f "$rec" ]; then bash "$rec" record-skip review "fail-open" 2>/dev/null || true; fi
}

# 우회 처리. 통과시키면 0, 우회가 아니면 1. (pretooluse 와 prepush 가 공유한다.)
_bypassed() {
    local rec="$GATE_DIR/efficacy-recorder.sh"
    if [ "${MANGOLOVE_SKIP_REVIEW:-}" = "1" ]; then
        echo "MangoLove review gate: MANGOLOVE_SKIP_REVIEW=1 (게이트 우회, 감사 대상)" >&2
        # 문서가 "감사됨"이라 적어놓고 정작 원장에 남기지 않았다. 세 우회 중 이것만
        # mangolove efficacy 에서 보이지 않아, 껐다는 사실이 측정에서 사라졌다.
        if [ -f "$rec" ]; then bash "$rec" record-skip review "env" 2>/dev/null || true; fi
        return 0
    fi
    # 환경변수 우회는 mangolove 실행 **전에** export 돼 있어야 한다. 훅은 Claude Code
    # 프로세스의 환경에서 뜨므로, 명령 앞에 붙인 VAR=1 은 훅에 닿지 않는다. 세션 도중
    # 우회해야 할 때를 위해 에이전트가 직접 쓸 수 있는 파일 경로를 둔다(1회용, 감사됨).
    if [ -f "$SKIP_REL" ] && _ml_tracked "$SKIP_REL"; then
        echo "MangoLove review gate: .mangolove/.review-skip 이 git 에 추적되고 있습니다." >&2
        echo "  우회 파일은 추적될 수 없습니다. 브랜치가 실어 온 위조본으로 보고 무시합니다." >&2
        echo "  의도한 우회라면 git rm --cached 후 다시 touch 하세요." >&2
    elif [ -f "$SKIP_REL" ]; then
        local why; why="$(head -c 400 "$SKIP_REL" 2>/dev/null | tr '\n' ' ')"
        # 소비는 항상 여기서 한다. 뒤 게이트는 위 USED_REL 주석의 시간 창으로 이어받는다.
        rm -f "$SKIP_REL" 2>/dev/null || true
        # 상태 디렉토리는 record 만 만든다. 리뷰를 한 번도 안 돌린 세션에서도 우회는 쓰인다.
        mkdir -p "$(dirname "$USED_REL")" 2>/dev/null || true
        _ensure_regular_file "$USED_REL" 2>/dev/null || true
        date +%s > "$USED_REL" 2>/dev/null || true
        echo "MangoLove review gate: .mangolove/.review-skip 으로 1회 우회 (감사 대상)" >&2
        [ -n "${why// /}" ] && echo "  근거: $why" >&2
        # 우회는 차단이 아니다. block 으로 적으면 "리뷰 미실행 push 차단" 수치가 부풀어,
        # 그 수치로 게이트가 실제로 무엇을 막았는지 판단할 수 없게 된다.
        if [ -f "$rec" ]; then bash "$rec" record-skip review "bypassed" 2>/dev/null || true; fi
        return 0
    fi
    return 1
}

# 사람이 읽을 범위 표기. 기준이 sha 면 그 커밋을 가진 원격 ref 이름으로 바꾼다(origin/develop~2).
_range_label() {
    local a="${1%%...*}" b="${1##*...}" n
    case "$a" in
        ''|*[!0-9a-f]*) ;;
        *) n="$(git name-rev --name-only --no-undefined --refs='refs/remotes/*' "$a" 2>/dev/null)" \
               && a="${n#remotes/}" ;;
    esac
    printf '%s...%s' "$a" "$b"
}

# 차단 사유를 stderr 로 낸다. 호출자가 종료코드를 정한다(훅 종류마다 다르다).
_emit_block() {
    {
        echo "--- MangoLove review gate: push 차단 ---"
        echo "이 변경의 트랙은 코드가 계산했습니다(모델 추정 아님): ${REVIEW_TRACK}"
        echo "  판정 범위 $(_range_label "$REVIEW_RANGE") (원격에 아직 없는 커밋이 더하는 변경)"
        echo "  ${REVIEW_JSON}"
        echo ""
        echo "${REVIEW_TRACK} 트랙에 필요한 리뷰 중 아직 이 내용을 보지 않은 것:"
        printf '%s' "${REVIEW_DETAIL}"
        echo ""
        case "$REVIEW_BLOCK_KIND" in
            missing)
                echo "이 스킬들은 이 작업 트리에서 실행된 기록이 없습니다. 그냥 실행하세요."
                echo "사용자에게 묻지 마세요: 물어야 할 결정이 아니라 하면 되는 일입니다."
                ;;
            scope)
                echo "스킬은 돌았지만 그 호출이 이 트리를 보지 않았습니다"
                echo "  (원격 PR 번호나 링크, 다른 작업 트리 경로, 갈라진 다른 브랜치만 짚은 경우)."
                echo "강도만 주거나(/code-review high) 이 트리의 경로를 짚어 다시 돌리세요."
                ;;
            *)
                echo "스킬은 이 내용을 봤지만 그 뒤에 코드가 더 들어왔습니다."
                echo "델타가 사소하면 근거를 남기고 스스로 우회하세요. 이것도 묻지 마세요."
                echo "  방법 1: Write 도구로 ${SKIP_REL} 파일에 근거를 적는다"
                echo "          (권한이 필요 없어 실행 중인 세션에서도 바로 됩니다)"
                echo "  방법 2: cd \"$PWD\" && mangolove review skip \"<무엇을 리뷰했고 델타가 무엇인지>\""
                echo "델타가 사소하지 않으면 다시 돌리는 편이 낫습니다."
                ;;
        esac
        echo "부족분 확인: mangolove review status"
        echo "(우회는 효능 원장에 남습니다. MANGOLOVE_SKIP_REVIEW=1 은 mangolove 실행 전에"
        echo " export 돼 있어야 합니다: 명령 앞에 붙인 값은 훅에 닿지 않습니다.)"
    } >&2
    local rec="$GATE_DIR/efficacy-recorder.sh"
    if [ -f "$rec" ]; then bash "$rec" record-block review "${REVIEW_BLOCK_KIND:-missing}" 2>/dev/null || true; fi
}

# rev 하나를 현재 디렉토리의 레포에서 판정한다. 0 통과(판정 불가면 감사를 남기고 통과), 1 차단.
# PreToolUse 와 pre-push 가 같은 순서를 공유한다: 두 벌이면 fail-open 사유와 통과 문구가 갈라진다.
_judge_rev() {
    _push_scope "$1" "${2:-}"
    [ -n "$SCOPE_RANGE" ] || { _record_fail_open; return 0; }
    # 새 커밋이 없다: 공유할 내용이 없으므로 점수화할 것도 없다(점수화 한 번이 100ms 를 넘는다).
    [ "${SCOPE_RANGE%%...*}" = "${SCOPE_RANGE##*...}" ] && return 0
    _analyze "$SCOPE_RANGE" || { _record_fail_open; return 0; }
    if [ -z "$REVIEW_MISSING" ]; then
        # 통과. 원장은 여기서 지우지 않는다: push 가 실제로 성공했는지 알 수 없기 때문이다.
        [ -z "$REVIEW_REQUIRED" ] || echo "MangoLove review gate: ${REVIEW_TRACK} 필수 리뷰 충족 (${REVIEW_REQUIRED})" >&2
        return 0
    fi
    _emit_block
    return 1
}

# ── pretooluse: git push 경계에서만 게이트. 한 명령의 push 가 여럿이면 전부, 각자 실제 레포에서 본다.
# gh pr create 는 보지 않는다. 내용을 올리지 않고(비대화형에서 push 를 대신하지 않는다), 이미 올라간
# 브랜치는 원격 추적 ref 가 갱신돼 범위가 늘 비므로 막을 수 있는 대상이 없다.
do_pretooluse() {
    local input raw dir rev gd top rc key seen=$'\n' bypassed=$'\n' blocked=0 parsed=0 unknown=0
    # read -d '' 는 builtin 이라 cat 의 포크를 없앤다. NUL 이 없으면 1 을 반환하나
    # 그때도 읽은 내용은 input 에 담긴다.
    IFS= read -r -d '' input || true
    raw="$(_json_str "$input" command)"
    # 대부분의 Bash 호출은 push 가 아니다. 포크 없이 글자로 먼저 거르고, 판정은 파서에 맡긴다.
    # 정규식으로 엄격하게 거르면 정규식이 모르는 모양이 파서에 닿기도 전에 조용히 빠져나간다.
    case "$raw" in *push*) ;; *) exit 0 ;; esac
    _cd_to_hook_cwd "$input"

    while IFS=$'\t' read -r dir rev; do
        [ -n "$dir" ] || continue
        if [ "$dir" = "!" ]; then parsed=1; continue; fi
        if [ "$dir" = "?" ]; then unknown=1; continue; fi
        # 레포 식별은 git 한 번: git-dir 은 상태 경로, toplevel 은 판정 위치이자 레포 키다.
        gd=""; top=""
        { read -r gd; read -r top; } < <(git -C "$dir" rev-parse --absolute-git-dir --show-toplevel 2>/dev/null)
        # 비-git 디렉토리에서는 진짜 push 가 실패한다. 판정이 여기 닿았다면 파서가 디렉토리를 잘못 풀었다는
        # 뜻이므로 조용히 넘기지 않고 감사한다.
        if [ -z "$top" ]; then unknown=1; continue; fi
        # 같은 명령에서 같은 레포, 같은 커밋은 한 번만 본다(PreToolUse 는 실행 전이라 둘이 같은 상태다).
        key="${top}"$'\t'"${rev}"
        case "$seen" in *$'\n'"$key"$'\n'*) continue ;; esac
        seen="${seen}${key}"$'\n'
        # 이 레포의 1회 우회를 이미 썼으면 그 레포의 나머지 push 도 그 우회에 든다.
        case "$bypassed" in *$'\n'"$top"$'\n'*) continue ;; esac
        # 판정은 레포 루트에서 한다. 범위의 경로는 루트 기준이라, 하위 디렉토리(cd sub && git push)에서
        # 판정하면 경로 제한이 한 건도 안 맞아 미검토 변경이 조용히 통과했다.
        ( cd "$top" 2>/dev/null || exit 0
          _ml_init_state "$gd" "$top"
          _bypassed && exit 3
          _judge_rev "$rev" ); rc=$?
        case "$rc" in
            1) blocked=1 ;;
            3) bypassed="${bypassed}${top}"$'\n' ;;
        esac
    done < <(_push_targets "$(_json_unescape "${raw}\\n${PARSER_END}" nl)" "$PWD")

    # 파서가 끝까지 돌지 못하면(awk 문법 오류 등) 판정할 push 가 하나도 안 나와 전부 조용히 통과한다.
    # 실제로 그랬다(awk 예약어 sub 를 인자 이름으로 써서 게이트 전체가 꺼졌다). 완료 표시는 JSON 풀기부터
    # 모든 단계를 지나야 나오므로, 어느 단계가 죽어도 감사로 남는다. 판정 불가는 명령당 한 번만 적는다.
    if [ "$parsed" = 0 ] || [ "$unknown" = 1 ]; then
        _record_fail_open "push 대상 레포나 커밋을 명령에서 정할 수 없음"
    fi
    [ "$blocked" -eq 1 ] && exit 2
    exit 0
}

# ── prepush: .githooks/pre-push 용. Claude Code 밖의 터미널 push 도 같은 규칙으로 막는다.
#
#    git 은 stdin 으로 "<local ref> <local sha> <remote ref> <remote sha>" 를 준다. 이것이
#    무엇을 push 하는지에 대한 **유일한 권위 있는 정보**다. 현재 브랜치를 가정하면
#    `git push origin other:main`, `--tags`, detached HEAD 에서 엉뚱한 범위를 본다.
#    git 이 부른 경우($# >= 2: 원격 이름 + URL)에는 stdin 만 믿는다. 올릴 것이 없으면
#    stdin 이 비고, 그때는 공유되는 내용도 없으므로 통과다.
do_prepush() {
    local from_git=0 lref lsha rref rsha blocked=0 saw=0 _used
    [ "$#" -ge 2 ] && from_git=1
    git rev-parse --git-dir >/dev/null 2>&1 || exit 0
    _ml_init_state
    _bypassed && { rm -f "$USED_REL" 2>/dev/null || true; exit 0; }
    # 앞선 게이트가 방금 이 공유를 우회로 통과시켰으면 여기서 또 막지 않는다.
    # 표시는 무조건 지운다: 남겨 두면 다음 push 까지 무료로 통과시킨다.
    if [ -f "$USED_REL" ]; then
        _used="$(cat "$USED_REL" 2>/dev/null)"
        rm -f "$USED_REL" 2>/dev/null || true
        case "$_used" in
            ''|*[!0-9]*) ;;
            *) if [ "$(( $(date +%s) - _used ))" -le "$SKIP_HANDOFF_SECONDS" ]; then
                   echo "MangoLove review gate: 직전 우회를 이어받아 통과 (감사 대상)" >&2
                   exit 0
               fi ;;
        esac
    fi

    # lref/rref 는 git 이 주는 4개 필드 중 쓰지 않는 두 개다. 이름을 남겨 두어야
    # 필드 순서를 헷갈리지 않는다.
    # shellcheck disable=SC2034
    while read -r lref lsha rref rsha; do
        [ -n "${lsha:-}" ] || continue
        saw=1
        # local sha 가 전부 0 = 원격 ref 삭제. 내용을 공유하지 않는다.
        case "$lsha" in *[!0]*) ;; *) continue ;; esac
        # 원격이 이미 가진 것 이후가 새 것이다. git 이 준 원격 sha 는 fetch 전이라 추적 ref 에
        # 없을 수 있어 함께 뺀다. 새 ref(원격 sha 가 0)라도 트렁크를 가정하지 않는다.
        case "${rsha:-}" in *[!0]*) ;; *) rsha="" ;; esac
        _judge_rev "$lsha" "$rsha" || blocked=1
    done

    if [ "$blocked" -eq 1 ]; then exit 1; fi
    # git 이 부른 게 아니고(수동 진단) stdin 도 비었으면 현재 브랜치를 본다.
    if [ "$from_git" -eq 0 ] && [ "$saw" -eq 0 ]; then
        _judge_rev HEAD || exit 1
    fi
    exit 0
}

# ── skip: 1회용 우회 마커를 근거와 함께 남긴다.
# 왜 CLI 로 두나: 안내문이 `touch .mangolove/.review-skip` 를 시키는데 에이전트가 그 명령을
# 실행하지 못하면, 차단이 전부 사용자 호출이 된다(실제로 그렇게 됐다). 게이트가 시키는 일은
# 게이트를 설치한 도구가 할 수 있게 해야 한다. 근거를 인자로 받아 효능 원장에 함께 남긴다.
do_skip() {
    local reason="${*:-}"
    git rev-parse --git-dir >/dev/null 2>&1 || { echo "review-gate: git 저장소가 아닙니다" >&2; exit 1; }
    _ml_init_state
    [ -n "$reason" ] || { echo "usage: mangolove review skip \"<근거>\"" >&2; exit 2; }
    mkdir -p "$(dirname "$SKIP_REL")" 2>/dev/null || true
    # 워킹트리에 남는 유일한 상태 파일이라 브랜치가 심볼릭 링크를 실어 올 수 있다.
    # 링크를 따라가면 레포 밖 파일을 덮어쓴다(이 명령은 권한까지 자동 허용돼 있다).
    if _ml_tracked "$SKIP_REL"; then
        echo "review-gate: ${SKIP_REL} 이 git 에 추적되고 있습니다. 위조본으로 보고 거부합니다." >&2
        exit 1
    fi
    _ensure_regular_file "$SKIP_REL" || { echo "review-gate: 마커 경로가 정상 파일이 아닙니다" >&2; exit 1; }
    _ml_seed_gitignore
    printf '%s\n' "$reason" > "$SKIP_REL" 2>/dev/null || { echo "review-gate: 마커를 쓸 수 없습니다" >&2; exit 1; }
    local rec="$GATE_DIR/efficacy-recorder.sh"
    if [ -f "$rec" ]; then bash "$rec" record-skip review "requested" 2>/dev/null || true; fi
    echo "MangoLove review gate: 다음 1회를 우회합니다 (감사 대상)" >&2
    echo "  근거: $reason" >&2
}

# ── status: 사람용 진단. 인자가 없으면 게이트가 실제로 볼 push 범위를 그대로 보여준다.
do_status() {
    local ref="${1:-}" gd="" top=""
    # 판정은 레포 루트에서 한다(범위의 경로가 루트 기준이다: do_pretooluse 주석).
    { read -r gd; read -r top; } < <(git rev-parse --absolute-git-dir --show-toplevel 2>/dev/null)
    if [ -n "$top" ]; then cd "$top" || exit 1; fi
    _ml_init_state "$gd" "$top"
    # _range_signature 는 A...B 만 이해한다. sha 나 --working 을 넘기면 서명이 비어
    # 모든 스킬이 충족으로 보이는 **거짓 PASS** 가 난다. 아예 받지 않는다.
    case "$ref" in
        ""|*...*) ;;
        *) echo "review-gate: status 는 범위(A...B)만 받습니다. 인자 없이 부르면 push 범위를 봅니다." >&2
           exit 2 ;;
    esac
    if [ -z "$ref" ]; then _push_scope HEAD; ref="$SCOPE_RANGE"; else SCOPE_PATHS=(); fi
    if ! _analyze "$ref"; then
        echo "review-gate: 판정 범위를 정할 수 없습니다 (원격 추적 ref 가 있는지 확인: git fetch)" >&2
        exit 1
    fi
    echo "Review gate: $(_range_label "$REVIEW_RANGE")  (원격에 아직 없는 커밋이 더하는 변경)"
    echo "  계산된 트랙: ${REVIEW_TRACK}"
    echo "  필수 리뷰: ${REVIEW_REQUIRED:-(없음)}"
    if [ -f "$LEDGER_REL" ]; then
        echo "  실행된 스킬 기록: $(tr '\n' ' ' < "$LEDGER_REL")"
    else
        echo "  실행된 스킬 기록: (없음)"
    fi
    if [ -z "$REVIEW_MISSING" ]; then
        echo "  판정: PASS"
    else
        echo "  판정: BLOCK, 부족: ${REVIEW_MISSING}"
        printf '%s' "${REVIEW_DETAIL}"
    fi
}

main() {
    case "${1:-}" in
        record)     do_record ;;
        pretooluse) do_pretooluse ;;
        prepush)    shift; do_prepush "$@" ;;
        skip)       shift; do_skip "$@" ;;
        required)   required_skills "${2:-}" "${3:-false}" "${4:-false}" "${5:-false}"; echo ;;
        status)     do_status "${2:-}" ;;
        *) echo "usage: review-gate.sh {record|pretooluse|prepush|skip <근거>|required <track> <db> <auth> <ext>|status [ref]}" >&2; exit 2 ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
