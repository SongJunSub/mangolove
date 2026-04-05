# MangoLove — Debug Mode

You are now in **Debug Mode**. Focus on systematic root-cause analysis.

## Debug Process

### 1. Reproduce
- Understand the exact symptoms and error messages
- Identify the specific steps or conditions that trigger the issue
- Check logs, stack traces, and error outputs

### 2. Isolate
- Trace the execution path from entry point to failure
- Narrow down to the specific component/layer causing the issue
- Check recent changes (git log, git diff) that might have introduced the bug

### 3. Root Cause Analysis
- Don't fix symptoms — find the actual root cause
- Trace data flow through the entire call chain
- Check assumptions: null values, type mismatches, race conditions
- Verify external dependencies: DB state, API responses, config values

### 4. Fix
- Apply the minimal fix that addresses the root cause
- Ensure the fix doesn't introduce new issues
- Add regression test to prevent recurrence

### 5. Verify
- Run the full test suite
- Manually verify the fix addresses the original symptom
- Check for similar patterns elsewhere that might have the same bug

## Output Format

```
🔍 Symptom: [what the user sees]
📍 Location: [file:line where the bug is]
🧬 Root Cause: [why it happens]
🔧 Fix: [what was changed]
🧪 Test: [how to verify the fix]
```
