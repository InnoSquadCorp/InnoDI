# InnoDI Roadmap

This document tracks the live roadmap after the 4.0.0 baseline.

## Shipped in 4.0.0

InnoDI 4.0.0 now treats the following capabilities as the stable baseline:

- Macro-generated DI containers with compile-time and build-time validation.
- Rooted graph rendering plus global DAG validation through `InnoDI-DependencyGraph`.
- `Overrides` scaffolding for every container unless a user-defined nested `Overrides` type suppresses generation.
- Deferred dependency wrappers:
  - `Lazy<T>` for soft-edge cycle escape hatches
  - `Provider<T>` for `.transient` re-entry
- Nested containers with `@SubContainer`, including ownership edges in graph output.
- Cross-module hierarchy support with `@DIComponent` and `@DIHierarchyRoot`.
- SwiftUI helpers through `InnoDISwiftUI`, including environment bridging and feature-root helpers.
- Validation artifacts, DocC generation, and a release workflow centered on `RELEASING.md`.

## Post-4.0.0 Priorities

1. Sub-container label remapping
   - When a child `.input` parameter label differs from the parent member name, the current macro still relies on Swift's compile error. A future iteration can make `with:` wiring more rename-safe.
2. Deferred and lifetime ergonomics
   - Evaluate whether `Lazy<T>` needs a lighter-weight surface such as a property-wrapper form, and whether the three built-in scopes need finer-grained lifetime variants for server-side or multi-window workloads.
3. CLI and validation polish
   - Add stronger `--help` coverage, more usage tests, and sharper diagnostics around graph collection, fix-its, and release artifacts.
4. Toolchain compatibility hardening
   - Keep SwiftSyntax, DocC, and build-plugin behavior stable across new Swift and Xcode toolchains without weakening the documented validation contract.
5. Example and onboarding quality
   - Keep the SwiftUI examples, README set, and localized DocC aligned so new adopters can get to a working container and graph render quickly.
