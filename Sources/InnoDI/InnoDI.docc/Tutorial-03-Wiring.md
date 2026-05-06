# Tutorial 3 — Key-path wiring

Replace the factory closure with a key-path-driven `Type.self` form. The
generated wiring is identical, but the declaration becomes a one-liner that
participates in IDE rename refactors.

## Goal

A container that builds the same `Greeter` from `AppConfig` without writing
the factory closure manually.

## Code

<!-- innodi:compile -->
```swift
import InnoDI

struct AppConfig {
    let audience: String
}

struct Greeter {
    init(config: AppConfig) { self.audience = config.audience }
    let audience: String
    func hello() -> String { "Hello, \(audience)" }
}

@DIContainer
struct AppContainer {
    @Provide(.input)
    var config: AppConfig

    @Provide(.shared, Greeter.self, with: [\AppContainer.config], concrete: true)
    var greeter: Greeter
}

let container = AppContainer(config: AppConfig(audience: "world"))
print(container.greeter.hello())
```

## What changed

* The second positional argument to `@Provide` is the concrete storage
  type. The macro looks up `Greeter.init` and chooses the overload whose
  parameter labels match the wired members.
* `with: [\AppContainer.config]` lists the parent member key paths the
  macro should pass into the initializer. The macro walks each key path,
  uses the trailing component name (`config`) as the argument label, and
  emits `Greeter(config: self.config)`.
* `Greeter.init(config:)` consumes the resolved `AppConfig` and stashes
  the audience locally. Same-name wiring keeps the relationship visible at
  the declaration site instead of hiding it inside a closure.

## When to prefer the closure form

Key-path wiring assumes the initializer signature lines up with the
declared member names. Use the closure form whenever:

* Construction needs side effects (logging, registration, etc.).
* You want to derive the argument from the input rather than passing it
  through (`Greeter(audience: config.audience.uppercased())`).
* The initializer is throwing or async (use `factory:` or `asyncFactory:`).

## Try it

* Drop the `with:` argument. The macro now uses *implicit* same-name
  wiring: it scans the container for a member named `config` whose type
  matches `Greeter.init`'s parameter. The resulting code is the same.
* Drop `concrete: true` and read the diagnostic. The opt-in is independent
  of which wiring form you chose.

## Next

- <doc:Tutorial-04-Concrete>
