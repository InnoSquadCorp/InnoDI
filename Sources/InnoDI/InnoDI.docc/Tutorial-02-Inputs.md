# Tutorial 2 — External inputs

Add a configuration value that the container does not own. `@Input` members
are passed in at initialization time and are read-only thereafter.

## Goal

A container that takes a runtime configuration value and uses it to build a
greeter that adapts its message.

## Code

<!-- innodi:compile -->
```swift
import InnoDI

struct AppConfig {
    let audience: String
}

struct Greeter {
    let audience: String
    func hello() -> String { "Hello, \(audience)" }
}

@DIContainer
struct AppContainer {
    @Input
    var config: AppConfig

    @Provide(.shared, factory: { (config: AppConfig) in
        Greeter(audience: config.audience)
    })
    var greeter: Greeter
}

let container = AppContainer(config: AppConfig(audience: "world"))
print(container.greeter.hello())
```

## What changed

* `@Input` adds `config: AppConfig` to the synthesized
  initializer. The macro infers the parameter from the property type and
  emits `init(config: AppConfig)`.
* The factory closure now takes `config` as a parameter. The macro reads
  the closure parameter list, matches `config` to the same-named container
  member, and wires it automatically.
* Reading `container.greeter` walks the cached `.shared` slot — the factory
  runs at most once even if you call the property many times.

## Try it

* Rename the factory parameter from `config` to `cfg` and observe the
  `provide.unresolved-factory-parameter` diagnostic. Name resolution is
  strict on purpose.
* Add a second `@Input` and confirm the synthesized initializer expects
  both arguments.

## Next

- <doc:Tutorial-03-Wiring>
