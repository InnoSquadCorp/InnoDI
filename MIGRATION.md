# Migration Notes

This file tracks release-to-release migration guidance when behavior, defaults, or artifact contracts change in a way that users must react to.

## 3.0.1

### Who is affected

- SwiftPM consumers that inspect resolved dependencies for InnoDI.

### Required action

- No code migration is required.

### Notes

- This patch release removes `swift-docc-plugin` from the consumer dependency graph.
- DocC generation remains available for maintainers and CI through the docs-only generation flow.

## 3.0.0

### Who is affected

- Existing internal consumers upgrading from earlier private tags.
- CI consumers reading benchmark or validation artifacts.

### Required action

- Review containers that previously relied on permissive validation behavior.
- Existing code may now fail earlier when strict name-based resolution, declaration-order enforcement, or cross-file custom `init` validation detects invalid wiring.
- If you parse validation or benchmark JSON artifacts, verify the documented schema versions in `RELEASING.md`.

### Notes

- This major release formalizes OSS release documents and release-gate workflows.
- The version bump reflects stricter validation and semantic enforcement rather than a new public macro surface.

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
