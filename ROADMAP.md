# InnoDI Roadmap

This document tracks the live roadmap after the 4.0.0 baseline and the
4.1.0 release-hardening pass.

## Shipped in 4.0.0

InnoDI 4.0.0 now treats the following capabilities as the stable baseline:

- Macro-generated DI containers with compile-time and build-time validation.
- Rooted graph rendering plus global DAG validation through `InnoDI-DependencyGraph`.
- `Overrides` scaffolding for every container unless a user-defined nested `Overrides` type suppresses generation.
- Deferred dependency wrappers:
  - `Lazy<T>` for soft-edge cycle escape hatches
  - `Provider<T>` for `.transient` re-entry
- Nested containers with `@SubContainer`, including ownership edges in graph output,
  explicit same-name wiring through exactly one of `with:` / `withNames:`,
  and child-to-parent label remapping through `bindings:`.
- Cross-module hierarchy support with `@DIComponent` and `@DIHierarchyRoot`.
- SwiftUI helpers through `InnoDISwiftUI`, including environment bridging and feature-root helpers.
- Validation artifacts, DocC generation, and a release workflow centered on `RELEASING.md`.

## Shipped in 4.1.0

InnoDI 4.1.0 hardens the 4.0.0 baseline without changing the public macro
surface:

- Validation coordinator locking now refuses unsafe filesystems by default
  (NFS mounts, SMB/CIFS, WebDAV, and FUSE-style filesystems) and documents the
  `INNODI_ALLOW_UNSAFE_LOCK=1` override plus `--scratch-path` recovery path.
- The coordinator lock now layers `open(O_CREAT | O_EXCL | O_RDWR)` with
  `flock(LOCK_EX | LOCK_NB)` on supported filesystems.
- Structured lock-timeout diagnostics, `--diagnose-lock`, and `--cache-stats`
  improve CI incident response.
- Malformed macro expansion paths no longer synthesize user-code
  `fatalError` accessors; terminal diagnostics plus empty expansion keep the
  failure at build time.
- PR and release gates both run the strict-concurrency suite and the
  macro-source `fatalError` allow-list guard.
- `@SubContainer(... withNames:)` now offers a `with:` Fix-it where Swift's
  peer-macro expansion rules allow the key-path form. RFC 0002 remains
  deferred for stacked peer-macro cases.

## Post-4.1.0 Priorities

1. Sub-container validation polish
   - `bindings:` now provides rename-safe child-to-parent label remapping.
     Future work should improve diagnostics for cross-module child input
     discovery, especially when build-support validation cannot see the child
     container.
   - Track the upstream Swift peer-macro limitation that keeps RFC 0002
     deferred for stacked `@SubContainer` + SwiftUI peer-macro sites.
2. Deferred and lifetime ergonomics
   - Evaluate whether `Lazy<T>` needs a lighter-weight surface such as a property-wrapper form, and whether the three built-in scopes need finer-grained lifetime variants for server-side or multi-window workloads.
3. CLI and validation polish
   - Add stronger `--help` coverage, more usage tests, and sharper diagnostics around graph collection, fix-its, and release artifacts.
4. Toolchain compatibility hardening
   - Keep SwiftSyntax, DocC, and build-plugin behavior stable across new Swift
     and Xcode toolchains without weakening the documented validation contract.
   - Continue narrowing the non-fatal Swift compiler-plugin JSON decode log
     tracked in `docs/internal/macro-plugin-json-investigation.md`.
5. Example and onboarding quality
   - Keep the SwiftUI examples, README set, and localized DocC aligned so new adopters can get to a working container and graph render quickly.
