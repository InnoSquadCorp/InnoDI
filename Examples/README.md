# InnoDI Examples

This folder contains runnable examples that match the current 4.x feature set,
including the 4.1.0 release-hardening validation and SwiftUI helpers.

## Core Macro Usage

Reference source:

- [Sources/InnoDIExamples/main.swift](../Sources/InnoDIExamples/main.swift)

## Dependency Graph CLI Sample

Runnable sample files:

- `Examples/SampleApp/AppContainer.swift`
- `Examples/SampleApp/App.swift`

Commands:

```bash
swift run InnoDI-DependencyGraph --root Examples/SampleApp
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
- `@DIFeatureRoot` emits both default and named SwiftUI feature-root helpers for a shared `@SubContainer`.
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
swift run InnoDI-DependencyGraph --root /path/to/your/project
swift run InnoDI-DependencyGraph --root /path/to/your/project --format dot --output graph.dot
swift run InnoDI-DependencyGraph --root /path/to/your/project --format ascii
swift run InnoDI-DependencyGraph --root /path/to/your/project --format dot --output graph.png
```
