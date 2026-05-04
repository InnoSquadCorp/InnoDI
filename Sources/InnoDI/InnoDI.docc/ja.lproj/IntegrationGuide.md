# Integration Guide

Use InnoDI as generated Swift source plus build-time validation. Most tooling
works best when it treats macro output as compiler-generated implementation
detail and keeps user-authored container declarations as the review surface.

## Periphery

- Run Periphery against generated build settings, not hand-written source
  globs, so macro-expanded members are visible to the compiler.
- Keep `@DIContainer`, `@Provide`, `@SubContainer`, and generated override
  entry points reachable through tests, sample apps, or explicit retention
  rules when they are only invoked by reflection-free wiring.
- Prefer suppressing generated-member noise by retaining the container type or
  its public entry points rather than ignoring the whole module.

## SwiftLint

- Lint user-authored source normally.
- Do not lint macro-expanded output as if it were handwritten code.
- If your setup checks generated interface artifacts, exclude InnoDI's reserved
  generated prefixes: `_storage_`, `_override_`, `_lazyCell_`,
  `_subBuildCell_`, `_innoDISubBuild_`, and `_lazySelfForSub`.

## SwiftFormat

- Format the container declarations you write.
- Do not require a separate formatting pass over macro expansion snapshots in
  consumer projects.
- Keep attributes and factory closures readable at the declaration site; that
  is the source reviewers should inspect.

## Macro-Generated Members

InnoDI generates initializers, storage, overrides, and helper closures from
container declarations. Treat those generated members as part of the compiled
API surface, but keep manual dependencies explicit in the source container.

When a tool reports a generated symbol, map it back to the nearest
`@DIContainer`, `@Provide`, or `@SubContainer` declaration before deciding
whether the report is actionable.

## Build Plugin

Attach `InnoDIDAGValidationPlugin` to each target that declares containers.
The plugin now runs the DAG validator in-process through the build coordinator;
the standalone `InnoDI-DependencyGraph` executable remains available for local
inspection and CI artifacts.

Use a local SwiftPM scratch path when derived data lives on a network volume:

```sh
swift build --scratch-path /tmp/innodi-cache
```

See <doc:lock-safety> for filesystem classifications and lock recovery.
