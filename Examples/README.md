# InnoDI Examples

This folder contains runnable examples for the `main` branch, including
mandatory target-scoped DAG validation and SwiftUI helpers. Each example
depends on the repository checkout through a local package path, so it always
builds against the current sources. Public installation snippets in the
[README](../README.md) pin the latest published release.

## Core Macro Usage

Reference source:

- [Sources/InnoDIExamples/main.swift](../Sources/InnoDIExamples/main.swift)

## Dependency Graph CLI Sample

Runnable sample:

- [Examples/SampleApp](SampleApp)

Commands:

```bash
cd Examples/SampleApp
swift build
swift test
swift run SampleApp
```

Graph commands from the repository root:

```bash
swift run InnoDI-DependencyGraph --root Examples/SampleApp --root-pruning all
swift run InnoDI-DependencyGraph --root Examples/SampleApp --validate-dag
```

The [owned lifecycle example](SampleApp/OwnedLifecycleExample.swift) also runs
as part of `SampleApp` and its tests. It demonstrates typed synchronous
`prewarm`, a deliberately failed async preparation, explicit retry/readiness,
and `close()` on success or error. It uses local values only, with no network
request or external account.

## SwiftUI Example

Path:

- [Examples/SwiftUIExample](SwiftUIExample)

Commands:

```bash
cd Examples/SwiftUIExample
swift build
swift test
```

Highlights:

- `.innodi(container)` applies the generated environment bridge at the feature root.
- `@SubContainer(..., featureRoot:)` and `featureRoots:` emit default and named
  SwiftUI feature-root helpers.
- init overrides and the `Overrides` builder keep live and test roots on the same container contract.

## Preview Injection Example

Path:

- [Examples/PreviewInjectionExample](PreviewInjectionExample)

Commands:

```bash
cd Examples/PreviewInjectionExample
swift build
swift test
```

Highlights:

- `#Preview` reuses the generated SwiftUI environment bridge instead of repeating `.environment` glue.
- preview matrices are built with the same container, override, and feature-root APIs used by live code.

## CLI Output Formats

```bash
swift run InnoDI-DependencyGraph --root /path/to/your/project --root-pruning all
swift run InnoDI-DependencyGraph --root /path/to/your/project --root-pruning all --format dot --output graph.dot
swift run InnoDI-DependencyGraph --root /path/to/your/project --root-pruning all --format ascii
swift run InnoDI-DependencyGraph --root /path/to/your/project --root-pruning all --format dot --output graph.png
```
