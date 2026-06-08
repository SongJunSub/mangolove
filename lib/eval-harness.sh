#!/usr/bin/env bash
# ─────────────────────────────────────────────
# MangoLove — Deterministic Self-Eval Harness  [Phase 4 / v1]
#
# 방법론의 **결정적 부품**(impact-score 트랙 분류, 비가역 가드)이 "스펙대로 동작하는가"를
# 라벨된 픽스처에 대해 LLM 없이 측정한다. 결과는 재현 가능하고 CI 에 올릴 수 있다.
#
#   ① impact 트랙 보정도(calibration): 픽스처의 변경 → impact-score 의 track_floor 가
#      방법론 규칙이 지시하는 기대 트랙과 일치하는가 (스펙 적합 점수).
#   ② 가드 정밀도·재현율(precision/recall): "막아야 할/막지 말아야 할" 명령 라벨에 대해
#      irreversible-guard 가 정확히 차단/통과하는가.
#
# 정직성 원칙:
# - 점수를 부풀리지 않도록 **known-gap 픽스처**(커버 안 되는 스택 등 결정적 부품이 *원리상*
#   못 잡는 경우)를 함께 싣고, 별도로 표기한다(회귀 임계엔 미포함, 리포트엔 노출 — 침묵 캡 금지).
# - 이 하니스는 **결정적 계층만** 측정한다. "방법론이 모델 행동을 바꾸는가"의 end-to-end A/B 는
#   실세션이 필요하므로 v2 범위(여기서 측정하지 않음 — 과장 금지).
#
# 사용:
#   eval-harness.sh report   결정적 부품 전체 평가(사람용)
#   eval-harness.sh impact   impact 트랙 보정도만
#   eval-harness.sh guard    가드 정밀도·재현율만
# 종료코드: 회귀(비-known-gap 픽스처 실패)가 있으면 1, 전부 통과면 0.
# ─────────────────────────────────────────────
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMPACT="$SELF_DIR/impact-score.sh"
GUARD="$SELF_DIR/irreversible-guard.sh"

# ── impact 보정도 픽스처 ──
# 형식: "<expect_track>|<known_gap?0/1>|<relpath>|<file_content>"  (한 줄 = 픽스처 1개; 이 TSV 형식상 content 멀티라인 불가)
# 단일 파일 신호 중심(파일수 밴드는 impact-score.bats 가 커버). db+auth 결합은 승격 우선순위(auth>db)를 검증.
_impact_fixtures() {
    cat <<'EOF'
Trivial|0|README.md|# docs only, no code
Trivial|0|src/util.js|export const TIMEOUT = 5000
Medium|0|db/migration/V1__init.sql|CREATE TABLE users (id INT);
Medium|0|src/Client.kt|val c = WebClient.create("https://api.example.com")
Medium|0|src/client.py|r = requests.get("https://api.example.com/v1")
Medium|0|src/client.rs|let b = reqwest::get("https://api.example.com").await?;
Medium|0|src/Data/SchemaSetup.cs|migrationBuilder.CreateTable(name: "Users");
Large|0|src/security/SecurityConfig.kt|@PreAuthorize("hasRole(ADMIN)")
Large|0|src/security/RoleSetup.kt|CREATE TABLE roles (id INT); auth=@PreAuthorize
Large|0|src/Api/UserController.cs|[Authorize(Roles = "Admin")] public class C {}
Large|0|src/net/mw.rs|use tower_http::auth::RequireAuthorizationLayer;
Medium|0|db/migrate/001_users.rb|create_table :users
Large|1|src/handlers/access.rs|fn require_role(u: User) -> bool { u.is_admin() }
EOF
}

# ── 가드 정밀도·재현율 픽스처 ──
# 형식: "<block|pass>|<command>"
# 가드 커버 범위(정직): SQL 구문(DROP/TRUNCATE/WHERE 없는 DELETE)·Mongo 파괴 구문(dropDatabase/.drop()/
# 빈 필터 deleteMany)·리터럴+환경변수 위험 루트(/,~,$HOME,$PWD,${HOME},$(pwd)). 잔여 미커버(정직):
# 백틱 `pwd`(검사 전 제거됨)·base64/eval 난독화·새 CLI 도구 — 정규식 가드의 구조적 한계(잔여 위험).
_guard_fixtures() {
    cat <<'EOF'
block|git push --force origin main
block|git push -f origin main
block|git reset --hard HEAD~3
block|rm -rf /
block|rm -rf $HOME/data
block|rm -rf $PWD
block|rm -rf ${HOME}
block|rm -rf $(pwd)
block|psql mydb -c "DROP TABLE users"
block|mysql -e "TRUNCATE TABLE orders"
block|psql -c "DELETE FROM accounts"
block|cqlsh -e "DROP TABLE users"
block|psql -c "DELETE FROM accounts; -- WHERE id=1 was here"
block|psql -c "DELETE FROM accounts; DELETE FROM logs WHERE id=5"
block|mongosh --eval "db.users.deleteMany({})"
block|mongosh mydb --eval "db.dropDatabase()"
block|mongosh --eval "db.sessions.drop()"
block|kubectl delete deployment api
block|terraform destroy -auto-approve
pass|git push origin main
pass|git push --force-with-lease origin feature
pass|rm -rf ./build
pass|rm -rf node_modules
pass|rm -rf $TMPDIR/cache
pass|psql -c "SELECT * FROM users WHERE id = 1"
pass|psql -c "DELETE FROM accounts WHERE id = 5"
pass|mongosh --eval "db.users.deleteMany({status:'old'})"
pass|mongosh --eval "db.users.find({})"
pass|git commit -m "drop table reference in a comment"
pass|grep -rn "DROP TABLE" src/
EOF
}

# impact 트랙 보정도 평가 → 전역 IMP_MATCH/IMP_TOTAL/IMP_GAP_* 설정, 불일치 라인 출력(stdout)
eval_impact() {
    IMP_MATCH=0; IMP_TOTAL=0; IMP_GAP_MATCH=0; IMP_GAP_TOTAL=0
    IMP_MISS=""
    local expect gap rel content repo got
    while IFS='|' read -r expect gap rel content; do
        [ -z "$expect" ] && continue
        # 분모를 측정 전에 센다 — mktemp/측정 실패가 분모를 조용히 줄여 점수를 부풀리지 않도록(침묵 캡 금지)
        if [ "$gap" = "1" ]; then IMP_GAP_TOTAL=$((IMP_GAP_TOTAL + 1)); else IMP_TOTAL=$((IMP_TOTAL + 1)); fi
        got=""
        if repo="$(mktemp -d 2>/dev/null)"; then
            git -C "$repo" init -q 2>/dev/null
            mkdir -p "$repo/$(dirname "$rel")" 2>/dev/null
            printf '%s\n' "$content" > "$repo/$rel"
            git -C "$repo" add -A 2>/dev/null
            git -C "$repo" -c user.email=e@e -c user.name=n commit -qm fixture >/dev/null 2>&1
            got="$(cd "$repo" && bash "$IMPACT" score HEAD 2>/dev/null | sed -E 's/.*"track_floor":"([^"]+)".*/\1/')"
            rm -rf "$repo" 2>/dev/null
        fi
        # 유효 트랙이 아니면(mktemp 실패·impact 오류·추출 실패) MISS 가 아니라 '측정실패'로 — 점수를 부풀리지 않고 회귀로 드러낸다
        case "$got" in Trivial|Small|Medium|Large) ;; *) got="<측정실패>" ;; esac
        if [ "$gap" = "1" ]; then
            if [ "$got" = "$expect" ]; then IMP_GAP_MATCH=$((IMP_GAP_MATCH + 1))
            else IMP_MISS="$IMP_MISS\n    [known-gap] $rel: 기대 $expect, 실제 $got (커버 밖 스택)"; fi
        else
            if [ "$got" = "$expect" ]; then IMP_MATCH=$((IMP_MATCH + 1))
            else IMP_MISS="$IMP_MISS\n    [MISS] $rel: 기대 $expect, 실제 $got"; fi
        fi
    done <<EOF
$(_impact_fixtures)
EOF
}

# 가드 정밀도·재현율 평가 → 전역 G_TP/G_FP/G_FN/G_TN 설정, 오차 라인 출력
eval_guard() {
    G_TP=0; G_FP=0; G_FN=0; G_TN=0; G_ERR=""
    local label cmd esc rc
    while IFS='|' read -r label cmd; do
        [ -z "$label" ] && continue
        # 유효 JSON 으로 가드에 전달 — 역슬래시 먼저, 그다음 따옴표 이스케이프(순서 중요; 픽스처는 단일 라인이라 개행 없음)
        esc="${cmd//\\/\\\\}"; esc="${esc//\"/\\\"}"
        printf '{"tool_input":{"command":"%s"}}' "$esc" | bash "$GUARD" >/dev/null 2>&1
        rc=$?  # 2 = 차단, 0 = 통과
        if [ "$label" = "block" ]; then
            if [ "$rc" -eq 2 ]; then G_TP=$((G_TP + 1)); else G_FN=$((G_FN + 1)); G_ERR="$G_ERR\n    [FN 누락] 막아야 했는데 통과: $cmd"; fi
        else
            if [ "$rc" -eq 2 ]; then G_FP=$((G_FP + 1)); G_ERR="$G_ERR\n    [FP 오차단] 통과해야 했는데 막음: $cmd"; else G_TN=$((G_TN + 1)); fi
        fi
    done <<EOF
$(_guard_fixtures)
EOF
}

# 백분율 정수 (분모 0 → 0)
_pct() { if [ "${2:-0}" -gt 0 ]; then echo $(( $1 * 100 / $2 )); else echo 0; fi; }

report() {
    local regressions=0
    echo "MangoLove 자가평가 (결정적 부품 — LLM 없이 측정, 재현 가능)"
    echo ""

    eval_impact
    echo "① impact-score 트랙 보정도 (방법론 규칙 적합):"
    printf '  적합: %s/%s (%s%%)\n' "$IMP_MATCH" "$IMP_TOTAL" "$(_pct "$IMP_MATCH" "$IMP_TOTAL")"
    if [ "$IMP_GAP_TOTAL" -gt 0 ]; then
        printf '  known-gap(커버 밖, 회귀 임계 제외): %s건 — 결정적 부품이 원리상 못 잡는 한계\n' "$IMP_GAP_TOTAL"
    fi
    [ "$IMP_MATCH" -lt "$IMP_TOTAL" ] && regressions=$((regressions + 1))

    echo ""
    eval_guard
    local prec rec
    prec="$(_pct "$G_TP" $((G_TP + G_FP)))"
    rec="$(_pct "$G_TP" $((G_TP + G_FN)))"
    echo "② 비가역 가드 정밀도·재현율 (막아야 할 것만 정확히):"
    printf '  정밀도(precision): %s%% (오차단 FP %s건)\n' "$prec" "$G_FP"
    printf '  재현율(recall):    %s%% (누락 FN %s건)\n' "$rec" "$G_FN"
    printf '  분류: TP %s / TN %s / FP %s / FN %s\n' "$G_TP" "$G_TN" "$G_FP" "$G_FN"
    { [ "$G_FP" -gt 0 ] || [ "$G_FN" -gt 0 ]; } && regressions=$((regressions + 1))

    # 오차/불일치 상세 (있을 때만)
    if [ -n "${IMP_MISS}${G_ERR}" ]; then
        echo ""
        echo "상세:"
        [ -n "$IMP_MISS" ] && printf '%b\n' "$IMP_MISS"
        [ -n "$G_ERR" ] && printf '%b\n' "$G_ERR"
    fi

    echo ""
    if [ "$regressions" -eq 0 ]; then
        echo "결과: 회귀 없음 (결정적 부품이 스펙대로 동작). end-to-end 모델 A/B 는 v2 범위 — 여기서 측정 안 함."
        return 0
    else
        echo "결과: 회귀 감지 — 위 [MISS]/[FP]/[FN] 를 확인하세요."
        return 1
    fi
}

main() {
    case "${1:-report}" in
        report|"") report ;;
        impact)
            eval_impact
            printf 'impact 트랙 보정도: 적합 %s/%s, known-gap %s\n' "$IMP_MATCH" "$IMP_TOTAL" "$IMP_GAP_TOTAL"
            [ -n "$IMP_MISS" ] && printf '%b\n' "$IMP_MISS"
            [ "$IMP_MATCH" -lt "$IMP_TOTAL" ] && return 1 || return 0
            ;;
        guard)
            eval_guard
            printf '가드 정밀도/재현율: TP %s TN %s FP %s FN %s\n' "$G_TP" "$G_TN" "$G_FP" "$G_FN"
            [ -n "$G_ERR" ] && printf '%b\n' "$G_ERR"
            { [ "$G_FP" -gt 0 ] || [ "$G_FN" -gt 0 ]; } && return 1 || return 0
            ;;
        *) echo "usage: eval-harness.sh {report|impact|guard}" >&2; exit 2 ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
