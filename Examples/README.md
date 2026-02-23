## InnoDI Examples

This folder contains runnable examples for real integration scenarios.

### 1) Core DI Macro Usage

Reference source:
- `Sources/InnoDIExamples/main.swift`

### 2) Dependency Graph CLI Sample

Runnable sample files:
- `Examples/SampleApp/AppContainer.swift`
- `Examples/SampleApp/App.swift`

Run:

```bash
swift run InnoDI-DependencyGraph --root Examples/SampleApp
```

Validate DAG (fails on cycle / ambiguous container reference):

```bash
swift run InnoDI-DependencyGraph --root Examples/SampleApp --validate-dag
```

### 3) SwiftUI Injection Example

Path:
- `Examples/SwiftUIExample`

Build:

```bash
cd Examples/SwiftUIExample
swift build
```

Highlights:
- `@DIContainer` for SwiftUI view model wiring
- Init override with mock service injection

### 4) TCA Integration Example

Path:
- `Examples/TCAIntegrationExample`

Build:

```bash
cd Examples/TCAIntegrationExample
swift build
```

Highlights:
- TCA reducer receives dependencies via InnoDI container
- Test double override via generated `init` parameters

### 5) Preview Injection Example

Path:
- `Examples/PreviewInjectionExample`

Build:

```bash
cd Examples/PreviewInjectionExample
swift build
```

Highlights:
- `#Preview` with lightweight preview-only container input
- Preview and live dependencies separated by injection

### 6) Existing CLI Output Formats

```bash
# Mermaid diagram (default)
swift run InnoDI-DependencyGraph --root /path/to/your/project

# DOT format
swift run InnoDI-DependencyGraph --root /path/to/your/project --format dot --output graph.dot

# ASCII format
swift run InnoDI-DependencyGraph --root /path/to/your/project --format ascii

# PNG image (requires Graphviz)
swift run InnoDI-DependencyGraph --root /path/to/your/project --format dot --output graph.png
```
