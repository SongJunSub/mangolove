#!/usr/bin/env bash
# ─────────────────────────────────────────────
# MangoLove: Deterministic Self-Eval Harness  [Phase 4 / v1]
#
# 방법론의 **결정적 부품**(impact-score 트랙 분류)이 "스펙대로 동작하는가"를
# 라벨된 픽스처에 대해 LLM 없이 측정한다. 결과는 재현 가능하고 CI 에 올릴 수 있다.
#
#   impact 트랙 보정도(calibration): 픽스처의 변경 → impact-score의 track_floor가
#   방법론 규칙이 지시하는 기대 트랙과 일치하는가 (스펙 적합 점수).
#
# 정직성 원칙:
# - 점수를 부풀리지 않도록 **known-gap 픽스처**(커버 안 되는 스택 등 결정적 부품이 *원리상*
#   못 잡는 경우)를 함께 싣고, 별도로 표기한다(회귀 임계엔 미포함, 리포트엔 노출: 침묵 캡 금지).
# - 이 하네스는 **결정적 계층만** 측정한다. "방법론이 모델 행동을 바꾸는가"의 end-to-end A/B는
#   실세션이 필요하므로 v2 범위(여기서 측정하지 않음: 과장 금지).
#
# 사용:
#   eval-harness.sh report   결정적 부품 전체 평가(사람용)
#   eval-harness.sh impact   impact 트랙 보정도만
# 종료코드: 회귀(비-known-gap 픽스처 실패)가 있으면 1, 전부 통과면 0.
# ─────────────────────────────────────────────
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMPACT="$SELF_DIR/impact-score.sh"

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

# impact 트랙 보정도 평가 → 전역 IMP_MATCH/IMP_TOTAL/IMP_GAP_* 설정, 불일치 라인 출력(stdout)
eval_impact() {
    IMP_MATCH=0; IMP_TOTAL=0; IMP_GAP_MATCH=0; IMP_GAP_TOTAL=0
    IMP_MISS=""
    local expect gap rel content repo got
    while IFS='|' read -r expect gap rel content; do
        [ -z "$expect" ] && continue
        # 분모를 측정 전에 센다: mktemp/측정 실패가 분모를 조용히 줄여 점수를 부풀리지 않도록(침묵 캡 금지)
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
        # 유효 트랙이 아니면(mktemp 실패, impact 오류, 추출 실패) MISS 가 아니라 '측정실패'로: 점수를 부풀리지 않고 회귀로 드러낸다
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

# 회귀 판정은 여기 한 곳에서만 한다(report와 impact가 같은 기준을 쓴다).
# 측정한 픽스처가 없으면 통과가 아니다: 전부 known-gap이면 아무것도 재지 않은 것이다.
_impact_ok() { [ "$IMP_TOTAL" -gt 0 ] && [ "$IMP_MATCH" -eq "$IMP_TOTAL" ]; }

# 백분율 정수 (분모 0 → 0)
_pct() { if [ "${2:-0}" -gt 0 ]; then echo $(( $1 * 100 / $2 )); else echo 0; fi; }

report() {
    echo "MangoLove 자가평가 (결정적 부품, LLM 없이 측정, 재현 가능)"
    echo ""

    eval_impact
    echo "impact-score 트랙 보정도 (방법론 규칙 적합):"
    printf '  적합: %s/%s (%s%%)\n' "$IMP_MATCH" "$IMP_TOTAL" "$(_pct "$IMP_MATCH" "$IMP_TOTAL")"
    if [ "$IMP_GAP_TOTAL" -gt 0 ]; then
        printf '  known-gap(커버 밖, 회귀 임계 제외): %s건, 결정적 부품이 원리상 못 잡는 한계\n' "$IMP_GAP_TOTAL"
    fi

    # 불일치 상세 (있을 때만)
    if [ -n "$IMP_MISS" ]; then
        echo ""
        echo "상세:"
        printf '%b\n' "$IMP_MISS"
    fi

    echo ""
    if _impact_ok; then
        echo "결과: 회귀 없음 (결정적 부품이 스펙대로 동작). end-to-end 모델 A/B 는 v2 범위, 여기서 측정 안 함."
        return 0
    else
        echo "결과: 회귀 감지, 위 [MISS] 를 확인하세요."
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
            _impact_ok
            ;;
        *) echo "usage: eval-harness.sh {report|impact}" >&2; exit 2 ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
