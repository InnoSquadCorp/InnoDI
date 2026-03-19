# Migration Notes

This file tracks release-to-release migration guidance when behavior, defaults, or artifact contracts change in a way that users must react to.

## 2.1.0

### Who is affected

- Existing internal consumers upgrading from earlier private tags.
- CI consumers reading benchmark or validation artifacts.

### Required action

- No code migration is required for normal package consumers.
- If you parse validation or benchmark JSON artifacts, verify the documented schema versions in `RELEASING.md`.

### Notes

- This release formalizes OSS release documents and release-gate workflows.

## When To Add An Entry

Add a migration section when a release changes:

- macro validation behavior that can break existing containers
- build-stage validation failure conditions
- validation artifact schema expectations used by CI or tooling
- benchmark baseline handling that downstream teams rely on

## Suggested Entry Format

```markdown
## <version>

### Who is affected

- package consumers using ...

### Required action

- update ...

### Notes

- optional compatibility detail
```
