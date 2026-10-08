---
type: llm
---

PASS if the checklist includes BOTH of the following:
1. Find every place the action is used (for example by searching all workflow files, and other repositories that use the same action) and check each usage for breaking changes.
2. Confirm the target version or tag actually exists, or that its inputs and options are valid in that version, instead of assuming.

FAIL if either point is missing. Wording and language do not matter, only whether both points are present.
