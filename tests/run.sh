#!/usr/bin/env bash
# ─────────────────────────────────────────────
# MangoLove: 테스트 실행기 (파일 단위 병렬)
#
# bats tests/ 는 파일을 하나씩 돌려 5분쯤 걸린다. 테스트는 저마다 mktemp 폴더에서 돌아 서로
# 겹치지 않으므로 파일 여러 개를 동시에 돌린다.
#
# 파일 안의 테스트는 순서대로 돈다. 한 파일이 유난히 길면 그 파일이 전체 시간을 정한다
# (review-gate 테스트를 여러 파일로 나눈 이유). 파일별 소요 시간을 찍는 것은 그런 파일을 찾기
# 위해서다. 나눠서 줄일 수 있는 것은 마지막에 끝나는 파일과 그 앞 파일의 차이까지다. 전체는
# 직렬의 1/5~1/6 이 한계다: 프로세스 생성이 그 배수에서 포화한다(12코어 macOS 에서 측정).
#
# 사용: tests/run.sh [파일...]     인자가 없으면 이 폴더의 *.bats 전부
# 통과하지 못한 파일이 하나라도 있으면 그 파일의 출력을 그대로 보여주고 1 로 끝난다. 돌지 못한
# 파일, 테스트가 하나도 없는 파일, 적힌 테스트보다 적게 돈 파일도 통과로 치지 않는다.
# 동시 실행 수는 CPU 수다. MANGOLOVE_TEST_JOBS 로 바꾼다(다른 세션과 겹쳐 머신이 바쁠 때 낮추거나,
# 동시에 돌 때만 깨지는 테스트를 좁힐 때).
# ─────────────────────────────────────────────
set -uo pipefail

[ "$#" -gt 0 ] || set -- "$(dirname "$0")"/*.bats
# 빈 인자는 받지 않는다. macOS 의 xargs -0 은 빈 항목을 버려서 아래의 순번과 파일 짝이 밀린다.
for f in "$@"; do
    [ -n "$f" ] || { echo "run.sh: 빈 인자는 받을 수 없습니다" >&2; exit 2; }
done

jobs="${MANGOLOVE_TEST_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
logs="$(mktemp -d)" || exit 1
trap 'rm -rf "$logs"' EXIT

# 출력은 파일별 로그에 모은다: 동시에 찍히면 섞인다. 로그 이름은 인자의 순번이다. 경로에서
# 이름을 만들면 서로 다른 인자가 한 로그를 나눠 써서 실패가 통과 표시 뒤에 숨는다.
# 통과는 종료코드가 아니라 로그 옆의 .ok 표시로 남긴다. xargs 의 종료코드는 구현마다 다르고,
# 표시가 없는 파일은 아래에서 전부 실패로 센다.
# 돈 테스트 수는 파일에 적힌 @test 수와 맞아야 한다. bats 가 테스트를 조용히 빼먹고 0 으로
# 끝난 적이 있다(bash 3.2 에서 한국어 테스트명 69개가 빠졌다). 폴더 인자는 세지 않는다.
# 넘기는 순서는 받은 그대로다. 크기순은 이득이 없었다: 크기가 소요 시간을 따르지 않는다.
n=0
for f in "$@"; do
    n=$((n + 1))
    printf '%s\0%s\0' "$n" "$f"
done | xargs -0 -n 2 -P "$jobs" bash -c '
    log="$1/$2.log"
    bats "$3" > "$log" 2>&1; rc=$?
    ran="$(grep -c "^ok " "$log")"
    want="$ran"
    [ -d "$3" ] || want="$(grep -c "^@test " "$3" 2>/dev/null)"
    if [ "$rc" -eq 0 ] && [ "$ran" -gt 0 ] && [ "$ran" = "$want" ]; then
        : > "$log.ok"
        printf "ok    %3s개 %3ss  %s\n" "$ran" "$SECONDS" "$3"
    else
        [ "$rc" -ne 0 ] || echo "# run.sh: 적힌 테스트 ${want:-0}개 중 ${ran}개만 돌았습니다" >> "$log"
        printf "FAIL        %3ss  %s\n" "$SECONDS" "$3"
    fi
' _ "$logs"

passed=0 skipped=0 failed=0 n=0
for f in "$@"; do
    n=$((n + 1))
    log="$logs/$n.log"
    if [ -f "$log.ok" ]; then
        passed=$((passed + $(grep -c '^ok ' "$log")))
        skipped=$((skipped + $(grep -c '^ok .* # skip' "$log")))
        # 통과한 파일이 낸 경고(없는 명령을 run 으로 부른 경우 등)는 그대로 보여준다.
        # bats tests/ 는 이것을 끝에 찍어 줬다.
        if grep -qv -e '^ok ' -e '^1\.\.[0-9]' "$log"; then
            printf '\n── 경고 %s\n' "$f"
            grep -v -e '^ok ' -e '^1\.\.[0-9]' "$log"
        fi
    else
        failed=$((failed + 1))
        printf '\n── %s\n' "$f"
        cat "$log" 2>/dev/null || echo "(실행되지 않았습니다)"
    fi
done

if [ "$failed" -gt 0 ]; then
    printf '\n실패: 파일 %d개 (%d초)\n' "$failed" "$SECONDS"
else
    printf '통과: 테스트 %d개 (건너뜀 %d개), 파일 %d개, %d초 (동시 %s)\n' \
        "$passed" "$skipped" "$#" "$SECONDS" "$jobs"
fi
# 건너뛴 테스트는 이름까지 보여준다. 수만 찍으면 늘어나도 아무도 비교하지 않는다.
[ "$skipped" -eq 0 ] || grep -h '^ok .* # skip' "$logs"/*.log
[ "$failed" -eq 0 ]
