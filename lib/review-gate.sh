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
# 범위는 세 점(<upstream>...HEAD)이다. merge base 가 두 가지를 공짜로 해결한다:
#   - 이미 upstream 에 있는 브랜치를 머지해도 그 내용은 범위에서 자동으로 빠진다
#     (머지 커밋 특별처리 코드가 필요 없다)
#   - upstream 에 없는(= 어디서도 검토되지 않은) 브랜치를 머지하면 그 내용은 범위에 남는다
#     (미검토 코드가 머지로 숨지 못한다)
# 그리고 범위는 커밋 개수와 무관하므로, 작은 커밋으로 쪼개 누적 우회하는 길이 막힌다.
#
# 두 개의 훅으로 동작한다 (bare mangolove 세션에 claude --settings 로 주입):
#   PostToolUse(matcher=Skill) → review-gate.sh record
#       실제로 실행된 스킬만 원장에 남는다. 모델의 자기보고가 아니라 도구 호출 사실이다.
#       동시에 그 시점 작업 내용을 blob 해시로 스냅샷한다(아래 "커버리지").
#   PreToolUse(matcher=Bash)   → review-gate.sh pretooluse
#       git push (또는 gh pr create) 일 때만 발화. 범위에서 리뷰가 이미 본 내용을 뺀
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
# 원장이 어느 세션의 것인지 기록한다. 어제 돌린 리뷰가 오늘의 첫 push 를 통과시키면 안 된다.
# HEAD 로는 무효화하지 **않는다**: push 경계에서는 HEAD 가 커밋마다 움직이므로 HEAD 기준
# 무효화는 사실상 항상 원장을 지워 모든 push 를 막는다. 리뷰의 유효 범위는 HEAD 가 아니라
# 아래 커버리지 파일(내용 주소)이 정한다.
LEDGER_BASE_REL=".mangolove/.review-ledger.base"
# 리뷰가 본 내용: "<스킬>\t<blob 해시>\t<경로>" 줄들. 세션 스코프.
COVERED_REL=".mangolove/.review-covered"
# 세션 도중 쓸 수 있는 1회용 우회 파일. 환경변수 우회는 훅에 닿지 않기 때문에 필요하다.
# 이것만은 워킹트리에 남긴다: 사람이 직접 touch 하는 경로라 안내문에 적히기 때문이다.
# 대신 추적된 사본은 신뢰하지 않는다(_ml_tracked).
SKIP_REL=".mangolove/.review-skip"

# cwd 가 정해진 뒤 상태 경로를 확정한다. git-dir 을 못 구하면(비-git) 워킹트리 기본값을
# 그대로 쓰는데, 그 경우는 어차피 게이트가 fail-open 한다.
_ml_init_state() {
    STATE_DIR="$(_ml_state_dir)"
    [ -n "$STATE_DIR" ] || return 0
    LEDGER_REL="$STATE_DIR/.review-ledger"
    LEDGER_BASE_REL="$STATE_DIR/.review-ledger.base"
    COVERED_REL="$STATE_DIR/.review-covered"
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

# tool_input.command 는 JSON 문자열이라 개행이 역슬래시+n 두 글자로 온다. 그대로 정규식에
# 태우면 둘째 줄 git 앞 글자가 'n'(영숫자)이라 단어 경계에 걸리지 않고, 멀티라인 명령이
# 통째로 게이트를 빠져나간다(실측: 이 머신의 실제 커밋 호출 411건 중 84건, 20%).
# 실제 개행으로 되돌린 뒤 grep 이 줄 단위로 보게 한다.
_unescape_cmd() { printf '%s' "$1" | awk '{gsub(/\\n/,"\n"); gsub(/\\t/," "); print}'; }

# git 을 단어 경계로 잡고 옵션 토큰을 건너뛴 뒤 push 서브커맨드만 매칭한다
# (git log --grep=push 같은 비-push 는 통과). gh pr create 도 같은 경계다: 그 시점에
# 작업이 공유된다.
GIT_PUSH_RE='(^|[^[:alnum:]_])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-][^[:space:]]*)?)*[[:space:]]+push([[:space:]]|$)'
GH_PR_RE='(^|[^[:alnum:]_])gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)'

# heredoc 본문을 매칭 대상에서 뺀다. 게이트는 셸을 파싱하지 않고 명령 **문자열**을 보므로,
# `python3 - <<PY ... PY` 로 넘긴 스크립트 본문에 "git push" 라는 글자가 있으면 그것을
# 명령으로 오인해 무관한 작업을 막는다(실제로 다른 레포 작업 중에 반복해서 걸렸다).
#
# 다만 **셸이 소비하는 heredoc 은 벗기지 않는다**: `bash <<EOF ... EOF` 의 본문은 데이터가
# 아니라 실행되는 코드라, 벗기면 진짜 push 가 통째로 새어 나간다. 소비하는 명령이 셸인지로
# 가른다. 판별이 애매하면 벗기지 않는다(막는 쪽 = 안전한 쪽).
_strip_heredocs() {
    printf '%s\n' "$1" | awk '
        {
            if (in_hd) {
                line = $0
                if (dash) sub(/^\t+/, "", line)
                if (line == marker) { in_hd = 0; print; next }
                if (strip) next
                print; next
            }
            if (match($0, /<<-?[ \t]*("[^"]+"|\047[^\047]+\047|[A-Za-z_][A-Za-z0-9_]*)/)) {
                tok = substr($0, RSTART, RLENGTH)
                dash = (tok ~ /^<<-/)
                m = tok
                sub(/^<<-?[ \t]*/, "", m)
                gsub(/["\047]/, "", m)
                marker = m
                in_hd = 1
                strip = ($0 ~ /(^|[^[:alnum:]_])(bash|sh|zsh|dash|ksh|eval)([ \t]|$)/) ? 0 : 1
            }
            print
        }'
}

# 명령을 셸 구분자에서 쪼개 **명령 하나당 한 줄**로 만든다.
# 줄 단위로만 보면 `git push --dry-run && git push origin main` 이 한 줄이라, 앞의
# dry-run 만 보고 뒤의 진짜 push 를 통째로 놓친다. 쪼갠 뒤 세그먼트마다 판정한다.
# (같은 이유로 `git push origin main && echo -n done` 의 -n 도 다른 세그먼트라 안 섞인다.)
_split_segments() { printf '%s\n' "$1" | awk '{gsub(/&&|\|\||;|\|/, "\n"); print}'; }

# --dry-run 은 아무 것도 공유하지 않으므로 게이트 대상이 아니다 (-n 은 push 의 dry-run 별칭).
_is_dry_run() {
    printf '%s' "$1" | grep -qE '(^|[[:space:]])(--dry-run|-[a-zA-Z]*n[a-zA-Z]*)([[:space:]]|$)'
}

# 원격 브랜치 삭제는 내용을 공유하지 않는다 (-d 는 --delete 의 짧은 형태).
_is_delete() {
    printf '%s' "$1" | grep -qE '(^|[[:space:]])(--delete|-[a-zA-Z]*d[a-zA-Z]*)([[:space:]]|$)'
}

# 게이트 대상이 되는 push 세그먼트 하나를 출력한다(없으면 빈 출력).
_gated_push_line() {
    _split_segments "$(_strip_heredocs "$1")" | grep -E "$GIT_PUSH_RE|$GH_PR_RE" | while IFS= read -r seg; do
        case "$seg" in
            *push*)
                if _is_dry_run "$seg" || _is_delete "$seg"; then continue; fi
                ;;
        esac
        printf '%s\n' "$seg"
    done | head -1
}

# 판정 범위: upstream 대비 이 브랜치의 순변경. upstream 이 없으면 기본 브랜치로 폴백한다.
# 빈 출력 = 범위를 정할 수 없음 → 호출자는 fail-open 한다(게이트가 작업을 인질로 잡지 않는다).
# 이 레포의 기본 비교 기준(원격 트렁크). 빈 출력 = 정할 수 없음.
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

_push_range() {
    local up def src dst base
    src="${1:-}"

    if [ -n "$src" ]; then
        # 명시된 refspec 이 있으면 그것이 실제로 올라가는 것이다.
        # `git push origin topic:main` 을 HEAD 로 가정하면 엉뚱한(대개 빈) 범위를 본다.
        dst="${src#*:}"; [ "$dst" = "$src" ] && dst=""
        src="${src%%:*}"; src="${src#+}"
        git rev-parse --verify --quiet "${src}^{commit}" >/dev/null 2>&1 || return 0
        base=""
        if [ -n "$dst" ]; then
            dst="${dst#refs/heads/}"
            git rev-parse --verify --quiet "origin/${dst}" >/dev/null 2>&1 && base="origin/${dst}"
        fi
        [ -z "$base" ] && base="$(_default_base)"
        [ -n "$base" ] && printf '%s...%s' "$base" "$src"
        return 0
    fi

    up="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)"
    if [ -n "$up" ] && git rev-parse --verify --quiet "$up" >/dev/null 2>&1; then
        printf '%s...HEAD' "$up"; return 0
    fi
    def="$(_default_base)"
    [ -n "$def" ] && printf '%s...HEAD' "$def"
    return 0
}

# push 세그먼트에서 refspec 을 뽑는다: 옵션을 건너뛰고 (원격, refspec) 중 두 번째 비-옵션.
# 못 찾으면 빈 출력 → 호출자는 현재 브랜치 기준으로 본다.
_push_source_ref() {
    printf '%s' "$1" | awk '
        { for (i = 1; i <= NF; i++) if ($i == "push") { start = i + 1; break } }
        start {
            n = 0
            for (i = start; i <= NF; i++) {
                if ($i ~ /^-/) continue
                n++
                if (n == 2) { print $i; exit }
            }
        }'
}

# JSON 문자열 이스케이프를 되돌린다. args 에는 사람이 친 인용부호와 경로가 그대로 들어오는데
# 훅에는 \" \\ \n 형태로 escape 되어 도착한다. 되돌리지 않으면 `/code-review "a b.js"` 의
# 토큰이 실제 파일명과 영영 달라 경로 지정이 무시되고, 그러면 **전체가 covered 된다**(조용한 통과).
# command 에는 _unescape_cmd 가 같은 일을 한다. args 에만 빠져 있었다.
# 한 번의 좌->우 스캔으로 처리한다: \\n 을 개행으로 오해하지 않으려면 순차 치환이 아니어야 한다.
#
# _unescape_cmd 와 합치지 않는다. 같은 JSON 이스케이프를 풀지만 \n 의 목적지가 반대다:
# 저쪽은 **실제 개행**으로 되돌려야 멀티라인 명령을 줄 단위로 grep 할 수 있고(합치면 그
# 84/411 회귀가 되돌아온다), 이쪽은 **공백**으로 만들어야 args 가 한 줄 토큰 흐름이 된다.
# 저쪽은 \" 와 \\ 를 건드리지 않는데, 이쪽에서 그러면 인용부호가 파일명과 어긋나 조용히
# 전체를 covered 시킨다. 목적지가 갈리는 만큼 각자 두고, 합치려면 매핑을 인자로 받는
# 하위 프리미티브를 따로 만들어야 한다.
_json_unescape() {
    printf '%s' "$1" | awk '{
        out = ""; n = length($0)
        for (i = 1; i <= n; i++) {
            c = substr($0, i, 1)
            if (c == "\\" && i < n) {
                i++; d = substr($0, i, 1)
                if (d == "n" || d == "t" || d == "r") out = out " "
                else out = out d
            } else out = out c
        }
        print out
    }'
}

# args 를 셸처럼 토큰으로 쪼갠다(한 줄에 하나). 인용부호는 묶음으로 인정하고 제거한다.
# 단순 공백 분리로는 `/code-review "a b.js"` 가 ["a, b.js"] 로 갈라져 어느 것도 실제
# 파일명과 같지 않고, 그러면 경로 지정이 통째로 무시되어 **전체가 covered 된다**(조용한 통과).
# eval 하지 않는다: args 는 외부 입력이고, 여기서 필요한 것은 실행이 아니라 분해뿐이다.
_tokenize_args() {
    printf '%s' "$1" | awk '{
        n = length($0); tok = ""; inq = ""
        for (i = 1; i <= n; i++) {
            c = substr($0, i, 1)
            if (inq != "") {
                if (c == inq) inq = ""; else tok = tok c
            } else if (c == "\"" || c == "'"'"'") {
                inq = c
            } else if (c == " " || c == "\t") {
                if (tok != "") { print tok; tok = "" }
            } else tok = tok c
        }
        if (tok != "") print tok
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
COVERAGE_PATHS=()     # paths 일 때만 채운다
_coverage_scope() {
    local args root refs tok saw_pr=0 saw_num=0
    COVERAGE_MODE=""; COVERAGE_PATHS=()
    args="$(_json_unescape "${1:-}")"
    [ -z "${args//[[:space:]]/}" ] && { COVERAGE_MODE="all"; return 0; }
    root="$(git rev-parse --show-toplevel 2>/dev/null)"; [ -n "$root" ] || root="$PWD"
    # ref 목록은 **한 번만** 뜬다. 토큰마다 git rev-parse 를 부르면 파일 목록을 넘긴 호출에서
    # fork 가 파일 수만큼 난다. HEAD 는 for-each-ref 에 없으므로 직접 넣는다.
    refs="HEAD
$(git for-each-ref --format='%(refname:short)' refs/heads refs/tags refs/remotes 2>/dev/null)"

    # **인자 전체가 알아볼 수 있는 것이어야** 범위를 인정한다. 하나라도 모르는 토큰이 있으면
    # 아무 것도 인정하지 않는다. 모르는 토큰을 "수식어겠지" 하고 무시했더니 두 가지가 샜다:
    #   - "review everything except lib" 의 lib 를 **커버 대상으로** 읽었다(부정을 긍정으로).
    #   - /code-review main 처럼 **다른 브랜치**를 리뷰한 호출이 전체를 커버했다.
    while IFS= read -r tok; do
        [ -n "$tok" ] || continue
        # 플래그는 **닫힌 목록만** 건너뛴다. 전부 건너뛰면 --pr=1952 처럼 원격 대상을 담은
        # 옵션이 유일하게 "모르는 토큰" 판정을 빠져나가, 이 트리를 보지 않은 리뷰가 전체를
        # 커버한다(실증됨). 스킬이 실제로 갖는 비-범위 플래그만 적는다.
        case "$tok" in
            --|--fix|--comment|--post|--no-post) continue ;;
            --*) COVERAGE_MODE="none"; return 0 ;;   # 대상을 품을 수 있다(--pr=1952)
        esac

        # 원격 참조 판정을 **경로 검사보다 먼저** 한다. 순서를 뒤집으면 이름이 겹치는 로컬
        # 경로가 원격 참조를 가린다: 공격자가 브랜치에 1952/ 나 main/ 디렉토리를 심어 두면
        # `/code-review 1952`(원격 PR 리뷰)가 그 디렉토리를 봤다고 기록된다(실증됨).
        case "$tok" in *://*) COVERAGE_MODE="none"; return 0 ;; esac
        if [[ "$tok" =~ ^[0-9]+$ ]]; then COVERAGE_MODE="none"; return 0; fi   # PR 번호
        case "$tok" in                                                          # crs#1891, #423
            *'#'[0-9]*) case "${tok##*#}" in *[!0-9]*) ;; *) COVERAGE_MODE="none"; return 0 ;; esac ;;
        esac
        # 경로로 풀리지 않는 /pull/ /merge_requests/ 는 원격 링크다(스킴이 없어도).
        # 실재하는 docs/pull/x 는 아래 경로 검사에서 먼저 잡히므로 여기 오지 않는다.
        if [ ! -e "$tok" ]; then
            case "$tok" in */pull/*|*/merge_requests/*) COVERAGE_MODE="none"; return 0 ;; esac
        fi
        # PR/MR 낱말과 숫자를 품은 토큰이 함께 있으면 원격 리뷰다("크스-1952 관련 PR 검토").
        case "$tok" in PR|pr|Pr|MR|mr|Mr) saw_pr=1 ;; esac
        case "$tok" in *[0-9]*) [ -e "$tok" ] || saw_num=1 ;; esac
        if [ "$saw_pr" = 1 ] && [ "$saw_num" = 1 ]; then COVERAGE_MODE="none"; return 0; fi
        case "
$refs
" in *"
$tok
"*) COVERAGE_MODE="none"; return 0 ;; esac                                     # 브랜치, 태그

        # 이 레포 안의 실재하는 경로. 절대경로는 레포 안일 때만 인정한다: 다른 worktree 도
        # 디스크에는 있으므로 존재만 보면 남의 코드를 본 리뷰가 통과한다.
        # (macOS 의 /tmp -> /private/tmp 처럼 show-toplevel 과 PWD 가 갈릴 수 있어 둘 다 본다.)
        case "$tok" in
            /*) case "$tok" in
                    "$root"|"$root"/*|"$PWD"|"$PWD"/*)
                        if [ -e "$tok" ]; then COVERAGE_PATHS+=("$tok"); continue; fi ;;
                    # 레포 밖 절대경로 = 남의 코드를 봤다. 산문 낱말과 달리 형태로 확정된다.
                    *) COVERAGE_MODE="none"; return 0 ;;
                esac
                continue ;;
            *)  if [ -e "$tok" ]; then COVERAGE_PATHS+=("$tok"); continue; fi ;;
        esac

        # 그 밖의 토큰(강도 지정, 산문 낱말)은 범위를 좁히지도 넓히지도 않는다. 무시한다.
        #
        # 한때 "모르는 토큰이 하나라도 있으면 아무 것도 인정하지 않는다"로 두었다. 그 결정은
        # 데이터 없이 내린 것이었고, 실측이 뒤집었다: 실사용 args 35종 중 33종(94%)이
        # 커버리지 0 이 됐다. 에이전트는 리뷰 스킬을 한국어 서술로 부른다
        # ("modules/.../X.sql 의 직전 커밋 변경분만"). 실재하는 경로를 짚었는데도 `의`,
        # `직전` 같은 낱말 때문에 통째로 무효가 되어, 게이트가 충족 불가능해지고 모든 차단이
        # 사용자 호출로 끝났다.
        #
        # 대신 **명확히 다른 대상을 가리키는 신호**(PR 번호, URL, git ref, 레포 밖 절대경로,
        # 값을 품은 --옵션)만 위에서 전체를 무효화한다. 그것들은 형태로 확정되지 알아맞히는
        # 것이 아니다. 남는 한계: "lib 는 빼고" 같은 부정문의 경로는 여전히 커버 대상으로
        # 읽힌다. 산문의 의미를 해석하지 않는 한 못 막는다. 그 과대 인정은 **짚은 경로 하나**로
        # 제한되고, 범위의 나머지는 여전히 미검토로 남는다.
    done <<TOKENS
$(_tokenize_args "$args")
TOKENS

    if [ "${#COVERAGE_PATHS[@]}" -gt 0 ]; then COVERAGE_MODE="paths"; return 0; fi
    # 강도뿐이거나 인자가 없다 = 스킬 기본 범위(워킹트리 전체 diff)를 본 것이다.
    COVERAGE_MODE="all"
    return 0
}

# 경로 제한(sp)이 있으면 pathspec 으로 붙여 git 을 부른다. 빈 배열 확장은 set -u 아래서
# 위험하므로 개수를 세고 분기한다. quotePath=false 는 비-ASCII 경로가 C-quote 되어
# push 시점 경로와 영영 어긋나는 것을 막는다(그러면 그 파일은 절대 covered 로 안 잡힌다).
_git_names() {
    # sp 는 호출자(_snapshot_covered)가 선언하는 pathspec 배열이다. 선언되지 않은 채로
    # 불리면 set -u 아래서 ${#sp[@]} 가 함수를 조용히 끝내고, 빈 출력은 "변경 파일 없음"과
    # 구별되지 않아 커버리지가 통째로 비게 된다(shellcheck 도 못 잡는다). 그래서 방어한다.
    local n=0
    [ "${sp+set}" = "set" ] && n="${#sp[@]}"
    if [ "$n" -gt 0 ]; then git -c core.quotePath=false "$@" -- "${sp[@]}" 2>/dev/null
    else git -c core.quotePath=false "$@" 2>/dev/null; fi
}

# 리뷰가 실제로 본 파일 내용을 blob 해시로 붙잡는다 (record 시점 = 스킬이 막 끝난 시점).
# 워킹트리 기준으로 해시를 뜬다: 리뷰는 커밋된 것이 아니라 지금 눈앞의 내용을 본다.
# 그 내용이 나중에 그대로 커밋되면 push 시점 HEAD blob 해시와 일치해 covered 로 잡힌다.
#
# **스킬 이름을 함께 적는다.** 내용만 적으면 스킬 하나만 돌려도 그 내용이 통째로 covered 가
# 되어, /simplify 만 돌리고 /code-review 를 건너뛴 push 가 통과한다(실제로 그랬다).
_snapshot_covered() {
    local skill="$1" args="${2:-}" range files present hashes f
    local sp=()
    # 명령치환으로 부르지 않는다: 서브셸이면 전역이 안 남는다(위 COVERAGE_MODE 주석).
    _coverage_scope "$args"
    # 이 스킬이 이 트리를 보지 않았다면 아무 것도 인정하지 않는다.
    if [ "$COVERAGE_MODE" = "none" ]; then
        # 왜 마커를 남기나: 이 스킬이 "돌긴 했지만 이 트리를 안 봤다"는 사실을 push 시점에
        # 알아야 차단 사유를 가를 수 있다. 원장 등재 여부만 보면 이 경우와 "리뷰 뒤에 코드를
        # 더 쓴 경우"(가장 흔한 차단)가 한 덩어리가 되어, 그 수치로는 커버리지 판정이
        # 엄격한지 아닌지 판단할 수 없다. blob 자리가 경로와 절대 안 맞아 판정에는 무해하다.
        _ensure_regular_file "$COVERED_REL" || return 0
        grep -qxF "$skill	_noscope	_noscope" "$COVERED_REL" 2>/dev/null \
            || printf '%s\t_noscope\t_noscope\n' "$skill" >> "$COVERED_REL" 2>/dev/null || true
        return 0
    fi
    # 짚은 경로가 있으면 git pathspec 으로 넘긴다. 손으로 "이 파일이 이 경로 아래인가"를
    # 짜면 후행 슬래시(lib/ -> lib//*)에서 아무것도 안 맞는 식으로 조용히 틀린다.
    # git 은 정확한 경로 또는 그 디렉토리 하위만 매칭하며(li 가 lib/ 를 오염시키지 않는다),
    # 없는 경로는 빈 결과로 조용히 끝난다.
    if [ "$COVERAGE_MODE" = "paths" ]; then
        sp=("${COVERAGE_PATHS[@]}")
        [ "${#sp[@]}" -eq 0 ] && return 0
    fi
    range="$(_push_range)"
    # quotePath=false: 위 _range_signature 와 같은 이유다. 여기서 따옴표 붙은 경로를 적으면
    # push 시점 경로와 영원히 어긋나 그 파일은 절대 covered 로 잡히지 않는다.
    files="$( {
        [ -n "$range" ] && _git_names diff --name-only "$range"
        _git_names diff --name-only HEAD
        _git_names ls-files --others --exclude-standard
    } | sort -u | grep -v '^$' )"
    [ -z "$files" ] && return 0

    # 존재하는 것과 사라진 것을 가른다(루프는 builtin 만 쓴다: fork 없음).
    present=""
    while IFS= read -r f; do
        [ -f "$f" ] && present="${present}${f}
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
                | awk -v s="$skill" -F'\t' 'NF>=2 {print s "\t" $1 "\t" $2}' \
                >> "$COVERED_REL" 2>/dev/null || true
        fi
    fi
    # 사라진 파일은 push 시점에도 _absent 로 계산되므로 같은 표기로 남긴다.
    printf '%s\n' "$files" | grep -vxF -f <(printf '%s' "$present") 2>/dev/null \
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
    git -c core.quotePath=false diff --raw --abbrev=40 "$1" 2>/dev/null | awk -F'\t' '
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

_head_sha() { git rev-parse HEAD 2>/dev/null || echo "_no-head"; }

# 원장의 유효 범위를 한 줄로 적는다: "<session_id>\t<head_sha>".
# 세션이 바뀌었으면 어제 돌린 리뷰가 오늘의 첫 push 를 통과시키면 안 된다.
# head_sha 는 진단용으로만 남긴다: 무효화 판단에는 쓰지 않는다(위 LEDGER_REL 주석 참조).
# session 인자가 비면 세션 비교를 건너뛴다(터미널 pre-push, status 처럼 세션이 없는 경로).
_ledger_stamp() { printf '%s\t%s' "${1:-}" "$(_head_sha)"; }

_drop_stale_ledger() {
    local session="${1:-}"
    [ -f "$LEDGER_REL" ] || [ -f "$COVERED_REL" ] || return 0
    [ -z "$session" ] && return 0
    local base="" b_session
    [ -f "$LEDGER_BASE_REL" ] && base="$(cat "$LEDGER_BASE_REL" 2>/dev/null)"
    b_session="${base%%	*}"
    [ "$b_session" = "$session" ] && return 0
    rm -f "$LEDGER_REL" "$LEDGER_BASE_REL" "$COVERED_REL" 2>/dev/null || true
}

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

# ── record: 실행된 스킬을 원장에 append (PostToolUse). 절대 실패로 turn 을 막지 않는다.
do_record() {
    local input skill session
    # read -d '' 는 builtin 이라 cat 의 포크를 없앤다. NUL 이 없으면 1 을 반환하나
    # 그때도 읽은 내용은 input 에 담긴다.
    IFS= read -r -d '' input || true
    _cd_to_hook_cwd "$input"
    _ml_init_state
    # 필드 이름은 런타임에서 실측했다: Skill 도구의 tool_input 은 {"skill":"simplify"} 다.
    # 훅 문서는 skill_name 이라고 적고 있어 양쪽을 다 받는다: 한쪽만 읽고 맞췄다가는
    # 원장이 영영 비어 Medium 이상 push 가 전부 막힌다(경계면 교차검증).
    # 두 패턴은 서로 오탐하지 않는다: "skill" 뒤에 곧바로 콜론이 와야 매칭된다.
    session="$(_json_str "$input" session_id)"
    skill="$(_json_str "$input" skill)"
    [ -z "$skill" ] && skill="$(_json_str "$input" skill_name)"
    [ -z "$skill" ] && exit 0
    skill="$(_normalize_skill "$skill")"
    mkdir -p "$(dirname "$LEDGER_REL")" 2>/dev/null || exit 0
    mkdir -p ".mangolove" 2>/dev/null || true
    _ensure_regular_file "$LEDGER_REL" || exit 0
    _ensure_regular_file "$LEDGER_BASE_REL" || exit 0
    _ensure_regular_file "$COVERED_REL" || exit 0
    _ensure_regular_file "$COVERED_REL.tmp" || exit 0
    _ml_seed_gitignore
    _drop_stale_ledger "$session"
    [ -f "$LEDGER_REL" ] || _ledger_stamp "$session" > "$LEDGER_BASE_REL" 2>/dev/null || true
    # 같은 스킬을 여러 번 호출해도 한 줄만 남긴다: 원장은 집합이지 호출 로그가 아니다.
    grep -qxF "$skill" "$LEDGER_REL" 2>/dev/null || printf '%s\n' "$skill" >> "$LEDGER_REL" 2>/dev/null || true
    # 이 스킬이 무엇을 봤는지 내용 주소로 붙잡는다. 원장(무엇을 돌렸나)만으로는
    # "리뷰 한 번 돌리고 그 뒤로 계속 쓰기" 를 구분할 수 없다.
    _snapshot_covered "$skill" "$(_json_str "$input" args)"
    exit 0
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
#   missing = 그 스킬이 이 세션에서 아예 안 돌았다
#   scope   = 돌긴 했는데 그 호출이 이 트리를 보지 않았다(원격 PR, 다른 worktree 등)
#   stale   = 보긴 했는데 그 뒤에 코드를 더 썼다 (가장 흔하다. 이걸 scope 와 섞으면
#             "커버리지 판정이 엄격한가"를 그 수치로 판단할 수 없다)
REVIEW_BLOCK_KIND=""
_analyze() {
    local ref="${1:-}" session="${2:-}" json tr s missing="" detail="" p
    local sig total paths=() key rj rt rreq cache_key="" cache_rt="" cache_rreq=""
    REVIEW_BLOCK_KIND=""
    _drop_stale_ledger "$session"

    if [ -z "$ref" ]; then ref="$(_push_range)"; fi
    [ -z "$ref" ] && return 1
    REVIEW_RANGE="$ref"

    # 트랙은 **범위 전체**로 정한다. 이 push 가 공유하는 작업 전체가 요구 수준을 정한다.
    json="$(bash "$IMPACT" score "$ref" 2>/dev/null)" || return 1
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
        elif grep -qxF "$s	_noscope	_noscope" "$COVERED_REL" 2>/dev/null; then
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
    echo "MangoLove review gate: 판정 범위를 정할 수 없어 통과시킵니다 (fail-open, 감사 대상)" >&2
    if [ -f "$rec" ]; then bash "$rec" record-skip review "fail-open" 2>/dev/null || true; fi
}

# 우회 처리. 통과시키면 0, 우회가 아니면 1. (pretooluse 와 prepush 가 공유한다.)
_bypassed() {
    local rec
    if [ "${MANGOLOVE_SKIP_REVIEW:-}" = "1" ]; then
        echo "MangoLove review gate: MANGOLOVE_SKIP_REVIEW=1 (게이트 우회, 감사 대상)" >&2
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
        rm -f "$SKIP_REL" 2>/dev/null || true
        echo "MangoLove review gate: .mangolove/.review-skip 으로 1회 우회 (감사 대상)" >&2
        # 우회는 차단이 아니다. block 으로 적으면 "리뷰 미실행 push 차단" 수치가 부풀어,
        # 그 수치로 게이트가 실제로 무엇을 막았는지 판단할 수 없게 된다.
        rec="$GATE_DIR/efficacy-recorder.sh"
        if [ -f "$rec" ]; then bash "$rec" record-skip review "bypassed" 2>/dev/null || true; fi
        return 0
    fi
    return 1
}

# 차단 사유를 stderr 로 낸다. 호출자가 종료코드를 정한다(훅 종류마다 다르다).
_emit_block() {
    {
        echo "--- MangoLove review gate: push 차단 ---"
        echo "이 변경의 트랙은 코드가 계산했습니다(모델 추정 아님): ${REVIEW_TRACK}"
        echo "  판정 범위 ${REVIEW_RANGE} (upstream 대비 이 브랜치의 순변경)"
        echo "  ${REVIEW_JSON}"
        echo ""
        echo "${REVIEW_TRACK} 트랙에 필요한 리뷰 중 아직 이 내용을 보지 않은 것:"
        printf '%s' "${REVIEW_DETAIL}"
        echo ""
        case "$REVIEW_BLOCK_KIND" in
            missing)
                echo "이 스킬들은 이 세션에서 아예 실행되지 않았습니다. 그냥 실행하세요."
                echo "사용자에게 묻지 마세요: 물어야 할 결정이 아니라 하면 되는 일입니다."
                ;;
            scope)
                echo "스킬은 돌았지만 그 호출이 이 트리를 보지 않았습니다"
                echo "  (원격 PR 번호, 다른 worktree, 이 트리에 없는 경로를 인자로 준 경우)."
                echo "강도만 주거나(/code-review high) 이 트리의 경로를 짚어 다시 돌리세요."
                ;;
            *)
                echo "스킬은 이 내용을 봤지만 그 뒤에 코드가 더 들어왔습니다."
                echo "델타가 사소하면 근거를 남기고 스스로 우회하세요. 이것도 묻지 마세요:"
                echo "  mangolove review skip \"<무엇을 리뷰했고 델타가 무엇인지>\""
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

# ── pretooluse: git push / gh pr create 경계에서만 게이트.
do_pretooluse() {
    local input cmd line
    # read -d '' 는 builtin 이라 cat 의 포크를 없앤다. NUL 이 없으면 1 을 반환하나
    # 그때도 읽은 내용은 input 에 담긴다.
    IFS= read -r -d '' input || true
    cmd="$(_unescape_cmd "$(_json_str "$input" command)")"

    # dry-run/삭제 세그먼트는 _gated_push_line 안에서 걸러진다.
    line="$(_gated_push_line "$cmd")"
    [ -n "$line" ] || exit 0

    _cd_to_hook_cwd "$input"
    git rev-parse --git-dir >/dev/null 2>&1 || exit 0
    _ml_init_state

    _bypassed && exit 0

    # 범위를 못 정하거나 impact 계산이 실패하면 fail-open: 게이트가 작업을 인질로 잡지 않는다.
    # 다만 조용히 넘기지 않는다(위 _record_fail_open 주석).
    _analyze "$(_push_range "$(_push_source_ref "$line")")" "$(_json_str "$input" session_id)" \
        || { _record_fail_open; exit 0; }

    if [ -z "$REVIEW_MISSING" ]; then
        # 통과. 원장은 여기서 지우지 않는다: push 가 실제로 성공했는지 알 수 없기 때문이다.
        if [ -n "$REVIEW_REQUIRED" ]; then
            echo "MangoLove review gate: ${REVIEW_TRACK} 필수 리뷰 충족 (${REVIEW_REQUIRED})" >&2
        fi
        exit 0
    fi

    _emit_block
    exit 2
}

# ── prepush: .githooks/pre-push 용. Claude Code 밖의 터미널 push 도 같은 규칙으로 막는다.
#    세션 인자가 없으므로 원장은 세션 기준으로 버리지 않는다(그 작업을 한 세션의 리뷰를 인정).
#
#    git 은 stdin 으로 "<local ref> <local sha> <remote ref> <remote sha>" 를 준다. 이것이
#    무엇을 push 하는지에 대한 **유일한 권위 있는 정보**다. 현재 브랜치를 가정하면
#    `git push origin other:main`, `--tags`, detached HEAD 에서 엉뚱한 범위를 본다.
#    git 이 부른 경우($# >= 2: 원격 이름 + URL)에는 stdin 만 믿는다. 올릴 것이 없으면
#    stdin 이 비고, 그때는 공유되는 내용도 없으므로 통과다.
do_prepush() {
    local from_git=0 lref lsha rref rsha base range blocked=0 saw=0
    [ "$#" -ge 2 ] && from_git=1
    git rev-parse --git-dir >/dev/null 2>&1 || exit 0
    _ml_init_state
    _bypassed && exit 0

    # lref/rref 는 git 이 주는 4개 필드 중 쓰지 않는 두 개다. 이름을 남겨 두어야
    # 필드 순서를 헷갈리지 않는다.
    # shellcheck disable=SC2034
    while read -r lref lsha rref rsha; do
        [ -n "${lsha:-}" ] || continue
        saw=1
        # local sha 가 전부 0 = 원격 ref 삭제. 내용을 공유하지 않는다.
        case "$lsha" in *[!0]*) ;; *) continue ;; esac
        case "${rsha:-}" in
            *[!0]*) base="$rsha" ;;               # 기존 원격 ref: 그 지점 이후가 새 것
            *)      base="$(_default_base)" ;;    # 새 ref: 기본 트렁크 기준
        esac
        [ -n "$base" ] || { _record_fail_open; continue; }
        range="${base}...${lsha}"
        _analyze "$range" "" || { _record_fail_open; continue; }
        [ -z "$REVIEW_MISSING" ] && continue
        _emit_block
        blocked=1
    done

    if [ "$blocked" -eq 1 ]; then exit 1; fi
    # git 이 부른 게 아니고(수동 진단) stdin 도 비었으면 현재 브랜치를 본다.
    if [ "$from_git" -eq 0 ] && [ "$saw" -eq 0 ]; then
        _analyze "" "" || { _record_fail_open; exit 0; }
        if [ -n "$REVIEW_MISSING" ]; then _emit_block; exit 1; fi
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
    [ -n "$reason" ] || { echo "usage: mangolove review skip \"<근거>\"" >&2; exit 2; }
    mkdir -p "$(dirname "$SKIP_REL")" 2>/dev/null || true
    _ml_seed_gitignore
    printf '%s\n' "$reason" > "$SKIP_REL" 2>/dev/null || { echo "review-gate: 마커를 쓸 수 없습니다" >&2; exit 1; }
    local rec="$GATE_DIR/efficacy-recorder.sh"
    if [ -f "$rec" ]; then bash "$rec" record-skip review "requested" 2>/dev/null || true; fi
    echo "MangoLove review gate: 다음 1회를 우회합니다 (감사 대상)" >&2
    echo "  근거: $reason" >&2
}

# ── status: 사람용 진단. 인자가 없으면 게이트가 실제로 볼 push 범위를 그대로 보여준다.
do_status() {
    local ref="${1:-}"
    _ml_init_state
    # _range_signature 는 A...B 만 이해한다. sha 나 --working 을 넘기면 서명이 비어
    # 모든 스킬이 충족으로 보이는 **거짓 PASS** 가 난다. 아예 받지 않는다.
    case "$ref" in
        ""|*...*) ;;
        *) echo "review-gate: status 는 범위(A...B)만 받습니다. 인자 없이 부르면 push 범위를 봅니다." >&2
           exit 2 ;;
    esac
    if ! _analyze "$ref"; then
        echo "review-gate: 판정 범위를 정할 수 없습니다 (원격 upstream 이나 origin/HEAD 확인)" >&2
        exit 1
    fi
    echo "Review gate: ${REVIEW_RANGE}  (upstream 대비 이 브랜치의 순변경)"
    echo "  계산된 트랙: ${REVIEW_TRACK}"
    echo "  필수 리뷰: ${REVIEW_REQUIRED:-(없음)}"
    if [ -f "$LEDGER_REL" ]; then
        echo "  이번 세션 실행 스킬: $(tr '\n' ' ' < "$LEDGER_REL")"
    else
        echo "  이번 세션 실행 스킬: (없음)"
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
