# InnoDI Project Context

## Project Overview

**InnoDI** is a Swift dependency injection framework that leverages Swift Macros for compile-time code generation and a CLI tool for static analysis validation. It aims to provide type-safe, boilerplate-free dependency injection with verification of container completeness and reachability.

## Architecture

The project is organized into a layered architecture with four primary modules:

1.  **`InnoDI` (Public API)**
    *   Contains the `@DIContainer` and `@Provide` macro declarations.
    *   Defines the `DIScope` enum (`.shared`, `.input`).
    *   This is the library imported by consumers.

2.  **`InnoDIMacros` (Macro Implementation)**
    *   Implements the code generation logic.
    *   `DIContainerMacro`: Generates the initializer and `Overrides` struct.
    *   `ProvideMacro`: Helper macro for property attribution.
    *   Depends on `InnoDICore`.

3.  **`InnoDICore` (Shared Parsing)**
    *   Centralizes parsing logic for attributes to ensure consistency between the Macros and the CLI.
    *   Handles parsing of `@Provide` arguments and `@DIContainer` flags.

4.  **`InnoDICLI` (Static Analysis)**
    *   Executable tool that validates DI usage across a project.
    *   Checks for missing `.input` dependencies in container initializations.
    *   Verifies that all containers are reachable from "root" containers.

## Key Concepts

### Macros
*   **`@DIContainer(validate: Bool, root: Bool)`**: Applied to a class/struct to make it a DI container.
    *   Generates an `init` method.
    *   Generates an `Overrides` struct for testing/mocking `.shared` dependencies.
*   **`@Provide(scope, factory)`**: Applied to properties within a container.
    *   **`.shared`**: Singleton-like within the container. Requires a `factory` closure.
    *   **`.input`**: Dependency passed in from the parent/caller. Must *not* have a factory.

### CLI Validation
The CLI performs static analysis to ensure:
*   All `.input` dependencies are satisfied when a container is initialized.
*   All containers are part of a valid dependency graph rooted at containers marked `root: true`.

## Building and Running

### Build
```bash
swift build                    # Build all targets
swift build --target InnoDI    # Build library only
swift build --target InnoDICLI # Build CLI tool only
```

### Test
```bash
swift test                     # Run all tests
```

### Run CLI
```bash
# Validate a project at a specific path
swift run InnoDICLI --root /path/to/project
```

## Development Conventions

*   **Parsing Logic**: All parsing of attribute arguments MUST reside in `InnoDICore` to be shared between the compiler plugin (Macros) and the CLI.
*   **Syntax Generation**: Use `SwiftSyntaxBuilder` for generating AST nodes in macros, avoiding string-based code generation where possible.
*   **Access Control**: Generated code (initializers, structs) must strictly respect the access level of the container type.
*   **Testing**: Maintain tests for both the core parsing logic (`InnoDICoreTests`) and the macro expansions (`InnoDIMacrosTests`).
