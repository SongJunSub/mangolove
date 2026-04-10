# MangoLove — Plan Mode

You are now in **Plan Mode**. Design the implementation strategy before writing any code.

## Planning Process

### 0. Brainstorm (Socratic)
구현 방법을 바로 정하지 않고, **최소 3가지 대안**을 먼저 도출한다.
- 각 대안에 대해: 접근 방식, 장점, 단점을 1-2줄로 정리
- 대안 간 비교: 복잡도, 성능, 유지보수성, 리스크를 테이블로 제시
- 추천안을 선택하고 **왜 이것이 최선인지** 근거 제시
- 사용자에게 대안 선택을 확인받은 후 다음 단계로 진행

### 1. Requirements Analysis
- Break down the request into discrete, measurable requirements
- Identify explicit vs implicit requirements
- Clarify ambiguities with reasonable assumptions (state them)

### 2. Architecture Design
- Identify affected components and their relationships
- Design data models and API contracts
- Consider scalability, performance, and maintainability
- Draw sequence diagrams for complex flows (using mermaid)

### 3. Implementation Plan
- Break work into ordered, committable steps
- Estimate complexity for each step (S/M/L)
- Identify risks and mitigation strategies
- Define acceptance criteria for each step
- **태스크 단위는 2-5분 내 완료 가능한 크기로 분할** (서브에이전트 드리프트 방지)

### 4. Impact Analysis
- List all files that will be modified
- Identify potential breaking changes
- Plan database migrations if needed
- Consider backward compatibility

### 5. Spec 문서 (필수)
모든 구현 작업에 반드시 Spec을 작성한다. TBD/미정/추후 결정 항목이 있으면 이 단계를 통과할 수 없다.

```
📝 Spec: [feature name]

## API Contract
- Endpoint: [METHOD /path]
- Request Body: [JSON schema or fields]
- Response Body: [JSON schema or fields]
- Error Responses: [status codes and messages]

## Data Model
- Entity/Table 변경 사항
- 새 필드, 타입, 제약조건, 인덱스

## 동작 명세
- 정상 흐름 (Happy Path)
- 엣지 케이스별 예상 동작
- 에러 시나리오별 처리 방식

## 수용 기준
- [ ] 기준 1 (자동화된 테스트로 검증 가능해야 함)
- [ ] 기준 2
```

### 6. Spec 리뷰 — 적대적 검증
Spec 작성 완료 후, **별도 서브에이전트**가 구현 맥락 없이 Spec만으로 다음을 검증한다:
- **완전성**: 모든 엣지케이스가 명세되었는가? 누락된 에러 시나리오는?
- **일관성**: API 계약과 동작 명세가 모순되지 않는가?
- **모호성**: 구현자가 다르게 해석할 수 있는 문장이 있는가?
- **TBD 탐지**: "추후", "나중에", "미정", "TBD" 등 미확정 표현이 있는가?
- **수용 기준 검증 가능성**: 각 수용 기준이 자동화된 테스트로 검증 가능한가?

이슈 발견 시 → Spec 수정 → 재리뷰 (통과할 때까지 반복)

### 7. 역할 기반 Plan 리뷰
Spec 리뷰 통과 후, **2개의 병렬 서브에이전트**가 서로 다른 관점에서 Plan을 리뷰한다.

#### Product 리뷰 (왜 만드는가?)
- 이 기능이 사용자 문제를 실제로 해결하는가?
- 스코프가 적절한가? (과도하거나 부족하지 않은가)
- 놓친 사용자 시나리오가 있는가?
- 에러 상황에서 사용자 경험이 고려되었는가?
- 기존 기능과의 일관성이 유지되는가?

#### Engineering 리뷰 (어떻게 만드는가?)
- 아키텍처가 기존 시스템과 일관되는가?
- 성능 병목이 예상되는 지점은?
- 보안 고려사항이 충분한가?
- 테스트 전략이 적절한가? (단위/통합/E2E)
- DB 마이그레이션이 무중단으로 가능한가?
- 롤백 시나리오가 고려되었는가?

리뷰 이슈가 있으면 Plan 수정 후 사용자에게 승인을 요청한다.

## Output Format

```
📋 Implementation Plan: [feature name]

## Requirements
- [ ] Requirement 1
- [ ] Requirement 2

## Architecture
[Component diagram or description]

## Spec
[Spec 문서 전문]

## Steps
1. **[S] Step name** — description
   - Files: file1.java, file2.java
   - Risk: Low

2. **[M] Step name** — description
   - Files: file3.java
   - Risk: Medium — [mitigation]

## Impact
- Modified files: N
- New files: N
- DB migrations: Yes/No
- Breaking changes: Yes/No

## Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2

## Review Results
- Spec 리뷰 (적대적): PASS — [요약]
- Product 리뷰: PASS — [요약]
- Engineering 리뷰: PASS — [요약]
```
