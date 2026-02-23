# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

InnoDI is a Swift dependency injection framework implemented using Swift macros. It provides compile-time DI container generation with a CLI dependency graph visualizer.

## Build and Test Commands

### Building
```bash
swift build                                    # Build all targets
swift build --target InnoDI                    # Build library only
swift build --target InnoDI-DependencyGraph    # Build CLI tool only
swift build --target InnoDIMacros              # Build macros only
```

### Testing
```bash
swift test                                     # Run all tests
swift test --filter InnoDICoreTests            # Run core parsing/graph tests
swift test --filter InnoDIMacrosTests          # Run macro expansion tests
```

### Running the CLI
```bash
swift run InnoDI-DependencyGraph --root /path/to/project   # Generate dependency graph from DI containers
```

## Architecture

### Module Structure

The project uses a layered architecture with four main modules:

1. **InnoDI** (Public API)
   - Exports the `@DIContainer` and `@Provide` macro declarations
   - Defines `DIScope` enum (`.shared`, `.input`, `.transient`)
   - This is what library consumers import

2. **InnoDIMacros** (Macro Implementation)
   - `DIContainerMacro`: Member macro that generates an `init` and validates `@Provide` usage
   - `ProvideMacro`: Accessor macro that emits storage/accessor code per scope
   - `SimpleDiagnostic`: Custom diagnostic messages for macro errors
   - Depends on `InnoDICore` for shared parsing logic

3. **InnoDICore** (Shared Parsing)
   - Contains parsing utilities used by both macros and CLI
   - `parseProvideArguments()`: Extracts scope and factory from `@Provide` attributes
   - `parseDIContainerAttribute()`: Extracts validate/root flags from `@DIContainer`
   - `DependencyGraphCore`: Shared graph normalization/deduplication helpers for CLI
   - `findAttribute()`: Helper for locating attributes in syntax trees
   - This module prevents parsing logic duplication

4. **InnoDI-DependencyGraph** (Dependency Graph Visualization)
   - Generates dependency graphs from DI container usage across a codebase
   - Analyzes container relationships and generates visual graphs
   - Supports multiple output formats (Mermaid, DOT, ASCII, PNG)
   - Uses SwiftSyntax for parsing DI annotations

### How the Macros Work

**@DIContainer** generates:
- An `init` with parameters for:
  - `.input` scoped properties (required parameters)
  - `.shared` and `.transient` scoped properties (optional override parameters)
- No separate `Overrides` struct is generated in the current architecture
- The init body:
  1. Assigns all `.input` properties to generated storage
  2. Resolves `.shared` properties with `override ?? factory`
  3. Stores `.transient` overrides for accessor-time usage

**@Provide** scope semantics:
- `.shared`: Singleton-like dependencies created by factory in init (requires `factory:` parameter)
- `.input`: Dependencies passed as init parameters (must not have `factory:`)
- `.transient`: New instance created on every access (requires `factory:` parameter)
- Protocol-typed dependencies for `.shared`/`.transient` should use explicit existential syntax (`any Protocol`)
- Concrete dependency types require `concrete: true` opt-in (enforced even when `validate: false`)

### Dependency Graph Generation Flow (CLI)

1. **Container Discovery**: `ContainerCollector` walks all Swift files to find `@DIContainer` types and extract their required `.input` properties and relationships
2. **Usage Analysis**: `ContainerUsageCollector` finds all container initialization calls and records:
   - Which labels were passed (for dependency mapping)
   - Container-to-container edges (for graph visualization)
3. **Graph Generation**:
   - Builds dependency graph from container relationships
   - Outputs in specified format (Mermaid, DOT, ASCII, or PNG via Graphviz)

## Key Design Patterns

### Centralized Parsing
All attribute parsing logic lives in `InnoDICore` to ensure macros and CLI interpret `@Provide` and `@DIContainer` identically. When adding new macro parameters, update both the parsing functions and the macro expansion logic.

### SwiftSyntaxBuilder Usage
Macros prefer `SwiftSyntaxBuilder` APIs over string concatenation for AST generation. This provides type safety and correct formatting. See `makeInitDecl()` for examples.

### Access Level Propagation
The generated `init` inherits the access level of the container type (public, internal, fileprivate, private) via `containerAccessLevel()`.

## Common Development Tasks

When modifying macro behavior:
1. Update parsing logic in `InnoDICore/Parsing.swift` first
2. Update macro expansion in `InnoDIMacros/DIContainerMacro.swift`
3. Add test cases to `Tests/InnoDIMacrosTests/`
4. Consider CLI implications in `Sources/InnoDI-DependencyGraph/` modules (`Collectors`, `Rendering`, `Output`, `CLI`)

When adding diagnostics:
- Use `SimpleDiagnostic` for error messages
- Attach diagnostics to the relevant syntax node for precise error location
- Follow existing patterns: `context.diagnose(Diagnostic(node:message:))`
