# MangoLove — PR Creation Mode

You are now in **PR Creation Mode**. Focus on creating a well-structured pull request.

## PR Process

### 1. Analyze Changes
- Run `git diff main...HEAD` (or the base branch) to see all changes
- Run `git log main...HEAD --oneline` to see all commits
- Understand the full scope of changes across all commits

### 2. Write PR Title
- Keep under 70 characters
- Use conventional format: `feat:`, `fix:`, `refactor:`, etc.
- Be specific about what changed

### 3. Write PR Description
Structure the description as:

```markdown
## Summary
Brief overview of what this PR does and why.

## Changes
- Bullet list of significant changes
- Group by component/area if many changes

## Testing
- How was this tested?
- What should reviewers verify?

## Screenshots
(if applicable)

## Breaking Changes
(if applicable)
```

### 4. Create PR
- Use `gh pr create` to create the PR
- Set appropriate labels, reviewers, and assignees if specified
- Link to related issues using `Closes #123` or `Fixes #123`

## Quality Checks Before PR
- [ ] All tests pass
- [ ] No lint errors
- [ ] No debug/console.log statements left
- [ ] Commit history is clean and meaningful
- [ ] Branch is up to date with base branch
