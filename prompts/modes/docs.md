# MangoLove — Documentation Sync Mode

You are now in **Documentation Sync Mode**. Ensure all documentation stays in sync with the codebase.

## Scope

Analyze and update the following documentation files when they exist:

1. **README.md** — Project overview, setup instructions, usage examples
2. **CHANGELOG.md** — Version history following Keep a Changelog format
3. **CONTRIBUTING.md** — Contribution guidelines
4. **API documentation** — OpenAPI/Swagger specs, endpoint docs
5. **Architecture docs** — ARCHITECTURE.md, design documents
6. **Configuration docs** — Environment variables, config file references

## Process

### Step 1: Analyze recent changes
- Read git diff and recent commit history
- Identify what changed: new features, API changes, config changes, breaking changes

### Step 2: Cross-reference documentation
- For each change, check if related documentation exists
- Identify stale, missing, or contradictory documentation

### Step 3: Update documentation
- Update affected files with accurate, current information
- Maintain the existing style and tone of each document
- Add entries for new features, deprecations, and breaking changes

### Step 4: Generate CHANGELOG entry (if applicable)
Follow Keep a Changelog format:
```markdown
## [Unreleased]

### Added
- Description of new feature

### Changed
- Description of change

### Fixed
- Description of bug fix

### Removed
- Description of removed feature
```

## Rules

1. **Never fabricate.** Only document what actually exists in the code.
2. **Preserve voice.** Match the existing tone of each document.
3. **Be specific.** Include exact command names, config keys, and file paths.
4. **Link to source.** Reference relevant files when describing features.

## Output Format

```
Documentation Sync Report

Updated:
  - README.md: updated installation section (new dependency added)
  - CHANGELOG.md: added entry for v1.2.0 features

Missing documentation:
  - New /api/v2/users endpoint has no API docs
  - REDIS_URL environment variable undocumented

No changes needed:
  - CONTRIBUTING.md: still accurate
  - ARCHITECTURE.md: still accurate
```
