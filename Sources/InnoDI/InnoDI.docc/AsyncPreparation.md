# Owned Asynchronous Preparation

Use ``DIAsyncScope`` when asynchronous construction needs an explicit owner,
observable status, cancellation, and retry. A scope coalesces concurrent
waiters into one operation. Cancelling a waiter cancels only that wait;
calling ``DIAsyncScope/close()`` cancels the owned operation, resumes all
waiters, and permanently prevents new work.

```swift
let profile = DIAsyncScope(providerID: "App.profile") {
    try await loadProfile()
}

let status = await profile.prepare()
guard status.state == .ready else { return }
```

``DIAsyncPreparationPlan`` validates an explicit provider dependency graph
and prepares only a requested provider plus its transitive dependencies. If a
dependency fails, downstream nodes stay idle and appear as `blocked` with the
provider IDs that blocked them. Unrelated providers do not start.

```swift
let plan = try DIAsyncPreparationPlan(nodes: [
    DIAsyncPreparationNode(provider: session),
    DIAsyncPreparationNode(
        provider: profile,
        dependencies: ["App.session"]
    ),
])
let report = try await plan.prepare(["App.profile"])
```

Use ``DIAsyncPreparationPlan/retry(_:)`` after a selected preparation reports
`failed` or `cancelled`. The plan advances the failed provider and its selected
downstream dependants together, while preserving ready parent dependencies.
It rejects a retry before changing anything when an affected provider is still
running or has been closed. Call ``DIAsyncScope/retry()`` directly only after
that individual scope fails or its owned operation is cancelled.

A task that is already cancelled does not start a factory. Cancelling one
waiter or preparation request reports `cancelled` for that request without
cancelling shared owner work. An owned operation that throws
`CancellationError` moves the scope to `cancelled` and can be retried. Each
retry advances to a clean generation; previously returned child values are not
mixed into the replacement subgraph.

InnoDI owns only the task created from the supplied operation. Tasks created
internally by an application service remain that service's responsibility, and
cancellation remains cooperative.

The status report records only a provider ID, generation, state, and reflected
error *type*. Direct waiters still receive the original application error, but
the report never serializes error values, input values, tokens, or other
application payloads. Cancellation is reported without an error payload.
