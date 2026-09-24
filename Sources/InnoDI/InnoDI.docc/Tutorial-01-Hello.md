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
    @Provide(.shared, factory: { Greeter() })
    var greeter: Greeter
}

let container = AppContainer()
print(container.greeter.hello())
```

## What the macro does

* `@DIContainer` synthesizes `init()`, a nested `Overrides` builder, and four
  `withOverrides` helpers. With no `@Input` members, the primary initializer
  takes no arguments.
* `@Provide(.shared, factory:)` declares a member built once per container
  instance from the supplied closure. The instance is cached and reused on
  every read.
* The declared property type is `Greeter`, so generated storage and overrides
  use that concrete nominal type. Declaring an `any Protocol` existential
  instead would produce existential storage.

## Try it

* Add a second `@Provide(.shared, factory: { Greeter() })`
  with a different name and confirm the second member is cached
  independently.

## Next

- <doc:Tutorial-02-Inputs>
