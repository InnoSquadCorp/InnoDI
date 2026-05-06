# RFC 0002 — SubContainer wiring simplification

- **Status**: Accepted and implemented
- **Authors**: InnoDI maintainers
- **Created**: 2026-04-26
- **Last updated**: 2026-05-05
- **Target release**: 4.2 hardening train
- **Supersedes**: public documentation that described a four-way
  `@SubContainer` wiring matrix

## Update — 2026-05-05

This RFC is no longer deferred. InnoDI removed the string-based
`withNames:` public argument directly and kept `with:` as the only
same-name explicit wiring form.

The previous deferral was driven by stacked peer-macro sites such as:

```swift
@SubContainer(scope: .shared, withNames: ["config"])
@DIFeatureRoot(FeatureRootView.self)
var feature: FeatureContainer
```

Those sites relied on string literals to avoid Swift's circular peer-macro
key-path expansion behavior. The implementation now resolves that by removing
the escape hatch from the API and moving helper construction out of the stacked
property. Consumers should keep `@SubContainer(scope:with:)` on the child
container member and write a small extension/helper method when a root view or
similar helper is needed.

## Summary

`@SubContainer` now has three supported wiring modes:

| Form | Example |
|---|---|
| Implicit | `@SubContainer(scope: .shared)` |
| Key-path subset (`with:`) | `@SubContainer(scope: .shared, with: [\.config])` |
| Remap (`bindings:`) | `@SubContainer(scope: .shared, bindings: [(child: \.config, parent: \.appConfig)])` |

The removed `withNames:` form duplicated `with:` semantics while losing
rename safety and forcing parallel parser, diagnostic, and build-support
branches.

## Motivation

Maintaining both `with:` and `withNames:` carried three costs:

1. **DX cost**: users had to learn a four-way matrix even though `withNames:`
   expressed no behavior that `with:` could not express.
2. **Maintenance cost**: every validation rule for `with:` needed a parallel
   string-literal branch in macro parsing and workspace hierarchy validation.
3. **Type-safety cost**: string literals are not rename-safe and fail later
   than key paths during refactors.

`bindings:` remains because it covers a different shape: child input labels
that intentionally differ from parent member names.

## Migration

Replace string same-name wiring with key paths:

```swift
// Before
@SubContainer(scope: .shared, withNames: ["config", "apiClient"])
var feature: FeatureContainer

// After
@SubContainer(scope: .shared, with: [\.config, \.apiClient])
var feature: FeatureContainer
```

Replace explicit empty string subsets the same way:

```swift
// Before
@SubContainer(scope: .shared, withNames: [])
var feature: EmptyFeatureContainer

// After
@SubContainer(scope: .shared, with: [])
var feature: EmptyFeatureContainer
```

For stacked peer-macro sites, split helper generation out:

```swift
@SubContainer(scope: .shared, with: [\AppContainer.config])
var feature: FeatureContainer

extension AppContainer {
    func featureRootView() -> FeatureRootView {
        FeatureRootView(container: feature)
    }
}
```

Use `bindings:` when the child input label differs from the parent member name.

## Implementation Notes

- `Sources/InnoDI/InnoDI.swift` no longer accepts `withNames:`.
- `Sources/InnoDICore/Parsing.swift` no longer parses strict string arrays for
  `@SubContainer`.
- `Sources/InnoDIMacros/Diagnostics.swift` removed
  `sub.with-conflicts-with-with-names` and the `withNames` invalid-wiring
  branch.
- `Sources/InnoDIBuildSupport` validates `with:` / `bindings:` only.
- Runtime tests, SwiftUI integration tests, and examples now use `with:` or
  manual helper methods.
- README and DocC describe `with:` / `bindings:` as the supported explicit
  forms.

## Acceptance Criteria

1. `rg 'withNames' Sources/ Examples/ Tests/` returns no supported API, test, or
   example usage.
2. `Sources/InnoDI/InnoDI.swift` no longer accepts a `withNames:` argument.
3. Macro diagnostics no longer expose `sub.with-conflicts-with-with-names`.
4. Workspace hierarchy validation no longer exposes
   `hierarchy.with-conflicts-with-with-names`.
5. README and DocC examples use `with:` or `bindings:`.
6. SwiftUI stacked helper examples compile through helper extraction rather
   than a string escape hatch.

## References

- `Sources/InnoDIMacros/DIContainerValidator.swift`
- `Sources/InnoDIMacros/DIContainerParser.swift`
- `Sources/InnoDIBuildSupport/WorkspaceHierarchyResolution.swift`
- `Sources/InnoDI/InnoDI.docc/MigrationGuide.md`
