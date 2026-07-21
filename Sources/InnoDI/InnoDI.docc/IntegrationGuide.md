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
  generated prefixes: `_storage_`, `_override_`, `_innoDI`, and `_InnoDI`.

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

Attach `InnoDIDAGValidationPlugin` to each target that declares containers or a
standalone `@DIEnvironmentBridge`. This is required by the 5.0 correctness
contract because attached macros cannot inspect sibling extensions, every
enclosing declaration, or other source in the same target. The target-scoped
full-source pass rejects matching same-file and cross-file custom initializers,
generated-qualifier shadows in enclosing or other same-target declarations,
visible qualifier shadows with `public` or `package` access in imported
dependency targets, and direct-extension or standalone-local bridge targets
before Swift compilation.

Starting in 5.1, this package plugin also conforms to
`XcodeBuildToolPlugin`. Attach it directly to every container target in a
native Xcode project or a Tuist-generated project. For Tuist workspaces, it
discovers the workspace root and builds one production-source snapshot so
cross-project container references remain visible to source-level validation.

The Xcode plugin API does not expose Tuist's complete cross-project target
dependency topology. The Tuist fallback therefore validates the full source DAG
and declaration contracts, but module-edge hierarchy rules that depend on the
exact target graph still require a topology-aware SwiftPM or CI check. Xcode
commands declare no outputs because multi-destination variants can share one
plugin work directory, so Xcode may schedule the validation on every build.

For a class bridge, or a container/bridge nested in a class, the preflight also
follows the first inherited type as the potential superclass. Every traversed
class and typealias must be source-visible in the workspace snapshot. An
SDK-only, binary-only, unresolved, or ambiguous first inherited type is rejected
with `generated-qualifier.inheritance-unverifiable`; use a struct/enum or a
source-visible adapter when the external hierarchy cannot be indexed. The
syntax-only index conservatively rejects inherited `Swift` and `SwiftUI` type
members used by bridge generation, but accepts an inherited `InnoDISwiftUI`
member. Direct and enclosing `InnoDISwiftUI` declarations remain reserved.

The plugin now runs the DAG validator in-process through the build coordinator;
the standalone `InnoDI-DependencyGraph` executable remains available for local
inspection and CI artifacts.

Use a local SwiftPM scratch path when derived data lives on a network volume:
the scratch path must be writable and on a local disk. Replace `/tmp` with the
appropriate local temporary directory for your OS or CI environment when needed.

```sh
swift build --scratch-path /tmp/innodi-cache
```

See <doc:lock-safety> for filesystem classifications and lock recovery.
