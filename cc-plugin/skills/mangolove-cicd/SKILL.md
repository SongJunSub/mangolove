---
name: mangolove-cicd
description: "MangoLove에서 CI/CD 워크플로우·GitHub Actions·빌드 설정을 변경할 때 사용한다. 외부 Action/CLI 실존 검증, 버전 업그레이드 시 사용처 전수 감사, 설정 대체 시 old/new diff 대조, CI/CD 최소권한·시크릿·보안 규칙을 제공한다."
---

# MangoLove — CI/CD 작업 규칙 (mangolove-cicd)

이 스킬은 strict 방법론의 **CI/CD 워크플로우 작업 규칙** 상세다. 트랙 판정·승인·안전 절차는 코어(core.md)가 단일 기준이다.

## CI/CD 워크플로우 작업 규칙

### 외부 도구/Action 사용 시 검증 필수
- GitHub Action 이름은 **추정으로 작성하지 말고** 실제 존재 여부를 확인한 뒤 사용
- CLI 도구의 플래그/옵션은 **대상 버전에서 유효한지** 확인 (deprecated/removed 여부)
- action이나 도구의 출력 형식이 후속 step의 입력과 호환되는지 확인

### 버전 업그레이드 시 사용처 전수 감사
- 바이너리/라이브러리/Action 버전 변경 시, 해당 도구를 사용하는 **모든 명령어를 grep**하여 호환성 확인
- 특히 CLI 플래그, 출력 형식, 설정 파일 스키마 등 breaking change 점검
- 멀티 레포 환경에서는 동일 도구를 사용하는 **다른 레포도 함께 감사**

### 텍스트/설정 대체 시 old/new diff 비교
- 기존 내용을 대체할 때, **삭제되는 항목을 먼저 식별**하고 보존 여부를 판단
- 특히 검증 기준, 리뷰 관점, 보안 규칙 등 목록형 항목은 1:1 대조

### CI/CD에도 코드와 동일한 품질 기준 적용
- **최소 권한 원칙**: permissions는 job 레벨에 선언, 필요한 권한만 부여
- **플랫폼 best practice**: `|| true` 대신 `continue-on-error: true`, workflow 레벨보다 job 레벨 설정 우선
- **멀티모듈 환경 고려**: 빌드 리포트, 캐시, 설정 파일 경로가 모듈별로 다를 수 있음
- **보안**: 외부 스크립트 파이프 실행 금지, 바이너리 버전 고정, secrets 하드코딩 금지

