# InnoDI Examples

This folder contains runnable examples for the current 5.0 development train,
including mandatory target-scoped DAG validation and SwiftUI helpers. Public
installation snippets remain pinned to the latest stable 4.3.0 release until
5.0.0 is published.

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
