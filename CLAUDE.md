# MangoLove: 프로젝트 작업 규약

## 커밋 & 푸시 책임 (에이전트가 끝까지 수행)
- 이 저장소에서 에이전트는 **검증된 작업을 커밋하고 `main`까지 푸시하는 것을 스스로 책임진다.**
  매 단계 "커밋할까요?"라고 되묻지 않는다. 검증(빌드/린트/테스트) 통과 후 바로 커밋, 푸시한다.
- 커밋 메시지는 Conventional Commits + footer 에 `Change-Track:` 트레일러를 포함한다.
- **커밋 단위는 잘게, 자주.** 하나의 큰 커밋보다 논리적으로 분리된 여러 작은 커밋을 선호한다
  (사이클/파일/관심사 단위). 각 커밋은 그 시점에 빌드, 테스트가 통과하는 상태여야 한다.
  feature 브랜치는 `--ff-only` 머지로 `main` 에 올려 개별 커밋을 이력에 보존한다(squash 금지).
- 기능 작업은 feature 브랜치에서 진행하되, 완결, 검증된 단위는 `main`에 반영(머지 후 `git push origin main`)한다.
- 예외: 되돌리기 어려운 작업(force-push, 공유 이력 재작성 등)은 이 규약에 포함되지 않는다. 사전 확인.

## 검증 명령
- 테스트: `bats tests/`
- 린트: `shellcheck -x bin/mangolove lib/*.sh install.sh uninstall.sh`
- 플러그인: `claude plugin validate --strict cc-plugin`

## 문장부호 규약은 코드가 강제한다
- em dash 와 가운뎃점은 금지다. 이 규칙이 프롬프트에만 있었을 때 한 세션이 500줄 넘게
  다시 만들어 놓았다. 그래서 어조가 아니라 게이트로 옮겼다.
- 추적 파일: `tests/style.bats` 가 `git grep` 으로 전수 검사한다(CI 에서 자동).
  확장자 목록을 손으로 관리하지 않는다. 그 목록이 지난번 15건 누락의 원인이었다.
  예외는 UI 구분자 세 곳(statusline, 배너, README 의 상태줄 예시)뿐이고, 예외 목록이
  조용히 넓어지지 않도록 그 세 파일까지 테스트가 고정한다.
- 커밋 메시지: 파일이 아니라 테스트가 구조적으로 못 본다. `.githooks/commit-msg` 가 맡는다.
  레포당 1회 활성화: `git config core.hooksPath .githooks`
  (이 저장소는 활성화돼 있다. 우회는 `--no-verify`, 감사 대상.)
- 같은 `core.hooksPath` 로 `.githooks/pre-push` 도 걸린다. 리뷰 게이트를 터미널 직접 push
  에도 적용한다(판정은 `lib/review-gate.sh prepush` 에 위임, 로직 복제 없음).

## 메서드러지 전달 구조 (개선 #1 이후)
- 방법론 단일 출처: `methodology/strict.md`.
- `methodology/core.md` 와 `cc-plugin/skills/*` 는 **`lib/gen-methodology.sh` 로 strict.md 에서 생성**한다
  (손으로 편집 금지, 드리프트 방지 테스트가 재생성 일치를 강제한다).
- 전달: `MANGOLOVE_METHODOLOGY_MODE=split`(기본, core.md + `--plugin-dir cc-plugin`) | `monolith`(strict.md 통주입).
