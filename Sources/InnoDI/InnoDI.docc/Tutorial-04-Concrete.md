# Tutorial 4 — Concrete vs protocol storage

`@Provide` defaults its storage to a protocol existential when the
declared property type is a protocol. Choosing concrete storage is an
explicit decision; this tutorial explains why the macro insists on the
opt-in.

## Goal

Compare the same dependency expressed in two ways: a protocol existential
versus a concrete struct, and use `concrete: true` to opt into the
concrete form when needed.

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
    @Provide(.input)
    var audience: String

    // Default: storage is the protocol existential `any GreeterProtocol`.
    @Provide(.shared, factory: { (audience: String) in
        LoudGreeter(audience: audience)
    })
    var greeter: any GreeterProtocol

    // Concrete storage of the struct keeps the static type for callers
    // that need methods or stored properties not part of the protocol.
    @Provide(.shared, factory: { (audience: String) in
        LoudGreeter(audience: audience)
    }, concrete: true)
    var loudGreeter: LoudGreeter
}

let container = AppContainer(audience: "world")
print(container.greeter.hello())
print(container.loudGreeter.audience)
```

## Why the opt-in exists

The macro could autodetect concrete storage by looking at the property
type, but that decision affects more than codegen — it changes the
caller-visible API:

* Protocol storage hides the implementation type. Tests and previews can
  swap in a different conforming type via `Overrides` without rebuilding
  the surrounding container.
* Concrete storage exposes implementation-specific properties and method
  signatures. Callers can reach for `LoudGreeter.audience` directly, but
  swapping in another implementation now requires a wider override path.

Forcing `concrete: true` makes the trade-off visible in code review
instead of hiding it inside the macro's heuristics.

## Try it

* Drop `concrete: true` on `loudGreeter` and read the
  `provide.concrete-opt-in-required` diagnostic.
* Override `greeter` with a different `GreeterProtocol` conformer in a
  test (`overrides.greeter = QuietGreeter()`). Confirm the override
  compiles because the slot type is the protocol.
* Try the same trick on `loudGreeter`. The override slot is the concrete
  `LoudGreeter`, so swapping a different conformer is a compile error.

## Next

- <doc:Tutorial-05-SubContainer>
