# Changelog

Release notes and upgrade notes for every InnoDI version. Each `## <version>`
section becomes the body of that version's GitHub Release. The release
process, including how a development train becomes a stable version, lives in
[RELEASING.md](RELEASING.md).

Latest stable public release: `6.0.0`

Current development train: `7.0.0` (unreleased)

## Unreleased

7.0.0 supersedes 6.0.0. The 6.0.0 release stays published and immutable;
7.0.0 is the next major version and carries the breaking changes below.
`ContainerRole` stays a string-backed token in 7.0: returning it to an enum
needs a Swift 6.2 compiler canary result, which this train does not have, so
that change moves to 8.0.

### Highlights

- `DIContainerHost` passes one stable lifecycle handle to hosted content and
  the environment. `DIContainerHostHandle` is now `Equatable`: two handles are
  equal when they operate on the same host owner, so a host redraw no longer
  looks like an environment change to views that read
  `innoDIContainerHostHandle`.

- The eager `asyncFactory:` lifetime is documented and pinned by runtime
  tests. A `.shared` asynchronous provider starts its construction task in the
  container initializer, reader cancellation and container release do not
  cancel it, and each read of a `.transient` sub-container starts the child's
  eager asynchronous work again.

- `@Provide(.shared, initialization: .onDemand, asyncFactory:)` is supported.
  The provider constructs its value on the first read through an owned task,
  concurrent readers share that construction, and cancelling a reader cancels
  only its own wait. The accessor is `get async throws` because a read can
  observe cancellation or a closed provider. A container with at least one
  such provider gains `closeAsyncProviders()`, which cancels in-flight
  construction, releases the value, including an overridden one, and makes
  later reads throw `DIAsyncScopeError.closed`. A construction that has not
  begun never starts the factory, and a value a running factory returns
  after close is discarded. The
  `provide.ondemand-async-unsupported` diagnostic is removed, and
  `container.close-async-providers-name-conflict` reserves the generated
  method name. See
  [RFC 0008](docs/rfcs/0008-async-on-demand-providers.md).

- The README states that InnoDI supports Apple platforms only, and
  `SECURITY.md` names `6.x` as the supported line.

- The README installation is three steps: add the package, attach the
  validation plugin, and write a first container. Validator contract details,
  including the Xcode and Tuist limits, now live only in the Integration Guide.

- Only the English and Korean READMEs and DocC articles are maintained. The
  Japanese, Simplified Chinese, German, Spanish, and Russian translations
  are now notice pages that link their 6.0.0 versions.

- Every English DocC article, including the five tutorials, has a Korean
  mirror, and the localized documentation gate fails when an English article
  has none.

- New DocC guides, with Korean mirrors, map Factory and Swinject concepts to
  InnoDI and include compiled examples. `.spi.yml` points Swift Package Index
  at the hosted DocC documentation.

- CI step summaries list the slowest test suites for the fast PR lane and the
  coverage gate. An informational compiler canary reports whether each CI
  toolchain accepts enum-typed arguments on a multi-role attached macro, the
  shape that forced the string-backed `ContainerRole` token.

- The release candidate validator requires RFC 0008 and RFC 0009 to be
  recorded as exactly `Accepted`, in each RFC and in the RFC index, before a
  7.x release, as it requires RFC 0006 for a 6.x release.

- The fast PR lane skips the unique-binding fix-it consumer build, a
  clean-build contract that compiles SwiftSyntax from source; the exhaustive
  coverage gate still runs it, and CI Plan selects that gate for a pull
  request that changes the test. Main CI caches SwiftPM repository mirrors,
  downloaded prebuilts, and the external consumer scratch per toolchain and
  swift-syntax pin, while the Release Gate keeps cold consumer builds. Pull
  requests report the macro performance gate and trend instead of failing on
  hosted-runner variance; pushes to `main`, merge queue runs, manual dispatch,
  and the Release Gate still enforce them.

- The exhaustive CI lane runs the external consumer and strict-concurrency
  build contracts in their own job beside the coverage gate instead of inside
  it, and the Release Gate adds Xcode 26.6 to the compatibility matrix that
  runs them. CI Plan also selects that job for a pull request that changes a
  consumer fixture or contract. On `main` they took about 1,415 of the
  coverage pass's 1,460 test seconds while building fixture packages in
  separate processes. Every module stays above its coverage floor without
  them; in a local comparison the only lines they alone covered were two
  timing-dependent lock-contention branches in `InnoDIBuildSupport`.

- The public API gate folds symbol-graph extension blocks into the type they
  extend, so one baseline holds on every CI toolchain. With SwiftUI no longer
  re-exported, SwiftPM on Swift 6.4 emits blocks for `InnoDISwiftUI`'s
  extensions of `EnvironmentValues` and `View` even when asked to omit them,
  while Swift 6.3 attaches the members to the extended type. Baseline schema
  10 records the members and their `memberOf` relationships only.

- SwiftSyntax moves to exact `604.0.0`, and Xcode 27 (Swift 6.4) becomes the
  primary consumer toolchain. SwiftSyntax 604.0.0 has a matching prebuilt on
  Swift 6.4 and none on Swift 6.3.
  `Tools/cold-build-benchmark.sh --target consumer --keep-user-cache` with 100
  bindings reported `prebuilt` on Xcode 27.0 (36.3 s on a local Apple silicon
  Mac) and `source` on Xcode 26.6 (302.3 s on the hosted `macos-26` runner).
  The exact-SHA remote consumer, the representative SampleApp example, and the
  cold benchmark's primary scenario run on Xcode 27. The in-package test,
  coverage, performance, sanitizer, platform, and documentation lanes stay on
  Xcode 26.6, where the root package builds SwiftSyntax from source as before.

### Breaking or Behavior Changes

- The macOS floor is 14. `DIContainerHostOwner` is an `@Observable` class
  instead of an `ObservableObject`, so its `objectWillChange` and `$phase`
  publishers are gone, and `DIContainerHost` keeps it in `@State`. Other
  platform floors are unchanged. See
  [RFC 0009](docs/rfcs/0009-7.0-source-breaks.md).

- `InnoDISwiftUI` no longer re-exports SwiftUI. It still re-exports InnoDI.
  A file that uses SwiftUI names, including through generated
  `@SubContainer(featureRoot:)` helpers or `@DIEnvironmentBridge`, must
  import SwiftUI. `InnoDI-Migrate` adds the import. See
  [RFC 0009](docs/rfcs/0009-7.0-source-breaks.md).

- InnoDI requires SwiftSyntax exactly `604.0.0`; 6.x required `603.0.2`. Every
  package in a consumer graph must agree on that version, so a graph that also
  requires SwiftSyntax 603 no longer resolves. Xcode 27 (Swift 6.4) builds
  InnoDI's macros with the matching SwiftSyntax prebuilt; Xcode 26.x
  (Swift 6.3) and Swift 6.2 compile SwiftSyntax from source.

- Parent key paths in `@SubContainer(with:)` and on the `parent:` side of
  `@SubContainer(bindings:)` and `@SubContainerFactory(bindings:)` must be
  spelled `\Self.member`. A named root such as `\AppContainer.config` is
  rejected with `sub.noncanonical-parent-key-path` and a fix-it; InnoDI only
  ever read the member name, so the root was never checked. The rest of the
  container is still validated in the same pass. A nested component such as
  `\Self.config.baseURL`, which used to wire only its last component, is
  rejected as `sub.invalid-same-name-wiring` or `sub.invalid-bindings`. Build
  validation resolves named roots so the compiler fix-it is reported first,
  and rejects nested components. Its `bindings:` remediation examples spell
  the parent side as `\Self.member`.

- `InnoDI-Migrate --trust-module <name>` treats an imported module as
  declaring no InnoDI-named attribute or macro, and `InnoDI-Doctor` accepts
  the same option for its migration check. The
  `migrate.unqualified-ownership-ambiguous` message names the imports that
  caused it. On the InnoSample pilot, this unblocked 9 of 11 container files,
  each of which imported the application's own modules.

- `InnoDI-Migrate` reports which rule changed each file. Each report change
  gains an additive `rules` array, such as `migrate.parent-key-path` and
  `migrate.swiftui-import`, and `MIGRATE` and `MIGRATED` lines append the
  same codes. The report schema version stays 1, and reports without
  `rules` still decode.

- `InnoDI-Migrate` no longer blocks on a comment above or after
  `@Provide(.input)`, a legacy `@DIContainer(root:mainActor:)`, or a
  `@SubContainer` that receives `@DIFeatureRoot`. Those rewrites keep the
  attribute's surrounding comments. Comments inside the attribute, or on a
  `@DIComponent`, `@DIHierarchyRoot`, or `@DIFeatureRoot` attribute that the
  rewrite removes, still block with `migrate.input-argument-unsupported`,
  `migrate.container-option-comment`, or `migrate.feature-root-ambiguous`.

- `InnoDI-Migrate` no longer blocks a whole run when a current 6.0
  `@DIContainer` without legacy options carries a documentation or nearby
  comment. It previously reported `migrate.container-option-comment` for such
  files.

- `InnoDI-Migrate` rewrites a legacy `@DIContainer(mainActor: true)` that has
  no `@DIComponent` or `@DIHierarchyRoot` to
  `@DIContainerRole(role: ContainerRole.local, mainActor: true)`. 6.0 wrote
  `@DIContainerRole(mainActor: true)`, which does not compile because the
  role macro requires `role:`; the InnoSample pilot hit this in three feature
  containers. A legacy container left with only default options, such as
  `@DIContainer(root: false)`, stays `@DIContainer`. A `@DIComponent` that
  also sets `root: true` now blocks with `migrate.container-role-conflict`
  instead of losing `root: true`, because a 6.0 container has one role.

- `InnoDI-Migrate` blocks instead of reporting a file clean or writing code
  that no longer compiles when a legacy spelling sits where no rewrite
  reaches it, such as an attribute-list `#if` clause or a macro argument
  (`migrate.legacy-form-unsupported`), or when the scanned sources declare a
  name a rewrite would produce, such as `Input` or `ContainerRole`
  (`migrate.rewrite-target-ambiguous`). A nested parent key path in a file
  whose imports make `@SubContainer` ambiguous now reports
  `migrate.unqualified-ownership-ambiguous`, as a named root already did, and
  removing a marker from the end of a line leaves no trailing space.

- `InnoDI-Migrate` parses every migrated file again before writing and
  blocks the run with `migrate.output-parse-error` if a rewrite produced
  invalid Swift, instead of writing it.

- `InnoDI-Migrate` gives a legacy `@DIContainer` without arguments its
  argument list when a `@DIComponent` or `@DIHierarchyRoot` marker moves into
  it. 6.0 wrote `@DIContainerRolerole: ContainerRole.component`, which does
  not compile. A trailing comment on the container stays after the new
  argument list.

- `InnoDI-Migrate` keeps the blank line above a removed `@DIComponent`,
  `@DIHierarchyRoot`, or `@DIFeatureRoot` attribute that came first on its
  declaration. 6.0 dropped it, so the migrated declaration directly followed
  the previous import or member, as in three InnoSample pilot files. A
  rewritten `@DIContainer`, `@Provide(.input)`, or `@SubContainer` attribute
  written one argument per line keeps that layout. 6.0 joined the container
  arguments and left `)` alone on the last line, pulled the `)` of `@Input`
  onto the argument line, and appended `featureRoot:` to the line of the last
  `@SubContainer` argument.

- Generated support: an `.onDemand` `asyncFactory:` provider stores its value
  in the new public `_InnoDIAsyncSharedCell`, and `DITraceContext.disabled`
  is now a computed property built in the caller. The cell exists only for
  generated code; do not declare or reference it directly.

- The `deferred-alias.workspace-finding` warning no longer suggests moving a
  `Lazy` or `Provider` alias into the file that consumes it. InnoDI does not
  resolve such aliases in any file, and in a real build the macro-level alias
  warning never sees a file-scope alias. Spell the wrapper directly at the
  factory parameter.

- A module that calls a generated container initializer or `withOverrides`
  from another module no longer has to link InnoDI. Swift evaluates the
  trailing `_innoDITrace: .disabled` default argument in the caller, and in
  6.0 that read a stored property of InnoDI, so an Xcode test bundle that
  linked a framework containing containers, but not InnoDI, failed with an
  undefined `DITraceContext.disabled` symbol. `DITraceContext.disabled` is
  now built in the caller. The InnoSample pilot hit this in its `Layers`
  test bundle.

- A `@SubContainer` child input wired to an asynchronous parent member is
  rejected with `sub.async-parent-member`. In 6.0 the generated child
  construction failed to compile with an unrelated missing-member error, so
  no compiling source changes meaning. `@SubContainerFactory(bindings:)`
  reports the same code instead of
  `provide.with-dependency-requires-synchronous-provider`, whose remediation
  suggested an `asyncFactory:` rewrite that a factory member cannot use. A
  `with:`, `bindings:`, or `@Multibinding` key path that names an
  asynchronous member reports only InnoDI's diagnostic. 6.0 also reported
  `cannot form key path to property with 'throws' or 'async'` at that key
  path.

- A value named `InnoDI`, such as an enclosing type's `static let InnoDI`,
  that is visible from a container with a `.shared`
  `initialization: .onDemand` provider is rejected with
  `container.reserved-module-name` by build validation. The generated
  initializer constructs on-demand storage through `InnoDI.` in expression
  position, so in 6.0 such a value made generated code fail to compile. A
  type named `InnoDI` was already rejected for every container.

- Build validation no longer rejects an unqualified `Lazy<T>` or
  `Provider<T>` factory parameter with
  `provide.deferred-wrapper-qualification-required`. The plugin scans
  InnoDI's own sources along with the other dependency targets, and 6.0
  treated InnoDI's `Lazy` and `Provider` as same-module declarations, so every
  such parameter failed. Only a wrapper declared in the consumer's own module
  still requires `InnoDI.Lazy<T>` or `InnoDI.Provider<T>`. Declarations that
  share a path across the scanned targets, such as that consumer-declared
  `Lazy` or two containers with the same name in a target and its dependency,
  no longer crash validation with `Duplicate values for key`.

- The build plugin's shared-run validation cache key moves to version 10, so
  a workspace validated by an earlier build is validated once more under the
  7.0 rules. No action is required.

### Upgrade Actions

- Rewrite named-root parent key paths to `\Self.member`. `\Self.member` also
  compiles with 6.0, so this can land before the upgrade. Run the read-only
  check, review its report, then rerun the same command with `--write`:

  ```bash
  swift run InnoDI-Migrate --root /path/to/consumer --check
  swift run InnoDI-Migrate --root /path/to/consumer --report
  ```

  The same run gives every file that imports `InnoDISwiftUI` a full
  `import SwiftUI` at that import's access level, `@_exported` when that
  import is, raising an existing `import SwiftUI` when needed.

  Raise macOS deployment targets below 14 by hand, and replace
  `DIContainerHostOwner` publisher subscriptions with
  `withObservationTracking` or SwiftUI view reads.

  Nested parent key paths block the rewrite with
  `migrate.parent-key-path-unsupported`; name the intended direct member
  instead. Files that import another module may report
  `migrate.unqualified-ownership-ambiguous`, which now lists the modules
  involved. Qualify the attribute as `@InnoDI.SubContainer`, or add
  `--trust-module <name>` for each listed module that declares no
  InnoDI-named attribute or macro, typically the application's own modules.

- Move the other macro packages in the graph to SwiftSyntax `604.0.0`, or stay
  on InnoDI 6.x until they support it. Build with Xcode 27 to keep the
  prebuilt SwiftSyntax macro build; Xcode 26.x builds work but compile
  SwiftSyntax from source.

## 6.0.0

### Highlights

- 6.0 introduces explicit `@Input` and container roles, typed assisted child
  factories, injectable multibindings, graph contract gates, owned async
  preparation, on-demand services, and SwiftUI container lifecycle helpers.
  See the breaking changes and upgrade actions below before updating from 5.x.

- Release-note extraction handles long Unicode sections on macOS's system
  Bash without repeated full-string whitespace substitution. Exact content,
  missing-section, and empty-section contracts are covered by subprocess tests.

- Apple trace owners amortize OS random generation in a bounded, lazy 1 KiB
  batch while retaining random UUID v4 instance IDs. The owner lock protects
  batch refill and consumption; disabled tracing allocates no batch. The
  existing trace workloads and budgets are unchanged. See
  [profiling evidence](docs/internal/trace-performance-6.0.md).

- Runtime trace timing moves from mandatory CI/release gating to optional,
  exact-SHA manual diagnostics. Raw measurements and rejection checks remain;
  the reference budgets are not a 6.0.0 performance guarantee. Functional trace
  tests, sanitizer checks, and the separate macro-performance gate are unchanged.

- Trace sinks execute outside on-demand cell locks. Initializing state is
  installed before a start callback, and waiters recheck it after callbacks
  to avoid lost wakeups. Same-thread, same-cell reentry from any trace callback
  now diagnoses immediately; callbacks may safely resolve a different cell.

- Host phase observers may synchronously start or retry without losing the new
  generation's cancellation handle or overwriting its phase. Cleanup barriers
  are installed before notifications; replacements started from an idle or
  ready notification wait for the previous container's close hook.

- Independent macro-performance workloads now cover an assisted factory with
  8 static and 8 assisted inputs, 64-contributor multibinding, and 32-method mock
  generation. Run `Tools/measure-macro-features.sh`; CI archives all samples,
  dimensions, workload versions, compiler and SHA provenance separately.
  These v1 workloads are report-only until independently calibrated. They do
  not replace, update, or count toward the composite-v2 release/trend baseline.

- On-demand Sendable safety: unrestricted deferred cells no longer claim
  `Sendable`, even for a Sendable result, because arbitrary factory captures may
  be unsafe. Keep ordinary on-demand containers on their isolation domain;
  use eager storage or an explicitly main-actor container when appropriate.
  For nonisolated async factories, generated code now uses a separate checked
  handle requiring both a Sendable payload and an `@Sendable` factory, including
  transitive on-demand dependencies. Overrides preserve the same checks and
  still skip unused factories. Compiler-negative and runtime controls cover
  unsafe captures, payloads, regular/actor-isolated use and async dependency chains.
- Public collection metadata now uses checked `Sendable` conformance and accepts
  `AnyKeyPath & Sendable` at every construction boundary. Canonical member
  literals remain source-compatible; callers building arrays explicitly must
  preserve that intersection instead of erasing to `AnyKeyPath`. Mutable,
  non-Sendable subscript captures are compiler errors, not silently transferable
  metadata. The `@Provide(collection:)` canonical-member grammar is unchanged.
- Post-acceptance contract hardening:
  - Async waiter cancellation no longer retains completed-request IDs across
    scope resets. Caller cancellation is checked during actor-isolated
    continuation registration; late handlers only remove live waiters.
  - Public API baseline schema 9 additionally records typealias RHS identities,
    structure, actor isolation, Sendable and function effects. Compiler/consumer
    mutation tests distinguish source breaks from qualification/format changes.
    Generic RHS references use compiler-declared depth/index slots so direct
    symbol-graph emission and serialized-module extraction compare identically.
    Swift 6.2 omits function `@Sendable` from symbol graphs. The gate exports a
    compiler interface from each built module and records Sendable positions
    within alias type structure, including nested parameter/return/tuple
    functions. It never infers a missing effect from source text or the baseline.
    Nominal-scope lookup prevents same-named aliases from being conflated;
    missing or ambiguous compiler-interface declarations fail closed.
    Unknown nominal identities and ambiguous parameter metadata still fail
    closed. Tests exercise both compiler paths and distinct nested generic slots.
    This schema update changes no public declarations.
  - Release exact-revision consumers preserve preflight's annotated-tag/main
    ancestry contract after normal main progress. Untagged initial dispatches,
    rewritten history and mismatched checkouts still fail closed.
  - All seven READMEs now use the 6.0.0 package dependency and versioned
    documentation, with a source-migration link for existing 5.x consumers.

- Follow-up hardening of the c7 review candidate:
  - Validation reads and hashes source bytes before reusing any AST digest,
    including metadata-identical edits. Digest-cache version 7 invalidates old
    records; `metadata-hit` now means matching metadata **and** verified bytes.
  - Public API baseline schema 6 retains named actor attributes, isolation,
    public setter availability, mutating methods/getters and nonmutating
    setters (including subscripts). Real compiler/consumer fixtures cover
    breaking changes and formatting-only controls; no public symbols were
    added or removed by this baseline update.
  - Detached transient resolvers share typed dependency-only factory code
    instead of recursively duplicating diamond dependency paths. Each call
    still creates fresh transient values; overrides, lazy resolution and
    escaped-handle ownership remain unchanged.
  - Async preparation uses iterative traversal for deep valid/cyclic graphs,
    preserving declaration-order traversal and reverse close order.
  - Permanent async-scope close releases its stored factory captures. An
    already-running operation retains its own captures until it returns.
  - SwiftPM DAG validation emits a comment-only generated Swift input so the
    consumer compiler waits for the gate instead of racing and cancelling its
    structured diagnostics on warm builds. Clang targets retain report-only
    outputs; Xcode's multi-destination always-run gate remains unchanged.
  - Doctor verification and Graphviz use owned process groups and bounded
    in-memory output tails (16 KiB per stream; merged for Doctor). Doctor keeps
    its 300-second timeout; Graphviz now has a 30-second timeout. Group cleanup
    has a 200 ms TERM grace then KILL, and signalled exit codes use 128+signal.
    Descendants that deliberately leave the owned group are not forcibly
    discovered or terminated. This is not a sandbox for untrusted commands.
    Closed caller standard streams are normalized before spawn so child
    output remains correctly separated or merged.
  These changes do not migrate standalone products, approve a new performance
  baseline, or constitute release approval. Upgrading existing 5.x consumers
  is not a prerequisite for publishing the 6.0 library.
- SampleApp resolves its local dependency and DAG plugin using the checkout
  directory's normalized SwiftPM identity, matching the other examples.
  Renamed-checkout CI now tests and runs SampleApp as well as building the
  SwiftUI examples; no canonical `InnoDI` directory name is required.
- Accepted [RFC 0006](docs/rfcs/0006-assisted-subgraphs-and-container-roles.md)
  following explicit owner approval on 2026-09-24, after the promotion PR's
  seven-day cooldown. This freezes the 6.0 assisted-factory, `@Input`, explicit
  container-role and multibinding syntax, including the documented replacements
  for 5.x declarations. It records design acceptance, not a GitHub PR review,
  merge, tag or release approval. Publication is established by the exact-SHA
  Release Gate and immutable GitHub Release, not by RFC acceptance.
- Re-audited all 46 excellence requirements and 25 follow-up findings against
  code candidate `6332864ea83743fd5fec99c95b98a91b1b06ae8b`. A clean Swift 6.4
  strict coverage run passed 355 tests in 37 suites with package line coverage
  90.28% and `InnoDIMacros` 90.75% (floor 90.70%). Public API, graph schema v6,
  DocC, localized README, link, validation-escape-hatch, fatal-trap, alias and
  runtime trace performance contracts also passed. The synchronized exact
  branch HEAD is rechecked by the release-validation matrix and consumers.
  These are historical candidate measurements, not the final release proof.
- Hardened the 6.x release-candidate validator so publication fails closed
  unless RFC 0006 has exactly one `Accepted` status in both its authoritative
  document and the RFC index. Pending, missing, duplicate, and inconsistent
  records are covered by executable release-contract tests.
- **6.0 breaking ownership correction (R02):** `Lazy<T>` and `Provider<T>`
  no longer exempt dependency cycles. Local cycles are compile errors even
  with `validateDAG: false`; global DAG checks also include deferred edges.
  Migrate mutual references by extracting shared state or restructuring the
  graph. Acyclic forward references, transient re-entry, and escaped handle
  lifetime remain supported. No explicit scope-close API is introduced.
  The earlier candidate measurements immediately above predate this correction;
  see [final hardening](docs/plans/6.0.0-final-hardening.md).
- Migration publication and rollback now use a preserving atomic exchange
  (R01/R09), never an unconditional overwriting rename. Every displaced entry
  remains at a reported recovery path, including after success, so late writes
  through open editor descriptors are retained. A conflict exits nonzero and
  requires review of source and recovery paths; no unsafe restore is attempted.
  POSIX source modes are restored independently of umask. Doctor schema v3 adds
  `recoveryPaths`; migration's read-only report remains schema v1.
- `DIContainerHostOwner.close()` releases stored factory/close captures before
  suspension, without clearing a reentrant new generation's callbacks (R03).
- Subgraph retry now reserves library-owned scopes before checking states and
  commits all affected generations before release (R04/R05). Selected custom
  `DIAsyncPreparing` providers fail with `nonTransactionalProvider` before any
  mutation; prepare/close support remains. `DIAsyncScope` status/retry/reset/close
  are explicitly asynchronous, including calls made from actor-isolated code.
  Concrete, existential, and generic reset calls now share the same semantics.
- Added graph explainability commands: `--why` traces a shortest root path,
  `--dependents` reports reverse impact, `--unused` finds containers outside
  every rooted graph, and `--diff` compares two schema-v6 JSON artifacts.
  `--diff ... --check-contract` turns that comparison into a CI gate: unchanged
  contracts exit 0 and any scope, node, or edge drift, including assisted input,
  assisted-factory ownership, or ordered contribution changes, exits 5 while
  preserving the human-readable diff. Schema v6 treats canonical factory
  parameter wiring and fixed/assisted child binding pairs as contract. It
  additionally records explicit collection kind, keys, order, contributor IDs,
  and contributor lifetimes. It rejects earlier schemas, missing binding
  metadata, and malformed collection contracts rather than treating them as
  unchanged. Regenerate older baselines before
  comparing them with this candidate. Query selectors now check container and
  provider namespaces together. Cross-namespace collisions list both candidate
  sets and require `container:` or `provider:`; exact graph IDs remain stable,
  and provider dependents follow canonical binding IDs rather than parameter
  labels. Fixed-child and assisted-factory queries also follow canonical parent
  input bindings per mount. JSON validation rejects dangling/foreign references,
  invalid ownership, and incomplete ordinary child input coverage before diffing,
  including identical invalid inputs.
- Connected generated providers to opt-in runtime tracing. Container,
  component, override, on-demand, transient, and async paths now carry the
  canonical schema-v6 provider identity, container owner, and generation;
  start/terminal, override, cache-hit, and wait relationships are emitted
  automatically. The disabled default still avoids UUID/event/buffer
  allocation, events remain metadata-only, and opaque work started inside a
  service is deliberately outside the trace boundary.
- Completed generated-mock stub preflight across properties, ordinary returns,
  untyped and typed throwing functions, and generic handlers. Setup state is
  independent from optional storage, so an explicitly stubbed `nil` is not
  reported as missing. Unnamed parameters now receive legal body identifiers;
  unsupported generic typed throws and static properties fail at the source
  attribute without emitting a partial conformance.
- Added generation-aware reset to actual generated mocks. `.calls` atomically
  closes and returns the current call-history snapshot while preserving stubs;
  `.all` also returns every stub to its missing state. `Sendable` mocks use one
  shared critical region, and `@MainActor` mocks use actor serialization, so a
  racing call belongs to exactly one generation.
- Added `InnoDI-Migrate --report` for deterministic schema-v1 JSON inventories
  before migration writes. Reports expose paths, stable codes, counts, status,
  and diagnostics without including original or migrated source bodies.
- Removed the superseded underscored assisted-factory SPI after the public
  `@Input(.assisted)`, `@AssistedFactory`, and `@SubContainerFactory` surface
  replaced its same-target, cross-module, runtime-isolation, and override
  evidence. The SPI was never covered by SemVer and no recorded pilot remains
  pinned to it.
- The public assisted-factory bridge now preserves `@MainActor` on its
  initializer, call, and override-application closure. A same-target Swift 6
  strict-concurrency fixture guards the exact Xcode consumer shape that would
  otherwise reject override forwarding as a non-Sendable actor crossing.
- Added public `@Multibinding` for one injectable deterministic ordered
  collection from explicit local synchronous providers with the same written
  type. Macro, serialized validation, graph-v6, and strict external-consumer
  tests cover invalid contributors, injection, shared/transient lifetime
  behavior, contributor order, and overrides. The superseded underscored SPI
  has been removed after public consumer migration.
- Verified the public RFC 0006 runtime and SwiftUI host pilot in InnoSample
  commit `ec88716` against validated InnoDI code candidate
  `f1a3eaccf19bfc43164de3621c9197c731d92342`. The People route passes the
  consumer's full Xcode 27 gate, proves per-child shared-state isolation plus
  overrides, and replaces its manual state wrapper with `DIContainerHost`.
- Added two more committed consumer pilots against that code candidate. BlPia
  `c12560d` passes Doctor over 160 Swift files, an unchanged second migration
  pass, DAG validation, 10 test schemes, and a generic iOS/watch build; the
  strict hierarchy gate also corrected seven manually provided containers from
  `component` to `local` ownership. Lynceus `3edb77b` passes Doctor over 81
  Swift files, an unchanged second pass, a real
  two-container full-root DAG, 41 tests, and its macOS build. Mulbyul was tested
  without source changes and is deliberately not counted as a committed pilot.
- Refreshed the consumer boundary for the T42 candidate in isolated clones.
  InnoSample passes exact resolution, DAG, Remote tests, leaf/root features and
  generic iOS/watch builds. BlPia passes layer/feature/app tests and iOS build
  after explicitly linking trace runtime support into static test bundles.
  Lynceus passes format, Tuist sync, macOS build and all tests; Doctor correctly
  marks its helper-based Tuist target mapping analysis-incomplete instead of
  healthy. Mulbyul committed HEAD `092ff951` remains test-only: its isolated
  `Layers` build reaches the expected legacy `@Provide(.input)` source break,
  while read-only Doctor reports 481 files, one proposal and 11 errors without
  applying a change. The original Mulbyul and mixed BlPia checkouts are
  preserved.
- Hardened migration and workspace analysis from real-consumer evidence:
  ambiguous unqualified 6.0 vocabulary now fails closed (`dc34d14`), Doctor
  recognizes direct Tuist package workspaces (`ac1124b`), and skipped hidden
  files no longer suppress following source siblings during full-root graph
  discovery (`28a95a5`).
- Added isolated Thread Sanitizer and Address Sanitizer suites to both the main
  validation workflow and the SHA-bound release gate. They run every applicable
  in-process strict-concurrency test from separate scratch paths so sanitizer
  state cannot be reused across lanes; separately spawned fresh-consumer builds
  remain covered by the exhaustive and compatibility jobs.
- Hardened Xcode 27 / Swift 6.4 release preparation: external-consumer
  diagnostics now preserve exact toolchain-specific compiler output, while the
  public API guard tracks only source-authored product declarations instead of
  SDK symbols re-exported by toolchain-specific SwiftUI symbol graphs. The
  schema-v4 API baseline also preserves a per-parameter default-presence vector:
  removing a default now fails even when the symbol identity does not change.
  Declaration formatting and default-expression values are not API identity;
  executable compiler/consumer fixtures verify the omitted-argument contract.
  Macro defaults are recovered even when older compiler symbol graphs omit
  `functionSignature`; missing metadata is not silently treated as no defaults.
  The
  coverage collector now accepts both the combined package test bundle used by
  earlier toolchains and Swift 6.4's per-target test bundles, including public
  executable entry points without lowering any checked-in floor.
- The 6.0 vocabulary migrator and examples now emit a required `role:` label
  with a named, string-backed `ContainerRole` token and the established
  `mainActor: true` option. This avoids a Swift 6.2.3 compiler signal 11 while
  matching a public enum argument in the multi-role attached
  `@DIContainerRole` expansion, without dropping Xcode 26.2 compatibility from
  the release gate. Arbitrary strings fail with a stable InnoDI diagnostic.
- Added owned on-demand and async preparation scopes, a SwiftUI container host,
  concurrency-safe public testing support, explicit cross-module ordered/keyed
  provider collections, schema-v6 provider contract queries, metadata-only
  bounded runtime tracing, and a read-only-first `InnoDI-Doctor` workflow for
  the 6.0 candidate.
- Added `@Provide(collection:)` closed metadata for factory-built ordered,
  keyed, value, and provider collections. Key identity, order, canonical
  contributor, and declared contributor lifetime are contractual across graph
  artifacts; explicit empty is valid, duplicates fail, and no factory-body or
  module discovery is performed.
- Async preparation now rejects already-cancelled waiters before factory start,
  reports request and owned-operation cancellation separately from failure,
  and retries a failed selected child plus its downstream in fresh generations
  while preserving ready explicit parent dependencies.
- Generated override fallbacks now parenthesize precedence-sensitive raw factory ASTs, full-source
  validation rejects out-of-order child `bindings:` at the first mismatching
  key path, and async overrides no longer resolve dependencies used only by a
  bypassed live factory.
- Feature-root helpers now include an identity-taking `DIContainerHost`
  overload, hosted content receives an explicit lifecycle handle through the
  SwiftUI environment, and `#PreviewWithContainer` constructs lazily through
  the same generation owner. Existing direct and manual host APIs remain.
- Added explicit `@Provide(effect: .sideEffect)` metadata and generated
  `Overrides` completeness reporting. Test and preview targets can use
  `InnoDITesting` strict preflight to reject missing effect overrides before a
  live factory runs; recording mode returns the same deterministic report.
  Unmarked opaque factories remain unclassified, and production construction
  does not enable this opt-in policy globally.

### Breaking and Behavior Changes

- **New 6.0 vocabulary:** replace `@Provide(.input)` with `@Input`. Replace
  `@DIComponent`, `@DIHierarchyRoot`, and the former `@DIContainer(root:mainActor:)`
  options with `@DIContainerRole(role: ContainerRole.component)` for mountable
  features, `ContainerRole.root` for roots, or `ContainerRole.local` for local
  isolation. Add `mainActor: true` to the role macro when needed. Each
  declaration uses one container macro; ordinary containers continue to use
  `@DIContainer`.
- **Deferred ownership:** `Lazy` and `Provider` no longer make dependency cycles
  valid. Local cycles are rejected even with `validateDAG: false`, and the
  global DAG includes deferred edges. Ordinary on-demand storage is not
  `Sendable`; nonisolated async dependency handles require a Sendable payload
  and an `@Sendable` factory. Keep non-Sendable state in its isolation domain.
- **Collection metadata:** explicitly assembled key-path arrays must preserve
  `AnyKeyPath & Sendable`. The old assisted-factory and multibinding SPI is
  removed; use `@Input(.assisted)`, `@AssistedFactory`, `@SubContainerFactory`,
  and `@Multibinding`.
- **Graph and tooling contracts:** graph JSON is schema v6 and older baselines
  are rejected. Doctor schema v3 adds migration recovery paths; its read-only
  migration inventory remains schema v1. Ambiguous graph selectors require
  `container:` or `provider:`. A contract diff exits 5 on semantic drift.
- **Owned async lifecycle:** `DIAsyncScope` status, retry, reset, and close are
  explicitly async. Transactional subgraph retry rejects selected custom
  `DIAsyncPreparing` implementations before mutation; prepare and close remain
  supported. Applications own shutdown and should await close hooks.
- **Migration safety:** applying or rolling back a migration preserves each
  displaced entry at a reported recovery path, even after success. Conflicts
  exit nonzero instead of overwriting late editor changes. Review recovery
  paths before removing them.
- **Tracing and mocks:** generated initializers and override operations add a
  defaulted `_innoDITrace:` parameter. Trace decoders must accept owner,
  generation, origin, related identities, and wait events. Same-cell synchronous
  trace callback reentry is diagnosed. `@GenerateMock` remains experimental;
  6.0 does not make its generated helper layout a stable API.

### Upgrade Actions

1. Read the [5.x to 6.0 migration guide](Sources/InnoDI/InnoDI.docc/MigrationGuide.md#5x--60-vocabulary)
   and the accepted [RFC 0006](docs/rfcs/0006-assisted-subgraphs-and-container-roles.md)
   before changing the package requirement to `from: "6.0.0"`.
2. From an InnoDI 6.0 checkout, run these read-only checks first, replacing
   `/path/to/consumer` with the consumer's package or source-tree root:

   ```sh
   swift run InnoDI-Doctor --root /path/to/consumer
   swift run InnoDI-Migrate --root /path/to/consumer --check
   swift run InnoDI-Migrate --root /path/to/consumer --report
   ```

   `--check` exits 1 when migration is required; inspect the report rather than
   treating that result as a tool crash. Review the proposed vocabulary changes,
   commit or back up consumer work, then replace `--check` with `--write` only
   when ready to apply them. Resolve dynamic/conflicting sites manually and
   inspect any reported recovery paths.
3. Replace cyclic deferred wiring, removed SPI, and erased collection key paths.
   Rebuild actual consumers under complete strict concurrency with warnings as
   errors; validate factory captures as well as their result types.
4. Regenerate both graph baselines with the same 6.0 tools before enabling
   `--diff ... --check-contract`. Update JSON readers and trace event decoders
   for the schema and metadata changes above.
5. Exercise async cancellation/retry/close, on-demand overrides, and SwiftUI
   host replacement in each adopting application. Existing products may remain
   pinned to 5.x; publishing the library does not migrate them automatically.

## 5.1.0

### Highlights

- Added native Xcode build-tool plugin support to
  `InnoDIDAGValidationPlugin`, allowing native Xcode and Tuist-generated
  targets to run the same build-time coordinator used by SwiftPM consumers.
- Added a Tuist workspace fallback that discovers the workspace root and
  validates all production Swift sources, preserving cross-project container
  references in the source DAG.
- Extended workspace-analysis manifest validation and module-graph diagnostics
  to accept the additive `xcode` build-system identity namespace.

### Breaking and Behavior Changes

- Xcode validation commands intentionally declare no output files because
  multi-destination variants can share one plugin work directory. Xcode may
  therefore schedule the validation command during every build.
- The Xcode plugin API does not expose Tuist's complete cross-project target
  dependency topology. The Tuist fallback validates the full source DAG and
  declaration contracts, but module-edge hierarchy rules that depend on the
  exact target graph still require a topology-aware SwiftPM or CI check.

### Upgrade Actions

- Native Xcode and Tuist consumers should attach
  `InnoDIDAGValidationPlugin` to every target that declares an InnoDI container
  or standalone `@DIEnvironmentBridge`.
- Keep a topology-aware hierarchy check in SwiftPM or CI when cross-module
  `@DIComponent` / `@DIHierarchyRoot` relationships are a release gate.

## 5.0.0

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
- Added the public `InnoDI-DependencyGraph` executable product and stabilized
  graph JSON schema v2 around module-qualified node identities, explicit
  target scope, and explicit root-pruning metadata.
- Added a tracked-Markdown local-link gate so moved or removed documentation
  targets fail pull-request and release validation before DocC publication.
- Pinned every external GitHub Action to a full commit SHA, disabled persisted
  checkout credentials outside the dedicated performance-history writer, and
  scoped Pages write/identity permissions to the deploy job.
- Removed the unpublished `InnoDIValidationTools` placeholder package. It was
  not a usable product and did not reduce the macro-only consumer build floor;
  RFC 0005 keeps prebuilt validator publication out of the 5.0 contract.
- Updated the exact swift-syntax pin to `603.0.2`. Apple Swift 6.3.3 in Xcode
  26.6 provides a matching MacroSupport prebuilt for this patch, while Swift
  6.3.2 in Xcode 26.5 remains compatible through a SwiftSyntax source build.
  The prior `603.0.1` pin fell back to source on both toolchains.

### Breaking and Behavior Changes

- **Validation cache digests changed:** the stable hasher behind AST digests,
  raw content hashes, and shared-run cache keys now mixes 8-byte blocks
  instead of single bytes while preserving one digest for a byte sequence
  regardless of `combine` call boundaries. All digests change, so the AST
  digest manifest version moved to `6` and the shared-run cache key prefix to
  `shared-run-v9`. The first build after upgrading revalidates once and
  repopulates both caches; no action is required.
- **`InnoDI-DependencyGraph` exit-code change:** a workspace that contains no
  `@DIContainer` now exits with code `4` instead of `1`, so scripted callers
  can distinguish an empty-but-healthy project from a genuine failure. Exit
  codes `0` (success), `1` (failure), `2` (I/O error), and `3` (DAG validation
  failure) are unchanged.
- **Build dependency compatibility change:** InnoDI now resolves swift-syntax
  exactly at `603.0.2` so Swift 6.3.3/Xcode 26.6 consumers can use the
  toolchain-provided MacroSupport prebuilt without giving up SwiftSyntax 603
  syntax support. Swift 6.3.2/Xcode 26.5 remains supported but compiles
  SwiftSyntax from source on a cold build. A consumer that directly pins
  swift-syntax to `603.0.1` must remove that unnecessary direct dependency or
  align it to `603.0.2` before adopting InnoDI 5.0.
- **Intentional breaking change:** `@DIContainer` and `@DIComponent` now accept only effectively non-generic
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
- **Contract-restoring behavior correction:** The shared build-validation
  cache salt is now v7 so a workspace cannot reuse a green result produced
  before target-topology signatures and the target-scoped full-source
  generated-qualifier preflight existed.
- **Contract-restoring behavior correction:** Generated module-qualifier
  preflight now validates only support qualifiers actually emitted by locally
  viable managed members. A valid async `@Provide` peer keeps its `Swift` and
  `_Concurrency` checks even when an invalid container-owned sibling suppresses
  member-body generation; `mainActor: true` still retains its explicit `Swift`
  requirement.
- **Intentional breaking change:** Targets that declare an InnoDI container or
  a standalone `@DIEnvironmentBridge` must attach
  `InnoDIDAGValidationPlugin`. Its target-scoped full-source pass extends
  generated module-qualifier diagnostics to visible sibling-file, enclosing,
  matching-extension, and imported dependency declarations. It also rejects
  `@DIEnvironmentBridge` attached directly to an extension, nested in an
  extension, or declared inside executable code. Move bridge targets to file
  or nominal scope and rename `InnoDI`, `Swift`, `_Concurrency`, `SwiftUI`, or
  `InnoDISwiftUI` shadows according to the diagnostic.
- **Contract-restoring behavior correction:** Root-path graph rendering now
  fails when any discovered Swift source cannot be read or decoded. It no
  longer warns and renders a partial graph that could omit a validation site.
- **Intentional breaking change:** Public `@Provide` now accepts only a direct, plain, stored instance `var` in
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
- **Intentional breaking change:** A property accepts exactly one `@Provide`; duplicate attributes are rejected
  with `provide.duplicate-attribute`. Opaque `some Protocol` provider types are
  rejected with `provide.opaque-type-unsupported` and must become
  `any Protocol`. Implicitly unwrapped `T!` provider types are rejected with
  `provide.iuo-type-unsupported` and must become explicit `T` or `T?`.
- **Intentional breaking change:** `.shared` and `.transient` providers now require exactly one construction
  source from `factory:`, `asyncFactory:`, `Type.self`, or a property
  initializer. `.input` providers reject all four sources and `with:`.
- **Intentional breaking change:** The public `@Provide` signature no longer accepts `concrete:`. The declared
  property type is the single source of truth for storage and override shape:
  a concrete nominal type produces concrete storage, while `any Protocol`
  produces existential storage. No replacement positional token or inference
  flag is added.
- **Contract-restoring behavior correction:** `.input` initializer parameters remain eager `T` values, preserving normal
  `try` / `await` argument evaluation. Direct non-optional function types are
  detected and emitted as escaping parameters automatically. A non-optional
  function type hidden behind a typealias uses the literal opt-in
  `@Provide(.input, escaping: true)`. Other scopes and obvious
  nonfunction/optional-function shapes receive stable diagnostics; Swift may
  diagnose a conservatively accepted alias that does not resolve to a
  non-optional function.
- **Intentional breaking change:** Sibling DI edges now have a closed syntax: named parameters on the root
  `factory:`/`asyncFactory:` closure literal, or `Type.self` plus a literal
  `with:` array containing only canonical direct-member key paths spelled
  exactly `\Self.member`, such as `[\Self.config]`; `[]` is also valid. Named
  container, module-qualified, and typealias roots are rejected, as are nested
  components, optional chaining, subscripts, and computed elements. `with:` is
  valid only with `Type.self` and can target synchronous providers only.
  Non-closure factories and property initializers are opaque zero-edge sources
  and may not read sibling container members.
- **Contract-restoring behavior correction:** Factory effects are explicit and checked on every explicit sibling edge.
  `validateDAG: false` does not suppress async/throwing compatibility errors.
- **Intentional breaking change:** The deprecated `@DIFeatureRoot` compatibility macro is removed. Declare
  SwiftUI roots through `@SubContainer(featureRoot:)` or `featureRoots:`.
- **Contract-restoring behavior correction:** Every `@DIContainer`, including a container with no managed members, now
  synthesizes the complete `Overrides` and trailing-override initializer ABI
  required for `@SubContainer` mounting. A user-declared nested `Overrides`
  type is now a terminal `container.overrides-name-conflict` error instead of
  suppressing only part of that ABI. Valid containers expose the reserved
  compiler-support alias `_InnoDIMountOverrides = Overrides`; generated parent
  mounting code uses it so an invalid child cannot bind to a user-collidable
  `Overrides` declaration. Consumers must not declare or reference the alias.
- **Intentional breaking change:** Every stored instance member in a container must now be managed by
  `@Provide` or `@SubContainer`; computed and type properties remain supported.
  Unmanaged stored state receives `container.unmanaged-stored-property` before
  the generated initializer could remove or conflict with a memberwise init.
- **Contract-restoring behavior correction:** With `validateDAG: false`, unresolved `Lazy<T>` and `Provider<T>` factory
  parameters now receive the same typed runtime-trap fallback as unresolved
  hard dependencies. This preserves the explicit opt-out without leaking an
  internal code-generation invariant or partial child storage.
- **Contract-restoring behavior correction:** `mainActor: true` now covers the whole generated surface: dependency
  accessors, every generated initializer, `Overrides`, the `applyOverrides`
  function types used by convenience initializers, `withOverrides`, child
  overrides, and component mounting, all four `withOverrides` operation
  closures, and feature-root helpers generated by `@SubContainer`.
- **Contract-restoring behavior correction:** For containers without `mainActor: true`, generated `async` and
  `async throws` `withOverrides` methods and their operation closure types are
  `nonisolated(nonsending)`. They retain the caller's actor executor, so
  arbitrary non-`Sendable` containers and closures do not cross isolation.
  Synchronous overloads are unchanged; main-actor overloads remain
  `@MainActor`.
- **Intentional breaking change:** Main-actor components now conform to the dedicated
  `_InnoDIMainActorComponentMountable` protocol; ordinary components continue
  to use `_InnoDIComponentMountable`. This split preserves the actor type on
  generic mounting override closures.
- **Intentional breaking change:** Graph JSON output is schema v2. JSON render
  mode requires a target-scoped `--analysis-manifest` plus an explicit
  `--root-pruning all|roots`; the legacy `--root` input remains available for
  text rendering and DAG validation but cannot emit schema v2 JSON. Node IDs
  are module-qualified, and the document records selected target and pruning
  scope.

### Upgrade Actions

- Remove a direct consumer dependency on swift-syntax when it exists only to
  constrain InnoDI transitively. If the consumer implements its own macros,
  align that package graph to swift-syntax `603.0.2` before resolving 5.0.
- Run the migration tool from the consumer package or workspace root, then
  review the diff and confirm a clean final check:
  ```sh
  swift run InnoDI-Migrate --root . --check
  swift run InnoDI-Migrate --root . --write
  swift run InnoDI-Migrate --root . --check
  ```
  It removes supported `concrete:` arguments and migrates supported deprecated
  feature-root declarations atomically. Resolve any reported ambiguous site
  manually before rerunning `--write`; the tool leaves the workspace unchanged
  when it cannot prove a safe migration.
- Delete any remaining `concrete:` argument and express the intended storage
  shape with the declared property type. Use a concrete nominal type for
  concrete storage or `any Protocol` for existential storage and overrides.
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
- Attach `InnoDIDAGValidationPlugin` to every target that declares a container
  or standalone `@DIEnvironmentBridge`. Rename generated-qualifier shadows
  reported from sibling files, enclosing members, matching extensions, or
  visible dependency targets. Move direct-extension, extension-nested, and
  local bridge targets to file or nominal scope. Ensure every Swift source
  below a legacy `--root` graph input is readable UTF-8 because partial graph
  rendering is no longer accepted.
- Invoke the public graph command with `swift run InnoDI-DependencyGraph`.
  Update JSON consumers to decode schema v2, provide a target-scoped
  `--analysis-manifest`, and choose `--root-pruning all` or `roots`
  explicitly. Do not request JSON with the legacy `--root` input.
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
- Keep consumer package requirements on 4.3.0 during development. Only the
  final, fully validated release-candidate commit updates the repository's
  installation snippets to 5.0.0; the SHA-bound workflow must be dispatched
  immediately so it can create and verify that tag.

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
  the current lower envelope against the rolling median of recent
  lower envelopes (default window 7, threshold 20%, same-toolchain filter on)
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
  generated helper storage names are not release-frozen until its independent
  future GA criteria pass.

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
