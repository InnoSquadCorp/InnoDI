# Explicitly Owned Containers

Opt in to a generated owner when asynchronous shared providers need explicit
preparation, cancellation, retry, and shutdown.

These APIs are included in the unreleased 7.0 candidate. Public API baseline
review and supported Apple toolchain qualification remain pending.

## Opt In at the Declaration

`generateOwned: true` is available on both `@DIContainer` and `@DIContainerRole`.
Keep the same `@Input`, `@Provide`, factories, and dependency parameters:

```swift
@DIContainer(generateOwned: true)
struct Services {
    @Input var seed: Int

    @Provide(.shared, asyncFactory: { (seed: Int) async in seed + 1 })
    var first: Int

    @Provide(.shared, initialization: .onDemand,
             asyncFactory: { (first: Int) async in first + 1 })
    var service: Int
}

let owner = try await Services.makeOwned(seed: 40)
do {
    let report = try await owner.prepare(.service)
    if report.isReady {
        let value: Int = try await owner.container.service
        print(value)
    }
} catch {
    await owner.close()
    throw error
}
await owner.close()
```

Omitting the flag or writing literal `false` emits no owned API. The existing
initializer remains unchanged even when the flag is enabled. `makeOwned` builds
its own concrete storage; it does not initialize a legacy container and adopt
its tasks. There is no second registration DSL and no automatic shutdown on
scope exit.

## One Prepared Operation

For a short operation, use the generated `withPrepared` instead of manually
checking a preparation report and closing in both success and error branches:

```swift
try await Services.withPrepared(.service, seed: 40, overrides: { overrides in
    overrides.service = 99
}) { services in
    let value = try await services.service
    print(value)
}
```

The helper is generated only for `generateOwned: true` containers with async
shared providers. The typed selections have the same meaning as `prepare`;
additional selections precede the labeled input arguments. The `overrides:`
closure defaults to an empty mutation and may throw. It runs before any live
factory, child, or owned task is constructed. The operation is nonescaping; its result
does not gain a `Sendable` requirement. MainActor isolation is preserved.

`withPrepared` creates a fresh owner, prepares the selected subgraph, and enters
its operation only when every report entry is ready. A failed, blocked,
cancelled, or closed entry throws ``DIAsyncPreparationFailure`` carrying the
preparation snapshot. The helper awaits `close()` before returning a result or
throwing from preparation or the operation. There is no detached cleanup task.
Independent eager providers still start according to their existing policy;
selecting one provider does not prove unrelated eager providers are healthy.

Cancellation and error precedence are explicit:

- A call already cancelled on entry is rejected before the override callback
  and live work; cancellation inside the callback is checked before live construction
- After preparation, caller cancellation is checked before the readiness report
- An operation-thrown error is preserved even if the caller is also cancelled
- A successful operation checks cancellation after close completes, so a
  cancelled caller receives `CancellationError` rather than its successful value

Cancellation is cooperative. An operation that ignores cancellation and never
returns keeps the helper suspended. Close does not drain cancellation-ignoring
factories, close arbitrary application tasks, or call a service's `shutdown()`.
It owns only the generated async scopes. Borrowed inputs, synchronous values and
children remain borrowed. Swift can return or capture a dependency view from the
operation: later async reads fail as closed, but synchronous values and already
returned service objects are not revoked.

For a long-lived screen that keeps its owner across a retry UI, use
`try await owner.requireReady(.service)`. This checks cancellation and throws on
a non-ready report without closing the owner. `retryAndRequireReady(.service)`
performs exactly one existing retry transaction and then the same check; it is
not a refresh operation or an automatic retry loop. Existing `prepare` and
`retry` report methods remain available for detailed loading state. A report's
synchronous `requireReady()` checks only its snapshot, not task cancellation.
Original factory errors can still be obtained from an open provider read; after
`withPrepared` has closed its owner, an escaped view instead reports closed.

## Admission, Readiness, and Selection

`makeOwned` is `async throws`. It completes setup and admits each eager async
provider before returning; it does not wait for those providers to become ready.
On-demand async providers start through a read or preparation. Construction
cancellation or setup failure closes the allocated owned scopes before throwing.

`prepare(.service)` follows the selected async dependency graph and returns a
``DIAsyncPreparationReport``. Inspect `isReady` and the entries for failed or
blocked providers. `status(.service)` returns the selected concrete scope's
``DIAsyncProviderStatus``. Tokens contain only async shared providers and cannot
be used as service resolvers or exchanged between different container types.
Sync-only owned containers have `close()` but no selection enum or selection
methods.

Every owned async read is `async throws`, including a provider whose authored
factory is nonthrowing. The read can observe lifecycle cancellation or close.
The authored factory's effect contract is unchanged; dependency arguments are
resolved before its invocation.

## Cancellation, Retry, and Close

- `await owner.cancel(.service)` affects only selected scopes that are running
  at each scope's individual cancellation point. Idle, ready, failed, cancelled,
  and closed states are unchanged. There is no admission pause, implicit
  dependency cancellation, or atomic transaction across several selections
- A cancelled scope retains its factory. `try await owner.retry(.service)` uses
  the existing preparation plan's explicit failed/cancelled-subgraph retry and
  generation rules. A late result from an older generation cannot replace the
  current one. Reads of a cancelled scope continue to fail until explicit retry
- `await owner.close()` closes the shared admission gate, then closes async
  scopes in reverse graph order. Concurrent close calls await the same
  completion, including outstanding lifecycle cleanup. Reads admitted before
  the barrier can win the scope-local race; later reads, including cached reads,
  fail with ``DIAsyncScopeError/closed(providerID:)``
- Close cancels work but does not drain a user factory that ignores cancellation.
  Such a factory can finish later; its result is discarded. Close does not call
  shutdown methods on returned services or revoke a value already handed out

## Overrides, Copies, and Borrowed Values

`makeOwned` accepts the existing input and direct value-override slots, shared
child overrides, child override closures, and `_innoDITrace`. An async value
override seeds a ready scope without running its factory. Its preparation node
has no factory dependency edges, while the complete declared graph is still
validated. Other declared eager providers start independently, even when an
overridden consumer no longer needs them.

Use `makeOwnedWithOverrides` with the existing `Overrides` builder when
several tests share an override preset:

```swift
let owner = try await Services.makeOwnedWithOverrides(seed: 40) {
    $0.service = 99
}
// A prebuilt or validated preset can be assigned with: { $0 = preset }
```

A cancelled task is rejected before the override closure runs. The nonescaping
closure may throw and runs before any live factory, child, or
owned task is constructed. Its values forward to the same direct `makeOwned`
path. Optional payload overrides keep the existing distinction: `.some(nil)`
means an explicit nil value, while an unset builder slot uses the live factory.
This convenience does not automatically validate side-effect overrides or close
the returned owner; use existing preset validation and explicit `close()`.

The separate method name preserves existing `makeOwned` trailing closures that
configure a child container. Both methods return the same explicit owner type.

Owner copies and escaped dependency-view copies share the same scopes and
terminal gate. Separate `makeOwned` calls are independent. Inputs, synchronous
shared values, and plain shared child containers are borrowed values for async
lifecycle purposes. Parent close does not close them, and escaped views can still
read synchronous values afterward.

Synchronous `.transient` providers also keep their ordinary per-read contract.
Each access invokes a typed factory without caching its result; a direct value
override returns that same override on each access without running the live
factory or resolving its dependencies. Independent eager providers still follow
their own initialization policy. A transient is not a preparation node and has
no cancel/retry/status token. Its synchronous getter remains usable after close,
just like the other synchronous getters. The caller owns returned values;
`close()` does not dispose or invalidate every service object in the view.
Transient resolver closures retain their typed dependencies, not the lifecycle
owner or coordinator. Diamond paths invoke a shared resolver independently; they
do not turn a transient into a cache.

## Synchronous Deferred Dependencies

Owned construction supports the existing synchronous `InnoDI.Lazy<T>` and
`InnoDI.Provider<T>` factory parameters. Lazy can target an input or synchronous
shared/transient provider; Provider requires a synchronous transient. Lazy does
not add caching to a transient target. The existing graph still rejects ownership
cycles, invalid targets and direct eager wrapper calls during shared construction.

Forward targets use concrete local cells, bound before asynchronous startup.
They capture only their target values or resolvers, never the whole view or owner.
Creating a wrapper does not trigger an on-demand factory. Direct or builder
overrides preserve identity, factory bypass and optional-nil behavior. Escaped
handles remain usable after close, consistently with other synchronous getters.

These owned deferred cells and the wrapper values are non-Sendable. They cannot
be captured by an ordinary asynchronous factory or by an on-demand factory that
must be Sendable for async use; Swift reports the invalid capture rather than
accepting unchecked transfer. MainActor-isolated async consumers are supported
when Swift verifies the complete capture and result types. This extension does
not introduce asynchronous Lazy/Provider wrappers.

## Migration and Current Boundaries

`owner.container` is a distinct generated dependency view, not the original
container type. Its concrete dependency getters are available, but original
custom methods, protocol conformances, and key paths do not transfer. Migrate
consumers to their service dependencies or the explicit view type. Prefer
inferred owner/view types and contextual selections such as `.service`.

MainActor containers isolate the owned factory, view, and lifecycle methods.
Other containers retain the caller's executor for async APIs; owners and views
do not gain an unconditional `Sendable` conformance. Async factory captures and
payloads remain compiler-checked, including synchronous on-demand cells captured
by asynchronous factories.

Owned construction requires `validateDAG: true`. It supports inputs, synchronous and
asynchronous shared providers with eager/on-demand initialization, synchronous
transient providers, eligible synchronous Lazy/Provider edges, and plain shared
children. It explicitly diagnoses async transient providers, assisted
inputs/factories, collection/multibinding providers, transient children,
feature-root helpers, custom global actors, and
per-member actor isolation outside a MainActor container.
Unknown custom-actor attribute spellings may fail in generated-code compiler
diagnostics rather than an InnoDI-specific diagnostic; custom actors are not
supported by this candidate. Use the existing container API for unsupported shapes. See
<doc:DiagnosticsGuide> and <doc:AsyncPreparation>.

Self inside an input type keeps its original container identity through a
compiler-bound outer witness, including nested containers and function types.
Factory expressions keep their original lexical Self. A shared property's
`Self.Value` spelling still encounters the pre-existing legacy `Overrides`
limitation; use its nested `Value` name for that case. Effectively generic
containers remain unsupported.
