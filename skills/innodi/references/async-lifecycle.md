# Async lifetime in 7.0.0

Choose lifetime based on who starts, awaits, retries, and ends the work. Keep plain containers when their existing contract fits; owned construction is opt-in.

| Situation | API / consequence |
|---|---|
| Plain eager shared async provider | Starts at container initialization. Cancelling a reader does not cancel shared construction; the plain initializer supplies no owned shutdown lifecycle |
| Plain on-demand shared async provider | Starts on first read, accessor is `async throws`; the owning feature calls `closeAsyncProviders()` when done |
| Short prepared operation | Set `generateOwned: true`, then `try await Services.withPrepared(.service, input: ...) { view in ... }`; it closes on success or error |
| Long-lived feature with loading/retry UI | Keep `try await Services.makeOwned(...)`; call `try await owner.requireReady(.service)` before ready-dependent behavior and `await owner.close()` at the feature boundary |
| Detailed preparation UI | `try await owner.prepare(.service)` returns a report; check `isReady` and entries. A returned report alone is not success |
| Explicit retry after failure/cancellation | `retryAndRequireReady(.service)` performs one retry transaction and checks readiness; it is not refresh or an automatic retry loop |
| Several value overrides | `makeOwnedWithOverrides(...) { overrides in ... }`; preflight runs before live construction and may throw |

`makeOwned` finishes setup and admits eager providers; it does not wait for ready results. On-demand providers start by read or preparation. Every owned async read is throwing, even when the authored factory is nonthrowing. An async value override seeds a ready scope and skips its factory. Independent eager providers retain their start policy.

## Cancellation and shutdown

- Reader/preparation cancellation ends that wait. It does not imply provider cancellation or require retry if the provider is still running.
- `owner.cancel(.service)` affects a selected scope only if it is running at its cancellation point. It is not an atomic graph-wide cancel and does not cancel dependencies automatically.
- Provider failure/cancellation and reader cancellation are different states. Explicit retry follows the selected dependency plan; a stale result cannot replace the new generation.
- `close()` closes admission and async scopes; repeated/concurrent closes are safe. Later async reads, including cached reads, throw `DIAsyncScopeError.closed`. A read already admitted can win a scope-local race.
- Close does not wait for cancellation-ignoring user factories to finish, invoke service `shutdown()`, or stop arbitrary application tasks. Own those resources separately if the application requires it.
- Sync dependencies, borrowed inputs, plain children, and objects already returned are not revoked. Owner/view copies share scopes; independent `makeOwned` calls do not.

For manual owners, close in both the success and error paths; an unawaited task in `defer` is not awaited cleanup. Prefer `withPrepared` for a bounded operation. It checks entry cancellation before overrides/live work, checks cancellation after preparation, preserves an operation-thrown error, and closes before returning/throwing. A successful operation whose caller was cancelled receives cancellation after close. It cannot finish an operation that ignores cancellation and never returns.

## Shape boundaries

The generated owned view is a distinct type. The original container's methods, protocol conformances, and key paths do not transfer. Prefer passing the actual service dependencies and inferred owner/view types. The exact guide documents generated types when stored/public signatures require them.

Owned construction requires DAG validation. It supports synchronous shared/transient, async shared, eligible synchronous `Lazy`/`Provider` edges, and plain shared children. It rejects async transient, assisted providers, collections/multibinding, transient children, feature-root helpers, and custom global actors. Do not enable it indiscriminately on an existing advanced container. No unconditional `Sendable` conformance is added; preserve compiler-checked isolation.

The [consumer tests](../assets/consumer/Tests/InnoDISkillExampleTests/ConsumerTests.swift) demonstrate readiness, retry, cancellation, close, overrides, and preflight failure with deterministic actors. They do not test every lifecycle race or all supported shapes.

Source: exact [OwnedContainers contract](https://github.com/InnoSquadCorp/InnoDI/blob/4783eee7f674f99a337768c107b7a5f640810c2a/Sources/InnoDI/InnoDI.docc/OwnedContainers.md). Its introductory candidate-status text is stale relative to the published [7.0.0 release](https://github.com/InnoSquadCorp/InnoDI/releases/tag/7.0.0); the support baseline is that release's revision.
