# Runtime Tracing

Correlate opt-in runtime provider activity with the static schema-v6 graph.

## Enable generated tracing

Create a bounded sink and map each runtime module name to the target ID emitted
by `InnoDI-DependencyGraph`:

```swift
let buffer = DIBoundedTraceBuffer(capacity: 4_096)
let trace = DITraceContext(
    sink: buffer,
    targetIDsByModule: ["App": "App"],
    generation: 3
)

let container = AppContainer(config: config, _innoDITrace: trace)
```

The generated eager, on-demand, transient, async, component, sub-container,
and override paths forward the context. With a target mapping, an event ID has
the same `target::Container.member` shape as the graph. Without a mapping,
InnoDI uses the reflected module-qualified container path and does not claim an
exact graph match.

## Interpret events

`ownerID` identifies one generated container instance. `generation` identifies
an application-selected rebuild generation. A provider resolution's
`instanceID` joins `start` to `success`, `failure`, or `cancel`; cache hits and
overrides carry an explicit `origin`. `waitStart` and `waitEnd` include the
provider and instance being awaited.

Events contain metadata only. There are no input values, resolved results,
tokens, serialized errors, or service descriptions. InnoDI observes generated
provider boundaries, not tasks or work that a service starts internally.

``DITraceContext/disabled`` is the default. On that path generated owners do
not allocate their state or UUID, and no event or buffer is created. Use
`DITraceContext.withResolution(providerID:_:)` only for manual boundaries
outside generated containers.
