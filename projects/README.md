# MangoLove Project Profiles

Each file in this directory represents a project profile.
MangoLove auto-detects the current project and loads the matching profile.

## File naming convention
- `{project-name}.md` — one file per project
- Profiles are auto-generated on first visit, or manually created

## Profile structure
```yaml
---
name: Project Name
path: /path/to/project
tech_stack: [Java, Spring Boot, MySQL, ...]
build_cmd: ./gradlew build
test_cmd: ./gradlew test
---
```
