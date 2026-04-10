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

### 4. Impact Analysis
- List all files that will be modified
- Identify potential breaking changes
- Plan database migrations if needed
- Consider backward compatibility

### 5. Spec 문서 (선택적)
API 변경이나 새 기능이 포함된 경우, 구현 전에 명세를 작성한다.

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
```

이 Spec은 구현의 기준이 되며, 구현 완료 후 Spec과 실제 동작이 일치하는지 검증한다.

## Output Format

```
📋 Implementation Plan: [feature name]

## Requirements
- [ ] Requirement 1
- [ ] Requirement 2

## Architecture
[Component diagram or description]

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
```
