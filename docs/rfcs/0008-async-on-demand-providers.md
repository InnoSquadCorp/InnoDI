# RFC 0008 — Asynchronous on-demand providers

- **Status**: Draft (implemented on the 7.0.0 train branch; awaiting
  maintainer acceptance)
- **Authors**: InnoDI maintainers
- **Created**: 2026-09-29
- **Last updated**: 2026-09-29
- **Target release**: 7.0.0
- **Tracking plan**: [7.0.0 post-audit plan](../plans/7.0.0-post-audit.md), item R1

## Summary

Allow `@Provide(.shared, initialization: .onDemand, asyncFactory:)`. The
provider constructs its value on the first read instead of in the container
initializer, coalesces concurrent readers into one construction, and gives
the owner an explicit way to cancel and release that work. Eager
asynchronous `.shared` providers keep their current behavior.

## Problem

InnoDI 6.0 rejects `.onDemand` together with `asyncFactory:`
(`provide.ondemand-async-unsupported`). The only asynchronous `.shared`
lifetime is eager: the generated initializer starts an unstructured task
before any read, and nothing cancels it. The 2026-09-29 audit pinned three
consequences with runtime tests:

- construction starts even when no code ever reads the provider;
- neither a cancelled reader nor releasing the container cancels work that
  has started;
- every read of a `.transient` `@SubContainer` builds a new child, so every
  read starts that child's eager asynchronous work again.

A feature whose child container owns network or storage setup therefore pays
for that setup on every transient read and cannot stop it when the feature
closes. `DIAsyncScope` already models owned asynchronous work with waiter
cancellation and explicit close, but containers cannot use it as provider
storage.

## Proposal

### Declaration

```swift
@Provide(.shared, initialization: .onDemand, asyncFactory: { (client: APIClient) async throws in
    try await Session.open(client: client)
})
var session: Session
```

The value type must be `Sendable`. The factory closure captures its
dependencies and runs on the provider's owned task, so every captured
dependency value must also be `Sendable`. The compiler checks both through
the generated `@Sendable` operation. In a `mainActor: true` container the
operation is main-actor isolated instead: the factory runs on the main actor,
as an eager factory does there, and its captures follow main-actor rules.

### Access

The generated accessor is `get async throws`, even when the factory does not
throw, because a read can observe cancellation of the reader or closure of the
provider:

```swift
let session = try await container.session
```

The first read starts construction. Concurrent reads wait for the same
construction. Cancelling a reader cancels only that reader's wait; the owned
construction continues for the other readers. A value or a failure is cached
for the lifetime of the provider, which matches eager asynchronous providers.

An eager asynchronous consumer still starts in the initializer, so it
constructs every on-demand provider it depends on at that time. Reading the
accessor of a non-`Sendable` container from another isolation domain has the
same limits as an eager asynchronous accessor.

### Close

A container with at least one asynchronous on-demand provider gains:

```swift
func closeAsyncProviders() async
```

Closing cancels in-flight construction, resumes every waiting reader with
`DIAsyncScopeError.closed`, and releases the value and the factory's
captures. A construction task that has not begun never starts the factory; a
factory that is already running observes cooperative cancellation, and a value
it returns anyway is discarded and traced as a cancellation. Later reads
throw `DIAsyncScopeError.closed`. The error's provider ID is the member name.
Closing is idempotent. Container copies
share the same provider storage, so closing any copy closes it for all copies,
as with synchronous on-demand providers. A container declared with
`mainActor: true` isolates the method to the main actor; other containers
emit it as `nonisolated(nonsending)`.

Sub-containers are not closed transitively. A `.shared` child exposes its own
`closeAsyncProviders()` when it declares such providers, and a `.transient`
child is a fresh value on every read.

### Overrides

The generated `Overrides` slot keeps the declared type. An override value
completes the provider immediately, and the factory never runs. Closing still
closes an overridden provider and releases its value, so later reads throw
`DIAsyncScopeError.closed`. A test that overrides the provider therefore
observes the same close contract as production.

### Effects and edges

An asynchronous on-demand provider always has the `async throws` consumer
effect, independent of whether its factory throws:

| Provider | sync consumer | `async` consumer | `async throws` consumer |
|---|---:|---:|---:|
| `async` on-demand | rejected | rejected | allowed |
| `async throws` on-demand | rejected | rejected | allowed |

`Lazy`, `Provider`, `with:`, `@Multibinding`, and the synchronous `prewarm`
method keep rejecting asynchronous targets. Sub-container inputs had no
dedicated check in 6.0: wiring an asynchronous parent member failed inside the
generated child construction with an unrelated missing-member error. 7.0 adds
`sub.async-parent-member` for eager, on-demand, and transient asynchronous
parents. The graph records the provider with `initialization: onDemand` and
its declared factory effect, so the graph JSON schema does not change.

A declaration named `closeAsyncProviders` in a container that has such a
provider is rejected with `container.close-async-providers-name-conflict`,
like the existing `prewarm` reservation.

### Tracing

The owned construction emits `start` when it begins and then `success`,
`failure`, or `cancel`. A read that observes in-flight construction emits
`waitStart` and `waitEnd`, then `cacheHit` on success, like a waiter on a
synchronous on-demand cell. A read that arrives before the owned task reports
its start joins the construction without wait events. A read of a completed
value emits `cacheHit`. An override emits `start` and `override` when the
container is initialized.

## Runtime shape

A new compiler-support type, `_InnoDIAsyncSharedCell<Value: Sendable>`, wraps
one `DIAsyncScope<Value>` or an override value. It is `Sendable` because every
stored property is `Sendable`; no `@unchecked Sendable` is introduced. The
cell is documentation-hidden, like `_InnoDISharedCell`, and application code
must not construct it.

## Alternatives considered

- **Make the eager task cancellable.** A container value has no deinitializer,
  and copies share the task handle, so no copy can know it is the last owner.
  An explicit close call is required either way.
- **Expose `DIAsyncScope` directly as the property type.** Consumers would
  write `try await container.session.value()` and lose the typed override and
  graph identity of an ordinary provider.
- **Keep failures retryable.** `DIAsyncScope` supports retry, but a provider
  that silently retries on the next read would diverge from eager
  asynchronous providers and hide failures. Applications that need retry keep
  using an injected `DIAsyncScope` with `DIAsyncPreparationPlan`.

## Migration

None. The spelling was rejected before, so no existing source changes
meaning. `provide.ondemand-async-unsupported` is removed.

## Open questions

- Whether `closeAsyncProviders()` should also close `.shared` sub-containers.
  This draft keeps closing local; a transitive variant can follow without a
  breaking change.

## Acceptance criteria

- `@Provide(.shared, initialization: .onDemand, asyncFactory:)` compiles under
  strict concurrency with warnings as errors, for ordinary and `mainActor`
  containers.
- Runtime tests show no construction before the first read, one construction
  for concurrent readers, reader cancellation that leaves construction
  running, and `DIAsyncScopeError.closed` after `closeAsyncProviders()`.
- Reading a `.transient` sub-container one hundred times starts no
  construction until a provider is read.
- Macro snapshots, the effect-compatibility table, the DocC articles, and the
  public API baseline describe the new surface.
