# InnoDI Project Context

## Project Overview

**InnoDI** is a Swift dependency injection framework that leverages Swift Macros for compile-time code generation and a CLI tool for static analysis validation. It aims to provide type-safe, boilerplate-free dependency injection with verification of container completeness and reachability.

## Architecture

The project is organized into a layered architecture with four primary modules:

1.  **`InnoDI` (Public API)**
    *   Contains the `@DIContainer` and `@Provide` macro declarations.
    *   Defines the `DIScope` enum (`.shared`, `.input`, `.transient`).
    *   This is the library imported by consumers.

2.  **`InnoDIMacros` (Macro Implementation)**
    *   Implements the code generation logic.
    *   `DIContainerMacro`: Generates the initializer and validates `@Provide` contracts.
    *   `ProvideMacro`: Helper macro for property attribution.
    *   Depends on `InnoDICore`.

3.  **`InnoDICore` (Shared Parsing)**
    *   Centralizes parsing logic for attributes to ensure consistency between the Macros and the CLI.
    *   Handles parsing of `@Provide` arguments and `@DIContainer` flags.

4.  **`InnoDI-DependencyGraph` (Dependency Graph Visualization)**
    *   Executable tool that generates dependency graphs from DI usage across a project.
    *   Analyzes container relationships and outputs visual graphs.
    *   Supports multiple formats (Mermaid, DOT, ASCII, PNG).

## Key Concepts

### Macros
*   **`@DIContainer(validate: Bool, root: Bool)`**: Applied to a class/struct to make it a DI container.
    *   Generates an `init` method.
    *   `validate: false` relaxes compile-time scope/factory checks and emits runtime fallback traps for invalid shared factories.
*   **`@Provide(scope, factory)`**: Applied to properties within a container.
    *   **`.shared`**: Singleton-like within the container. Requires a `factory` closure.
    *   **`.input`**: Dependency passed in from the parent/caller. Must *not* have a factory.
    *   **`.transient`**: New instance created on every access. Requires a `factory` closure.
    *   Concrete types require explicit `concrete: true` opt-in.

### CLI Graph Generation
The CLI performs static analysis to generate dependency graphs:
*   Analyzes container relationships and initialization patterns.
*   Outputs visual graphs in multiple formats (Mermaid, DOT, ASCII, PNG).

## Building and Running

### Build
```bash
swift build                            # Build all targets
swift build --target InnoDI            # Build library only
swift build --target InnoDI-DependencyGraph # Build CLI tool only
```

### Test
```bash
swift test                     # Run all tests
```

### Run CLI
```bash
# Generate dependency graph from a project
swift run InnoDI-DependencyGraph --root /path/to/project
```

## Development Conventions

*   **Parsing Logic**: All parsing of attribute arguments MUST reside in `InnoDICore` to be shared between the compiler plugin (Macros) and the CLI.
*   **Syntax Generation**: Use `SwiftSyntaxBuilder` for generating AST nodes in macros, avoiding string-based code generation where possible.
*   **Access Control**: Generated code (initializers, structs) must strictly respect the access level of the container type.
*   **Testing**: Maintain tests for both the core parsing logic (`InnoDICoreTests`) and the macro expansions (`InnoDIMacrosTests`).
