---
type: llm
---

PASS if the response states BOTH of the following:
1. The subagent must work in an isolated git worktree (or equivalent isolation) so the main session's checked-out branch is not changed.
2. After the subagent finishes, the main session must itself re-verify the result before commit or push, including re-running build or lint itself instead of trusting the subagent's report.

FAIL if either point is missing. Wording and language do not matter, only whether both points are present.
