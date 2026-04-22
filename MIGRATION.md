# Migration Notes

This file tracks release-to-release migration guidance when behavior, defaults, or artifact contracts change in a way that users must react to.

## Unreleased — Phase N hardening (file splits + new warnings)

### Who is affected

- Projects that reference internal macro-source paths (e.g. tool integrations
  that parse `Sources/InnoDIMacros/*.swift` for documentation extraction).
- Projects that ship a `typealias` for `Lazy<T>` / `Provider<T>` at
  closure-parameter sites — these now emit a warning, not an error.
- Projects that own a `@SubContainer` pointing at an input-only child in the
  same source file — these now emit a warning.

### Required action

- **File relocations (no public-API change).** Four large macro / build-support
  files were split into purpose-based modules. Public and `package` APIs are
  unchanged and the whole test suite stays green, but if you have tooling that
  depends on file paths inside `Sources/InnoDIMacros/` or
  `Sources/InnoDIBuildSupport/`, re-point it at the new layout:

  | Was | Now |
  |---|---|
  | `DIContainerCodeGenerator.swift` (1,259 lines) | entry file + `DIContainerOverridesGenerator.swift` + `DIContainerWithOverridesGenerator.swift` + `DIContainerSubContainerGenerator.swift` |
  | `DIContainerValidator.swift` (904 lines) | entry file + `DIProvideValidationDiagnostics.swift` + `DIContainerValidatorTypeChecks.swift` |
  | `ValidationCoordinator.swift` (744 lines) | entry file + `ValidationCoordinator+Caching.swift` + `ValidationCoordinator+Locking.swift` |
  | `SwiftUIMacros.swift` (722 lines) | entry file + `DIEnvironmentBridgeMacro.swift` + `DIFeatureRootMacro.swift` |

  Four original trunks expanded to four retained entry files plus nine new
  sibling files (9 new siblings, 13 destination files total).

- **New `provide.lazy-aliased` / `provide.provider-aliased` warnings.** When a
  factory parameter is spelled through a `typealias` that resolves to
  `Lazy<T>` / `Provider<T>`, the macro previously misclassified the edge as
  `.hard` silently. Now you'll see a warning pointing at the parameter token.
  Spell the wrapper directly (`Lazy<T>` / `InnoDI.Lazy<T>`) to keep the
  soft-edge / provider semantics, or accept the hard-edge classification and
  silence the warning with the appropriate compiler suppression.

### Notes

- `root: Bool` on `@DIContainer` now controls graph-render entry points. If at
  least one root exists, Mermaid/DOT/ASCII output is limited to the
  root-reachable subgraph. Toggling `root` still has no impact on DAG
  validation.
- `validateDAG: false` now opts a container out of the macro's graph-derived
  unresolved/declaration-order diagnostics in addition to global
  cycle / ambiguous / unknown-reference checks. Structural diagnostics remain
  enabled.

## Unreleased — Deferred wrapper sendability tightened

### Who is affected

- Projects that store `Lazy<T>` / `Provider<T>` inside `Sendable` types.
- Projects that pass `Lazy<T>` / `Provider<T>` across actor boundaries under
  `-strict-concurrency=complete`.

### Required action

- Stop treating `Lazy<T>` / `Provider<T>` as actor-boundary transport types.
  Keep them on the container's original isolation domain, or resolve the
  underlying dependency before crossing actors.
- If a `Sendable` holder currently stores either wrapper, replace the stored
  property with a concrete value, an actor-local closure, or an explicit
  message type that does not retain the container-backed deferred handle.

### Notes

- `Lazy<T>` / `Provider<T>` no longer expose `Sendable` conformance, even when
  `T: Sendable`.
- Shared/init-time late binding still uses `_LazyCell`; this change only
  removes the unsupported actor-boundary guarantee for accessor-based deferred
  handles.

## Unreleased — `@SubContainer` nested containers (Phase M)

### Who is affected

- Projects that already consume the CLI's `DependencyGraphEdge` payload
  programmatically — ownership now surfaces as a new `isOwnership` flag.
- Tests that match `Overrides` struct declarations by exact structure —
  a container that adopts `@SubContainer` gets two new Overrides slots
  per sub-container member (`<name>` and `<name>Overrides`).
- Projects that share identifier prefixes starting with
  `_storage_sub_`, `_override_sub_`, `_override_sub_apply_`, or
  `_innoDISubBuild_` inside a `@DIContainer` type.

### Required action

- If you parse `DependencyGraphEdge` values programmatically, add the
  new `isOwnership: Bool` field to your decoder or pattern match. It
  defaults to `false` so existing callers keep working unchanged.
- If your container body declares members starting with any of the
  reserved `_storage_sub_` / `_override_sub_` / `_override_sub_apply_`
  / `_innoDISubBuild_` prefixes, rename them — `@SubContainer`'s peer
  macro now owns those prefixes via `@attached(peer, names:
  prefixed(...))` and a collision will surface as a duplicate
  declaration error once you adopt `@SubContainer` on the same type.
- Macro expansion for a child container that carries `@SubContainer`
  on the parent must have at least one `.shared` / `.transient` /
  `@SubContainer` member on the child. The generated `Overrides`
  slot references `<ChildContainer>.Overrides`, and an input-only
  child does not produce that nested type. The Swift compiler reports
  the conflict as `type has no member 'Overrides'` at the parent's
  Overrides struct.

### Notes

- `@SubContainer` requires an explicit `scope:` argument; there is no
  default. Existing code does not break — the attribute is new — but
  authors should pick the lifetime intentionally. `.shared` caches
  the child per parent lifetime; `.transient` rebuilds on every
  accessor read.
- `.shared` sub-containers can only auto-wire through `.input` or
  `.shared` parent members. Referencing a `.transient` parent fails
  with the new `sub.shared-parent-must-not-be-transient` diagnostic —
  switch to `@SubContainer(scope: .transient)` if you need that
  dependency, or restructure the parent so the member is `.shared`.
- Ownership edges render in the dependency graph output (Mermaid
  `-->|owns: <member>|`, DOT `style=bold`, ASCII `#=>`). Existing
  graph output for containers that do not adopt `@SubContainer` stays
  byte-identical.
- Macro expansion emits `_innoDISubBuild_<name>` as `private var`
  with a `fatalError` default; Swift's definite-initialization rules
  require a mutable slot so the parent init's closure assignment can
  run after every other storage slot is filled. The closure captures
  a `let _lazySelfForSub = self` snapshot — value-type copies of
  `self` are cheap and reflect the parent's stable state.

## Unreleased — `Provider<T>` factory handle (Phase L)

### Who is affected

- Projects that define their own top-level type named `Provider<T>` in a
  module that is imported alongside `InnoDI`.
- Projects that consume the CLI's `DependencyGraphEdge` payload
  programmatically.

### Required action

- If you already own a `Provider<T>` type, spell factory-parameter references
  as `InnoDI.Provider<T>`. Detection is textual and mirrors the existing
  `Lazy<T>` heuristic: a bare `Provider<T>` whose symbol resolves to a
  user-defined type at call time may still be treated as InnoDI's wrapper
  during macro expansion. Generated wrappers preserve the written qualifier,
  so the collision-safe spelling is `InnoDI.Provider<T>`.
- If you parse `DependencyGraphEdge` values programmatically, add the new
  `isProvider: Bool` field to your decoder or pattern match. It defaults to
  `false` so existing callers keep working unchanged.

### Notes

- `Provider<T>` target scope is restricted: only `.transient` targets are
  allowed. `.shared` or `.input` targets fail with
  `provide.provider-non-transient-target`. If you want caching semantics,
  use `Lazy<T>` instead — Provider is specifically the "fresh instance each
  call" wrapper.
- Renderer output gains new glyphs for provider edges (Mermaid `==>`,
  DOT `style=dotted`, ASCII `~~>`) and the ASCII legend now lists them
  when present. Existing graphs with only hard/soft edges stay
  byte-identical.
- Under the hood, Provider reuses InnoDI's `_LazyCell` late-binding box, so
  macro output for `.shared` factories that consume a `Provider<T>`
  parameter references `_LazyCell` — a deliberate implementation sharing,
  not a new public runtime type.

## Unreleased — `Lazy<T>` cycle escape hatch (Phase K)

### Who is affected

- Projects that define their own top-level type named `Lazy<T>` in a module
  that is imported alongside `InnoDI`.
- Projects that consume the CLI's `DependencyGraphEdge` payload programmatically.

### Required action

- If you already own a `Lazy<T>` type, prefer qualifying factory-parameter
  references as `InnoDI.Lazy<T>`. The
  macro detects `Lazy<T>` heuristically by AST name match and treats the
  parameter as a soft edge; a conflicting user-defined bare `Lazy<T>` may
  still be misread as InnoDI's wrapper and silently excluded from cycle
  detection. Generated wrappers now preserve the written qualifier, so the
  supported collision-safe spelling is `InnoDI.Lazy<T>`. A future release
  can lift the heuristic limitation once the macro has access to a real
  type checker.
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
- `Lazy<T>` remains synchronous. A soft edge that targets an async shared
  provider now fails with `provide.lazy-unsupported-target` instead of
  reaching macro code generation.

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
- CI consumers reading validation artifacts.

### Required action

- Review containers that previously relied on permissive validation behavior.
- Existing code may now fail earlier when strict name-based resolution, declaration-order enforcement, or cross-file custom `init` validation detects invalid wiring.
- Replace any `@DIContainer(validate: ...)` uses with `@DIContainer(...)`. The `validate` parameter has been removed; `validateDAG: false` remains the supported DAG opt-out.
- If you parse validation JSON artifacts, verify the documented schema versions in `RELEASING.md`.

### Notes

- This major release formalizes OSS release documents and release-gate workflows.
- The version bump reflects stricter validation and semantic enforcement rather than a new public macro surface.

## When To Add An Entry

Add a migration section when a release changes:

- macro validation behavior that can break existing containers
- build-stage validation failure conditions
- validation artifact schema expectations used by CI or tooling

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
