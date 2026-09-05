# Tutorial 4 — Concrete vs protocol storage

`@Provide` uses the declared property type as the source of truth for generated
storage and overrides. A concrete nominal type produces concrete storage;
`any Protocol` produces existential storage.

## Goal

Compare the same dependency expressed in two ways: a protocol existential
versus a concrete struct, and see how that declaration shapes the caller API.

## Code

<!-- innodi:compile -->
```swift
import InnoDI

protocol GreeterProtocol {
    func hello() -> String
}

struct LoudGreeter: GreeterProtocol {
    let audience: String
    func hello() -> String { "HELLO, \(audience.uppercased())" }
}

@DIContainer
struct AppContainer {
    @Input
    var audience: String

    // The declared type selects existential `any GreeterProtocol` storage.
    @Provide(.shared, factory: { (audience: String) in
        LoudGreeter(audience: audience)
    })
    var greeter: any GreeterProtocol

    // Concrete storage of the struct keeps the static type for callers
    // that need methods or stored properties not part of the protocol.
    @Provide(.shared, factory: { (audience: String) in
        LoudGreeter(audience: audience)
    })
    var loudGreeter: LoudGreeter
}

let container = AppContainer(audience: "world")
print(container.greeter.hello())
print(container.loudGreeter.audience)
```

## Why the declared type is the source of truth

Storage shape affects more than code generation — it changes the caller-visible
API:

* Protocol storage hides the implementation type. Tests and previews can
  swap in a different conforming type via `Overrides` without rebuilding
  the surrounding container.
* Concrete storage exposes implementation-specific properties and method
  signatures. Callers can reach for `LoudGreeter.audience` directly, but
  swapping in another implementation now requires a wider override path.

The property declaration already exposes that trade-off in code review. InnoDI
does not select storage with an attribute flag or a macro heuristic. A factory
may return a concrete value for an existential property, but the declared
property type still determines the generated storage and override slot.

## Try it

* Override `greeter` with a different `GreeterProtocol` conformer in a
  test (`overrides.greeter = QuietGreeter()`). Confirm the override
  compiles because the slot type is the protocol.
* Try the same trick on `loudGreeter`. The override slot is the concrete
  `LoudGreeter`, so swapping a different conformer is a compile error.
* Change `loudGreeter`'s declared type to `any GreeterProtocol`. Confirm that
  its override slot now accepts any conformer and that callers can no longer
  access `audience` through the existential API.

## Next

- <doc:Tutorial-05-SubContainer>
