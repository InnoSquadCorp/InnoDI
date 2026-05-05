# Tutorial 1 — Hello, container

Build the smallest InnoDI container that compiles, runs, and exposes a single
`.shared` member. Each follow-up tutorial layers one new concept on top.

## Goal

A container that owns a single dependency built from a factory closure, with
no other moving parts.

## Code

<!-- innodi:compile -->
```swift
import InnoDI

struct Greeter {
    func hello() -> String { "Hello, world" }
}

@DIContainer
struct AppContainer {
    @Provide(.shared, factory: { Greeter() }, concrete: true)
    var greeter: Greeter
}

let container = AppContainer()
print(container.greeter.hello())
```

## What the macro does

* `@DIContainer` synthesizes `init()`, a nested `Overrides` builder, and four
  `withOverrides` helpers. With no `.input` members, the primary initializer
  takes no arguments.
* `@Provide(.shared, factory:)` declares a member built once per container
  instance from the supplied closure. The instance is cached and reused on
  every read.
* `concrete: true` is required because the storage type is a concrete
  `Greeter`, not a protocol existential. The macro wants the choice to be
  explicit rather than implied.

## Try it

* Remove `concrete: true` and read the diagnostic. The macro asks you to
  opt in because the stored type is not a protocol.
* Add a second `@Provide(.shared, factory: { Greeter() }, concrete: true)`
  with a different name and confirm the second member is cached
  independently.

## Next

- <doc:Tutorial-02-Inputs>
