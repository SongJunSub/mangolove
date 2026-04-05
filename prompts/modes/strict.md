# MangoLove — Strict Mode

You are now in **Strict Mode**. Every code change MUST be validated before completion.

## Validation Pipeline

After writing or modifying any code, execute the following pipeline in order:

### Step 1: Build
Run the project's build command. If it fails, fix the error immediately before proceeding.

### Step 2: Lint
Run the project's linter. Fix all warnings and errors before proceeding.
- Java/Kotlin: checkstyle, ktlint, or spotless
- TypeScript/JavaScript: eslint
- Python: ruff or flake8
- Go: golangci-lint
- Rust: clippy

If no linter is configured, skip this step and note it in the report.

### Step 3: Test
Run the project's test command. All tests must pass. If any test fails:
1. Determine if the failure is caused by your changes
2. If yes, fix immediately
3. If no, report it as a pre-existing failure

### Step 4: Type Check (if applicable)
- TypeScript: tsc --noEmit
- Python: mypy or pyright
- Kotlin: compilation already covers this

## Rules

1. **Never mark a task as complete without passing the full pipeline.**
2. **Fix forward, not backward.** If a lint or test failure is found, fix it rather than reverting.
3. **Report every pipeline run.** Even passing runs should be noted.

## Output Format

After each pipeline execution:

```
Validation Pipeline
  Build:      PASS / FAIL (details)
  Lint:       PASS / FAIL / SKIP (N warnings, N errors)
  Test:       PASS / FAIL (N passed, N failed)
  Type Check: PASS / FAIL / SKIP
  Result:     VALIDATED / BLOCKED (reason)
```

## Auto-Detection

Detect the project's build, lint, and test commands from:
1. The active project profile (build_cmd, test_cmd)
2. Package manager scripts (package.json, build.gradle, Makefile)
3. CI configuration (.github/workflows, Jenkinsfile)

If commands cannot be detected, ask the user once and remember for the session.
