# Releasing InnoDI

This document is the single release source of truth for InnoDI.

Latest stable public release: `4.3.0`

Current development train: `5.0.0` (unreleased)

`main` accumulates the 5.0 contract-hardening work as independently green
commits. Keep README installation snippets on 4.3.0 until the complete 5.0
release-candidate gate passes and an immutable 5.0.0 tag is created.

## Release Checklist

Before tagging a release:

1. Update the matching `## <tag>` section in this file. The release workflow publishes that section as the GitHub Release body.
2. Confirm the README installation snippet points at the same tag.
3. Run the main package test suite:
   - `swift test`
4. Run the strict-concurrency suite:
   - `swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors`
5. Run example builds and tests:
   - `(cd Examples/SwiftUIExample && swift build && swift test)`
   - `(cd Examples/PreviewInjectionExample && swift build && swift test)`
6. Run the global DAG check:
   - `swift run InnoDI-DependencyGraph --root . --validate-dag`
7. Verify the macro-source `fatalError` allow-list is intact:
   - `Tools/check-no-fatalerror-in-macros.sh`
8. Validate the Apple Privacy Manifests bundled with the embedded products:
   - `plutil -lint Sources/InnoDI/PrivacyInfo.xcprivacy`
   - `plutil -lint Sources/InnoDISwiftUI/PrivacyInfo.xcprivacy`
   - When the manifest is touched in this release, double-check that
     `NSPrivacyTracking`, `NSPrivacyTrackingDomains`,
     `NSPrivacyCollectedDataTypes`, and `NSPrivacyAccessedAPITypes` still
     match the actual SDK behavior — adding any Required Reason API to the
     runtime targets requires a corresponding manifest entry.
9. Generate DocC:
   - `Tools/generate-docc.sh`
10. Decide whether any artifact or schema contract changed and update the contract notes below.
11. Confirm the GitHub Actions `Release Gate` workflow is using the intended tag and toolchain.
12. If publishing the optional prebuilt validation plugin, prepare and verify
    the companion package artifact:
    - `(cd InnoDIValidationTools && Tools/prepare-release-artifact.sh --tag <tag> --source-path ../ --output-dir Artifacts)`
    - verify a synthetic consumer can build with `InnoDIPrebuiltDAGValidationPlugin`
    - publish `InnoDIValidationTools` with the same tag as this repository
13. For public-discovery releases, confirm Swift Package Index readiness:
    - repository is public
    - `Package.swift` is at the root
    - a semantic-version tag exists
    - `swift package dump-package` succeeds with the current Swift toolchain
    - package URL submitted to SPI includes `https://` and `.git`
    - after the package appears on SPI, use the maintainer badge markdown from
      the package page and add it to `README.md`
14. After tagging, evaluate external discovery PRs:
    - `matteocrippa/awesome-swift` for the compile-time DI category
    - the current leading SwiftUI awesome list only if the submitted entry
      focuses on `InnoDISwiftUI` helpers rather than core DI

## Release Notes Source

The tag-driven `Release Gate` workflow extracts the matching `## <tag>` section
from this file and uses it as the GitHub Release body.

Each version section should include:

- highlights
- breaking or behavior changes
- upgrade actions

## Artifact and Schema Contracts

These artifacts are treated as release-quality contracts:

- validation metrics JSON artifact
- validation summary Markdown artifact

Versioning rules:

- additive fields: minor schema increment or explicit release note
- changed semantics or removed fields: explicit schema bump plus upgrade note
- Markdown summaries do not carry a standalone numeric schema field; they follow the paired JSON artifact and the matching release section in this document

Current tracked versions:

- `ValidationMetricsArtifact.currentVersion`: see [ValidationMetrics.swift](Sources/InnoDIBuildSupport/ValidationMetrics.swift)
- `sharedRunCacheVersion`: see [ValidationCoordinator.swift](Sources/InnoDIBuildSupport/ValidationCoordinator.swift)

If artifact naming, schema shape, or coordinator cache salt changes, update
this document and the release-contract tests in the same change.

## Documentation Sync

Every release should leave these entrypoints consistent:

1. [README.md](README.md) and the localized README variants
2. [Overview.md](Sources/InnoDI/InnoDI.docc/Overview.md) and localized DocC source mirrors where present
3. [Validation.md](Sources/InnoDI/InnoDI.docc/Validation.md) and localized DocC source mirrors where present
4. [PolicyBoundaries.md](Sources/InnoDI/InnoDI.docc/PolicyBoundaries.md) and localized DocC source mirrors where present
5. [ModuleWideInitDetection.md](Sources/InnoDI/InnoDI.docc/ModuleWideInitDetection.md) and localized DocC source mirrors where present
6. [ROADMAP.md](ROADMAP.md)

If a release changes user-facing validation, graph semantics, hierarchy
behavior, or SwiftUI integration, update those docs in the same change.

The repository keeps localized DocC Markdown mirrors for review and GitHub
reading. The generated DocC archive currently builds from the English base
catalog.

## Automated Release Artifacts

The release workflow publishes these assets to the GitHub Release:

- packaged DocC archive

Validation metrics and Markdown summaries remain release-quality contracts, but
they are produced as build and validation outputs rather than uploaded as
standalone release assets.

## Unreleased

### Highlights

- Accepted [RFC 0005](docs/rfcs/0005-5.0-contract-hardening.md), making
  public-contract correctness and external consumer compilation the 5.0
  release blockers.
- Declared `main` as the 5.0 development line while keeping 4.3.0 as the
  latest stable installation version.
- Added reusable external SwiftPM compile-pass and compile-fail fixtures, and
  enabled the strict macro test workflow for pushes to `main`.
- Restored public `@DIComponent` expansion across Swift module boundaries by
  exporting its generated associated-type witnesses.

### Breaking or Behavior Changes

- `@DIContainer` and `@DIComponent` now accept only effectively non-generic
  `struct` declarations at file scope or inside non-generic nominal
  declarations. Direct non-struct or generic declarations, declarations in an
  enclosing generic nominal context, declarations nested inside extensions,
  declarations in executable scopes, and explicitly `private` containers are
  rejected by stable InnoDI macro diagnostics or the full-source build/CLI
  preflight. Use `fileprivate` for file-local mounting, or nest a default-access
  container inside a private namespace. Current Swift toolchains
  require the full-source layer for types inside computed-property bodies and
  can add compiler-owned or companion-macro diagnostics without that preflight
  when a local container is stacked with an attached-extension macro such as
  `@DIComponent`.
- The shared build-validation cache salt is now v5 so workspaces cannot reuse
  a green result produced before the declaration-matrix preflight rejected
  inaccessible private mount surfaces.
- Public `@Provide` now accepts only a direct, plain, stored instance `var` in
  the same supported `@DIContainer` struct. `let`, computed or observed
  properties, `lazy`, `weak`, `unowned`, `static`/`class`, standalone or
  indirectly nested declarations, property wrappers, conditional/unknown
  attributes, setter access controls, every source-written property-level
  global-actor attribute (including `@MainActor`), and manual attachment of the
  internal `_InnoDIProvideAccessor` macro are rejected. Request actor isolation
  with `@DIContainer(mainActor: true)`; isolation attributes InnoDI generates
  on provider declarations and accessors are internal compiler support. A
  complete provider member inside `#if` receives the dedicated
  `provide.conditional-declaration-unsupported` diagnostic.
- A property accepts exactly one `@Provide`; duplicate attributes are rejected
  with `provide.duplicate-attribute`. Opaque `some Protocol` provider types are
  rejected with `provide.opaque-type-unsupported` and must become
  `any Protocol`. Implicitly unwrapped `T!` provider types are rejected with
  `provide.iuo-type-unsupported` and must become explicit `T` or `T?`.
- `.shared` and `.transient` providers now require exactly one construction
  source from `factory:`, `asyncFactory:`, `Type.self`, or a property
  initializer. `.input` providers reject all four sources and `with:`.
- `.input` initializer parameters remain eager `T` values, preserving normal
  `try` / `await` argument evaluation. Direct non-optional function types are
  detected and emitted as escaping parameters automatically. A non-optional
  function type hidden behind a typealias uses the literal opt-in
  `@Provide(.input, escaping: true)`. Other scopes and obvious
  nonfunction/optional-function shapes receive stable diagnostics; Swift may
  diagnose a conservatively accepted alias that does not resolve to a
  non-optional function.
- Sibling DI edges now have a closed syntax: named parameters on the root
  `factory:`/`asyncFactory:` closure literal, or `Type.self` plus a literal
  `with:` array containing only canonical direct-member key paths spelled
  exactly `\Self.member`, such as `[\Self.config]`; `[]` is also valid. Named
  container, module-qualified, and typealias roots are rejected, as are nested
  components, optional chaining, subscripts, and computed elements. `with:` is
  valid only with `Type.self` and can target synchronous providers only.
  Non-closure factories and property initializers are opaque zero-edge sources
  and may not read sibling container members.
- Factory effects are explicit and checked on every explicit sibling edge.
  `validateDAG: false` does not suppress async/throwing compatibility errors.
- The deprecated `@DIFeatureRoot` compatibility macro is removed. Declare
  SwiftUI roots through `@SubContainer(featureRoot:)` or `featureRoots:`.
- Every `@DIContainer`, including a container with no managed members, now
  synthesizes the complete `Overrides` and trailing-override initializer ABI
  required for `@SubContainer` mounting. A user-declared nested `Overrides`
  type is now a terminal `container.overrides-name-conflict` error instead of
  suppressing only part of that ABI. Valid containers expose the reserved
  compiler-support alias `_InnoDIMountOverrides = Overrides`; generated parent
  mounting code uses it so an invalid child cannot bind to a user-collidable
  `Overrides` declaration. Consumers must not declare or reference the alias.
- Every stored instance member in a container must now be managed by
  `@Provide` or `@SubContainer`; computed and type properties remain supported.
  Unmanaged stored state receives `container.unmanaged-stored-property` before
  the generated initializer could remove or conflict with a memberwise init.
- With `validateDAG: false`, unresolved `Lazy<T>` and `Provider<T>` factory
  parameters now receive the same typed runtime-trap fallback as unresolved
  hard dependencies. This preserves the explicit opt-out without leaking an
  internal code-generation invariant or partial child storage.
- `mainActor: true` now covers the whole generated surface: dependency
  accessors, every generated initializer, `Overrides`, the `applyOverrides`
  function types used by convenience initializers, `withOverrides`, child
  overrides, and component mounting, all four `withOverrides` operation
  closures, and feature-root helpers generated by `@SubContainer`.
- For containers without `mainActor: true`, generated `async` and
  `async throws` `withOverrides` methods and their operation closure types are
  `nonisolated(nonsending)`. They retain the caller's actor executor, so
  arbitrary non-`Sendable` containers and closures do not cross isolation.
  Synchronous overloads are unchanged; main-actor overloads remain
  `@MainActor`.
- Main-actor components now conform to the dedicated
  `_InnoDIMainActorComponentMountable` protocol; ordinary components continue
  to use `_InnoDIComponentMountable`. This split preserves the actor type on
  generic mounting override closures.
- 5.0 release notes will keep contract-restoring behavior corrections separate
  from intentional breaking API changes.

### Upgrade Actions

- Before adopting 5.0, move unsupported containers and components to file scope
  or a non-generic nominal `struct`; inject runtime or type-specific state
  through `@Provide(.input)` or protocol dependencies. Replace an explicit
  `private` container with `fileprivate` for same-file mounting, or nest a
  default-access container inside a private namespace.
- Move each `@Provide` onto a direct, plain, stored instance `var` in its
  container. Remove accessor/observer blocks, unsupported storage modifiers,
  property wrappers, conditional/unknown attributes, setter access controls,
  and every source-written property-level actor attribute, including
  `@MainActor`. Request isolation with `@DIContainer(mainActor: true)` and never
  attach `_InnoDIProvideAccessor` directly. Isolation attributes InnoDI
  generates on provider declarations and accessors are internal compiler
  support. Move complete provider members out of `#if` and branch inside their
  factories or injected implementations.
- Keep exactly one `@Provide` per property. Replace `some Protocol` with
  `any Protocol`, and replace `T!` with explicit `T` or `T?`. Deliberately
  forging the compiler-support accessor together with another property wrapper
  can also produce Swift structural diagnostics alongside InnoDI's misuse
  diagnostic.
- Keep `.input` call sites eager. `try` and `await` remain ordinary initializer
  argument evaluation. Direct non-optional function types need no annotation;
  add literal `escaping: true` only when such a type is hidden behind a
  typealias. Remove the option from other scopes and optional/nonfunction
  shapes, and expect Swift to diagnose an alias that is not actually a
  non-optional function.
- Give every `.shared`/`.transient` provider exactly one construction source:
  `factory:`, `asyncFactory:`, `Type.self`, or a property initializer. Remove
  all four and `with:` from `.input` providers.
- Rewrite sibling-dependent non-closure factories and property initializers as
  root closure literals whose named parameters match the sibling members. Use
  `Type.self` with a literal canonical `with:` array such as `[\Self.config]`
  (or `[]`) for synchronous autowiring. Named container, module-qualified, and
  typealias roots, nested components, optional chaining, subscripts, and
  computed elements are invalid. Use a qualified global/static construction
  symbol when the source intentionally has no DI edge. Do not target an async
  provider from `with:`.
- Spell consumer effects explicitly with `asyncFactory:` and, when required,
  an `async throws` closure. Audit containers using `validateDAG: false` because
  effect validation still applies there.
- Replace every remaining `@DIFeatureRoot` with
  `@SubContainer(featureRoot:)` or `featureRoots:` before adopting 5.0.
- Move dependency conformers plus construction and use of non-`Sendable`
  generated values for `mainActor: true` components onto `@MainActor`. From an
  off-actor caller, construct and consume those values inside `MainActor.run`;
  use direct `await` only when the isolated operation returns a `Sendable`
  result.
- For a container without `mainActor: true`, keep asynchronous `withOverrides`
  work on the caller's isolation. Its generated async methods and operation
  closure types are `nonisolated(nonsending)`; do not add `Sendable` merely to
  move container or closure values across an actor boundary. Sync overloads
  remain unchanged.
- Update generic component-mounting helpers with a separate
  `@MainActor` `_InnoDIMainActorComponentMountable` overload whose override
  parameter is an `@MainActor` function type. Helpers constrained only to
  `_InnoDIComponentMountable` no longer accept main-actor components.
- Do not update package requirements to 5.0 before the release tag exists.

## 4.3.0

### Highlights

- **Feature-root helper generation is now integrated into `@SubContainer`.**
  New code should declare SwiftUI roots with `featureRoot:` for a single root
  or `featureRoots: [FeatureRoot(...)]` for multiple/default+aliased roots.
- `DIContainerMacro` now generates `<propertyName>RootView()` and
  `<alias>RootView()` helpers from sub-container metadata, avoiding stacked
  peer-macro expansion between `@SubContainer` and `@DIFeatureRoot`.
- `InnoDISwiftUI` no longer depends directly on `InnoDIMacros`; it continues
  to provide the SwiftUI facade API through its dependency on `InnoDI`.

### Breaking or Behavior Changes

- `@SubContainer` gained additive `featureRoot:` and `featureRoots:`
  parameters.
- `@DIFeatureRoot` remains available but is deprecated with the migration
  message: `Use @SubContainer(..., featureRoot:) or featureRoots: instead.`
- Feature-root alias, duplicate-default, and helper-name conflict diagnostics
  now also apply to the new `@SubContainer` feature-root metadata.

### Upgrade Actions

- Replace stacked feature-root declarations:
  `@SubContainer(...) @DIFeatureRoot(Root.self)` with
  `@SubContainer(..., featureRoot: Root.self)`.
- For multiple roots, replace repeated `@DIFeatureRoot` attributes with
  `featureRoots: [FeatureRoot(DefaultRoot.self), FeatureRoot(Shell.self, as: "shell")]`.
- Consumers that previously had duplicate `InnoDIMacros` copy phases through
  `InnoDI + InnoDISwiftUI` should update to `4.3.0` and depend on the
  `InnoDISwiftUI` product at SwiftUI root targets.

## 4.2.2

### Highlights

- **Tuist external-consumer compatibility for the package manifest.**
  The package no longer emits package-wide `SwiftSetting` entries from
  `Package.swift`. Current SwiftPM still accepts those settings, but Tuist's
  external package conversion can fail while decoding the Swift 6.3 manifest
  JSON when InnoDI is linked as an external dependency.
- `InnoDIBuildSupport` now declares its source path explicitly so Tuist does
  not mis-resolve the build-support target while constructing external package
  projects.
- Strict-concurrency validation remains enforced by the existing CI and release
  commands (`-strict-concurrency=complete -warnings-as-errors`) instead of
  being imposed through consumer-facing manifest settings.

### Breaking or Behavior Changes

- No runtime, macro, plugin, or public API behavior changes.

### Upgrade Actions

- Tuist-based consumers that could not generate projects with `4.2.1` should
  update to `4.2.2`.

## 4.2.1

### Highlights

- **swift-syntax pinned to `exact: "603.0.1"`.** The package dependency on
  `swiftlang/swift-syntax` is bumped from `from: "602.0.0"` (the prior
  next-major range) to `exact: "603.0.1"`. swift-syntax 603 tracks the
  Swift 6.3 toolchain that the project's CI matrix and macro-performance
  baseline already exercise; pinning explicitly removes the resolver
  ambiguity that surfaced during the 4.2.0 publish window when downstream
  consumers and the local resolver could land on different 602.x patch
  versions.
- **Maintainer-operations note for multi-account `gh auth`.** RELEASING.md
  now documents the `git` credential-helper / `gh auth switch` skew that
  surfaced during the 4.2.0 publish, so future releases of this package
  do not re-discover it.
- No user-facing API, runtime, or build-plugin behavior changes. The
  swift-syntax bump is a build-time dependency and does not alter the
  generated container surface.

### Breaking or Behavior Changes

- The package now pins swift-syntax exactly to `603.0.1`. Consumers whose
  own `Package.swift` declares an incompatible swift-syntax range (for
  example pinning to 602.x) will see an SPM resolver failure and must
  align their range with `603.x` or remove the constraint.

### Upgrade Actions

- If your `Package.swift` directly depends on `swiftlang/swift-syntax`
  with a 602.x constraint, update it to allow `603.x` (or remove the
  direct dependency if it was only there for InnoDI's transitive resolve).
- No source-code changes are required in your container or `@Provide`
  declarations.

### Internal Notes (Maintainer Operations)

- **Multi-account `gh` setups: `gh auth switch` does not, by itself, change
  which account `git push` uses.** When two GitHub accounts are configured
  (`gh auth status` shows both), the gh CLI's active account is independent
  from git's credential helper chain. On macOS, `osxkeychain` is consulted
  first and may return a token for the wrong account, producing a
  `403 Permission denied to <wrong-account>` even though `gh auth switch`
  reports the correct active account.
- **Permanent fix.** Run `gh auth setup-git` once on the maintainer's
  machine. That registers `!gh auth git-credential` as a credential helper
  alongside `osxkeychain`, so subsequent `gh auth switch -u <account>`
  calls deterministically change which account `git push` uses.
- **One-shot bypass without setup-git.** When pushing a single ref under a
  specific account without modifying the global helper chain, force the
  helper inline:
  ```sh
  git -c credential.helper='!gh auth git-credential' push origin <ref>
  ```
  This is the right escape hatch for shared release-runner machines where
  the global git config should not be mutated.
- **Symptom log from 4.2.0 publish.** A `git push origin main` succeeded,
  but the immediately following `git push origin 4.2.0` (the same shell,
  the same active gh account) returned 403 because keychain returned a
  different cached token for the second connection. After running
  `gh auth setup-git`, retrying with the inline `!gh auth git-credential`
  helper succeeded; subsequent operations followed `gh auth switch`
  deterministically.
- **Always restore the default account when done.** After publishing,
  switch the gh CLI back to the maintainer's primary account so unrelated
  shells do not push under the publishing identity.

## 4.2.0

### Highlights

- **`@SubContainer(withNames:)` removed.** Same-name child wiring now has a
  single supported explicit spelling: `with: [\.member]`. Use `bindings:` when
  child input labels differ from parent member names, and use `with: []` for an
  intentionally empty same-name subset.
- **Stacked peer-macro escape hatch removed from the API.** Sites that
  previously combined `@SubContainer(... withNames:)` with `@DIFeatureRoot` or
  another peer macro should split helper generation out into normal extension
  methods or another non-stacked helper surface.
- **DAG validation plugin state follows SwiftPM plugin work directories.** The
  build plugin no longer writes lock/cache state under
  `<package>/.build/innodi-dag-validation`; state is placed below
  `context.pluginWorkDirectoryURL`, so `swift build --scratch-path <local-dir>`
  moves validation state off unsafe package-root filesystems.
- **Documentation snippet compile gate.** `Tools/check-docs-code-blocks.sh`
  compiles Swift code fences marked with `<!-- innodi:compile -->`, and both PR
  and release gates run it.
- **Lazy eager-call validation.** Direct `Lazy<T>` invocation inside `.shared`
  factories now emits `provide.lazy-eager-call`, matching the Provider guard and
  preventing soft edges from silently becoming eager initialization traps.
- **CLI unknown options are hard errors.** `InnoDI-DependencyGraph` now fails
  unknown flags instead of warning and continuing, so typoed validation flags
  cannot silently skip release checks.
- **Optional prebuilt validation tools scaffold.** `InnoDIValidationTools`
  contains the companion prebuilt macOS validation plugin package and artifact
  preparation script. The source plugin remains the default compatibility path.
- **`@GenerateMock` consumer compile hardening.** The experimental mock macro
  now declares a deterministic `Mock` suffix, supports top-level protocols,
  qualifies helper names for overloaded methods, and handles generic method
  requirements through erased handler closures.
- **Korean adoption and DX docs.** The Korean README mirrors the English
  structure, migration guidance now includes internal v1-v3 adopter sequencing,
  and DocC includes anti-pattern guidance plus an interactive getting-started
  tutorial.
- **Apple Privacy Manifest bundled.** Both runtime products (`InnoDI` and
  `InnoDISwiftUI`) now ship a `PrivacyInfo.xcprivacy` resource declaring no
  user tracking, no tracking domains, no collected data types, and no Required
  Reason API usage. SwiftPM auto-bundles the manifest into apps that embed
  these libraries, so iOS / watchOS / tvOS / visionOS submissions surface the
  declaration in the aggregated privacy report. Build-time tools
  (`InnoDIBuildSupport`, dependency-graph CLI, macro plugin) are unaffected
  because they are not embedded in consumer apps.
- **Per-module test coverage on every PR.** The PR workflow now runs
  `swift test --enable-code-coverage` and `Tools/collect-coverage.sh` to
  produce a per-module rollup (lcov + JSON + Markdown). The Markdown table
  appears in the workflow's step summary; the four artifacts upload as
  `coverage`. Informational — merges are not gated on a coverage threshold.
- **Build-validation escape hatch report on every PR.**
  `Tools/report-validate-dag-escape-hatches.sh` lists every
  `@DIContainer(...validateDAG: false...)` site plus any active
  `INNODI_DISABLE_BUILD_VALIDATION=1` environment override in the workflow's
  step summary, separating production opt-outs from test/example fixtures.
  Set `INNODI_ESCAPE_HATCH_FAIL=1` in CI to escalate the report into a
  merge blocker.
- **Cross-file deferred-wrapper alias scanner.** New executable target
  `InnoDI-DeferredAliasScan` walks the workspace and lists every
  `typealias` that renames `Lazy<T>` or `Provider<T>`. The macro plugin
  only detects same-file aliases — cross-file ones silently behave as
  hard edges and disable cycle escape. The scanner closes that gap
  workspace-wide and is wired into the PR pipeline as a step-summary
  report plus `deferred-aliases-report` artifact. The `Lazy<T>` and
  `Provider<T>` docstrings now reference the scanner instead of the
  prior "planned workspace-analysis check" caveat.
- **Macro performance trend gate.** A new `perf-history` orphan branch
  records one macro-performance entry per push to `main` via the
  `Perf History` workflow + `Tools/append-performance-history.sh`. The
  PR workflow runs `Tools/check-performance-trend.sh`, which compares
  the current measurement against the rolling median of the last
  entries (default window 7, threshold 10%, same-toolchain filter on)
  and uploads `perf-trend-report.json` as an artifact. The pinned
  `Tools/macro-performance-baseline.json` gate stays in place; the
  trend gate runs alongside it to catch gradual creep under-threshold
  PRs accumulate. The `perf-history` branch bootstraps itself on the
  first `main` push after this release ships — no manual setup
  required.

### Breaking or Behavior Changes

- The public `@SubContainer` signature no longer accepts `withNames:`. Existing
  consumers must migrate to `with:` or `bindings:` before upgrading.
- Macro diagnostics and build-support diagnostics no longer include
  `sub.with-conflicts-with-with-names` or
  `hierarchy.with-conflicts-with-with-names`.
- `InnoDICore` no longer exposes `parseStrictStringArrayArgument`, and
  `SubContainerAttributeInfo` no longer carries `hasWithNamesDependencies`.
- `@GenerateMock` remains experimental. The attribute name is stable, but
  generated helper storage names are not release-frozen until the planned 5.0
  GA.

### Upgrade Actions

- Replace `@SubContainer(scope: .shared, withNames: ["config"])` with
  `@SubContainer(scope: .shared, with: [\.config])`.
- Replace `withNames: []` with `with: []`.
- For stacked peer-macro sites, keep `@SubContainer(scope:with:)` on the child
  container property and write the root/helper method manually.
- If CI diagnosed unsafe filesystem locks, move SwiftPM scratch/plugin work
  state with `swift build --scratch-path /tmp/innodi-cache`; `--diagnose-lock`
  can inspect the scratch or plugin state directory recursively.
- For teams adopting 4.x from early internal versions, migrate diagnostics and
  SubContainer wiring first, then enable the build plugin and repo documentation
  gates. See the migration guide and anti-patterns article before wrapping
  InnoDI in a runtime service locator.

## 4.1.0

### Highlights

- **No more macro-synthesized `fatalError` traps in user code.** The five
  `fatalErrorGetter` sites in `ProvideMacro` that previously produced
  runtime-trapping accessors for malformed `@Provide` inputs now emit a
  build-time diagnostic and an empty expansion. Invalid input fails at
  build time, never at run time. The `internal.codegen-invariant`
  diagnostic remains available as a defense-in-depth signal for InnoDI
  contributor bugs but no longer pairs with a runtime trap.
- **Validation coordinator refuses unsafe filesystems.** A new
  `FilesystemTypeDetector` runs `statfs(2)` against the lock directory
  before any `O_CREAT | O_EXCL` and classifies the filesystem. NFS mounts,
  SMB/CIFS, WebDAV, and FUSE-style filesystems are blocked unless the
  operator explicitly opts in via `INNODI_ALLOW_UNSAFE_LOCK=1`.
  Unrecognized filesystems emit a single-line stderr warning and
  proceed.
- **Structured lock-timeout diagnostic.** When the coordinator times
  out waiting for the lock it now prints a multi-line block with the
  holder PID, holder age, boot ID (when known), recovered-stale flag,
  and four numbered remediation actions. The new
  [`lock-safety.md`](Sources/InnoDI/InnoDI.docc/lock-safety.md) DocC
  article documents the supported and unsupported filesystems, the
  diagnostic's fields, and the recovery procedure.
- **`InnoDI-DependencyGraph --diagnose-lock`.** New CLI subcommand
  that prints the coordinator's view of a scratch directory:
  filesystem class, environment overrides, and any lock files it
  discovers (with metadata). Designed for incident response when a
  build is stuck on `lock-contention-timeout`.
- **`InnoDI-DependencyGraph --cache-stats`.** New CLI subcommand
  that aggregates `validation-metrics.json` artifacts under a state
  directory into a single hit/miss table plus per-reason-code
  counts and per-file scan totals. Useful for CI environments
  whose cache rules look right on paper but never reuse work.
- **flock(2) advisory layer on the validation lock.** The
  coordinator now acquires `O_CREAT | O_EXCL` *and*
  `flock(LOCK_EX | LOCK_NB)` on the lock descriptor. The advisory
  layer is redundant on local filesystems and acts as defense-in-depth on
  filesystems with advisory-lock support, but it does not make NFS or other
  unsafe filesystems supported by default.
- **New `MigrationGuide.md` DocC article.** Reorganizes the
  per-release upgrade notes from `RELEASING.md` into a "what
  changes a consumer must do" article, covering 1.x → 4.0,
  4.0 → 4.1, 4.1 → 4.2 (planned), and 4.x → 5.0 (planned).
- **Historical `@SubContainer` `withNames:` deferral.** 4.1.0 kept
  `withNames:` supported while the stacked peer-macro limitation was being
  evaluated. That deferral is superseded by the 4.2.0 wiring simplification
  above: current consumers should migrate to `with:` or `bindings:` only.

  **RFC 0002 status update**:
  [RFC 0002](docs/rfcs/0002-subcontainer-wiring-simplification.md)
  was `Deferred` in 4.1.0 while the stacked peer-macro escape hatch was still
  public. 4.2.0 applies the removal and documents the replacement path in
  the 4.2.0 upgrade actions; the RFC moves to `Implemented` in the index.

### Breaking or Behavior Changes

- Malformed `@Provide(.transient)` (no factory, no typeExpr, no
  inline initializer) now produces only the existing
  `provide.transient-factory-required` diagnostic, plus a Swift
  compiler "stored property has no initial value" error from the
  property whose accessor was dropped. No `fatalError` reaches user
  code. Source-incompatible only for callers who relied on the
  runtime trap for unreachable cases.
- `@Provide(.transient, factory: { (_: T) in ... })` (wildcard
  closure parameters) and `@Provide` with an unknown scope behave
  the same way: terminal diagnostic + no synthesized accessor.
- The validation coordinator emits `ValidationReasonCode.unsafeFilesystem`
  in its metrics artifact when fail-fast triggers. Downstream tooling
  that parses metrics should add the new case.
- The lock-timeout stderr block format has changed. CI scripts that
  grep the previous one-line format (`Timed out waiting for
  validation coordinator lock at '...'`) should switch to the
  structured fields: `path:`, `waited:`, `Suggested actions:`.

### Upgrade Actions

- `@SubContainer(... withNames: [...])` consumers on 4.1.0 had no
  release-blocking migration at that time. Consumers upgrading beyond this
  release should follow the 4.2.0 migration path and replace every
  `withNames:` site with `with:` or `bindings:`.
- CI runners that mount the SPM scratch directory on NFS or SMB —
  redirect with `swift build --scratch-path /tmp/innodi-cache`, or
  set `INNODI_ALLOW_UNSAFE_LOCK=1` (the coordinator still emits a
  warning so the bypass is auditable).
- If you previously parsed the validation coordinator's lock
  timeout stderr, update the parser to read the structured fields
  documented in `lock-safety.md`.
- Downstream metrics consumers — handle
  `ValidationReasonCode.unsafeFilesystem`.

### Internal Notes

- `Sources/InnoDIMacros/SyntaxBuilders.swift` no longer exports
  `fatalErrorStmt`; the helper had a single caller (the
  now-eliminated `.none` scope path) and was removed.
- A new CI step (`Tools/check-no-fatalerror-in-macros.sh`)
  enforces the macro-source `fatalError` allow-list. Any future
  attempt to add a runtime trap to a macro-synthesized accessor
  will fail the macro-tests workflow until either the trap is
  removed or `docs/internal/fatalerror-inventory.md` and the
  allow-list are explicitly extended.
- The PR macro-tests workflow now runs the same strict-concurrency
  command as the tag release gate, and the release gate also runs the
  macro-source `fatalError` guard.
- A non-fatal SwiftSyntax/compiler-plugin JSON decode message can still
  appear during `swift test` package test-bundle builds. It does not fail
  the suite and is tracked separately in
  `docs/internal/macro-plugin-json-investigation.md`.

## 4.0.0

### Highlights

- Consolidates InnoDI's current public contract around macro-generated containers, strict validation, graph rendering, hierarchy validation, and SwiftUI integration.
- Ships `Lazy<T>`, `Provider<T>`, `@SubContainer`, `@DIComponent`, `@DIHierarchyRoot`, rooted graph rendering, and validation artifacts as the stable 4.0.0 baseline.
- `@SubContainer` adds explicit name-based same-name wiring via the new `withNames:` argument, and the macro now diagnoses ambiguous, conflicting, or unparseable wiring (`with:` + `withNames:` conflict, same-name wiring + `bindings:` conflict, non-literal arrays, parent-name-collision when inferred wiring is ambiguous).
- Standardizes documentation around localized README and DocC entrypoints while treating this file as the single release and upgrade record.

### Breaking or Behavior Changes

- `@DIContainer(root:)` is a graph-rendering entry flag only. When at least one root exists, Mermaid, DOT, and ASCII output is pruned to the union of root-reachable nodes and edges.
- `validateDAG: false` skips global DAG validation plus the macro's local cycle and closure/`with:` graph-derived diagnostics, but raw-expression `factory:` and initializer references still diagnose at compile time and structural validation still runs.
- All containers synthesize `Overrides` scaffolding unless the user declares a nested `Overrides` type. Input-only containers therefore keep an empty builder and support no-op child override forwarding.
- `Lazy<T>` and `Provider<T>` are intentionally non-`Sendable` deferred handles and must stay on the container's original isolation domain.
- `Provider<T>` is limited to `.transient` targets.
- The previously public `_LazyCell<T>` runtime helper is removed. The macro now emits a local `_InnoDIDeferredCell<T>` inside synthesized initializers; downstream code should not depend on either symbol.
- `@SubContainer` implicit same-name wiring is only blessed when the parent has zero or one `@Provide` candidate. Larger parents must opt into `with:`, `withNames:`, or `bindings:`. `with: []` and `withNames: []` are explicit empty subsets that call `Child()`.
- `@SubContainer(with:)` / `withNames:` must be literal arrays the macro can read; runtime variables and computed elements are now rejected with `sub.invalid-same-name-wiring`.
- New diagnostics: `sub.with-conflicts-with-with-names`, `sub.bindings-conflicts-with-with`, `sub.invalid-same-name-wiring`, `container.reserved-name-prefix`. Build-support adds `hierarchy.unknown-child-input` for extras forwarded via `with:`/`withNames:`/`bindings:`.

### Upgrade Actions

- If you parse dependency graph payloads programmatically, support `isSoft`, `isProvider`, and `isOwnership`.
- If you relied on the old release-note flow, update internal tooling to read version sections from this file instead of legacy release-note files.
- If your tooling referenced older internal source paths, re-point it at the split macro and build-support file layout introduced before 4.0.0.
- If your module also defines `Lazy<T>` or `Provider<T>`, prefer spelling deferred wrapper parameters as `InnoDI.Lazy<T>` and `InnoDI.Provider<T>`.
- If you imported `_LazyCell` from InnoDI runtime, remove that import — the helper is now inlined per macro expansion and is no longer part of the public surface.
- If a container declares a member whose name starts with `_storage_`, `_override_sub_`, `_innoDISubBuild_`, `_innoDIUnresolvedDependency`, `_subBuildCell_`, `_lazyCell_`, or `_lazySelfForSub`, rename it. The macro now flags these reserved prefixes via `container.reserved-name-prefix`.
- New `InnoDICore` parsing helpers added to support strict literal-array validation: `parseStrictKeyPathArrayArgument`, `parseStrictStringArrayArgument`, `parseSubContainerBindingsArgument`, plus the supporting `SubContainerSameNameWiringLabel`, `SubContainerSameNameWiringParseState`, and `SubContainerBindingArgument` types and the new `hasWithDependencies` / `hasWithNamesDependencies` / `sameNameWiring` fields on `SubContainerAttributeInfo`. The non-strict `parseStringArrayArgument` was removed; migrate to the strict variant.

## 3.0.1

### Highlights

- Removed `swift-docc-plugin` from the main consumer package graph.

### Breaking or Behavior Changes

- No user-facing API migration was required.

### Upgrade Actions

- No code migration required.

## 3.0.0

### Highlights

- Promoted strict validation, semantic enforcement, build-stage validation, and release artifacts as the OSS baseline.
- Added repository governance and release automation documents.

### Breaking or Behavior Changes

- Established the documentation, validation, and release-contract model that later releases build on.

### Upgrade Actions

- Follow the README, Validation, and Policy Boundaries docs as the canonical integration path from 3.0.0 onward.
