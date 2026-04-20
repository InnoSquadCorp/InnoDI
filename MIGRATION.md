# Migration Notes

This file tracks release-to-release migration guidance when behavior, defaults, or artifact contracts change in a way that users must react to.

## Unreleased — `Lazy<T>` cycle escape hatch (Phase K)

### Who is affected

- Projects that define their own top-level type named `Lazy<T>` in a module
  that is imported alongside `InnoDI`.
- Projects that consume the CLI's `DependencyGraphEdge` payload programmatically.

### Required action

- If you already own a `Lazy<T>` type, prefer qualifying factory-parameter
  references with the module name (for example `MyModule.Lazy<T>`). The
  macro detects `Lazy<T>` heuristically by AST name match and treats the
  parameter as a soft edge; a conflicting user-defined type may be misread
  as InnoDI's `Lazy<T>` and silently excluded from cycle detection. A
  future release can lift this limitation once the macro has access to a
  real type checker.
- If you parse `DependencyGraphEdge` values programmatically, add the new
  `isSoft: Bool` field to your decoder or pattern match; it defaults to
  `false` so existing callers keep working unchanged.

### Notes

- The `container.dependency-cycle` message now ends with "To break this
  cycle without restructuring, wrap one factory parameter in `Lazy<T>`."
  Exact-match assertions against the old message string need an update;
  tests that assert against the `SwiftDiagnostics.MessageID`
  (`container.dependency-cycle`) are unaffected.
- Renderer output gains dashed edges (`-.->`, `style=dashed`, `- ->`) and
  an ASCII legend when soft edges are present. Existing graphs without
  soft edges stay byte-identical.

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
