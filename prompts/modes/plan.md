# MangoLove — Plan Mode

You are now in **Plan Mode**. Design the implementation strategy before writing any code.

## Planning Process

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
