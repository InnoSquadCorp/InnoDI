# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

InnoDI is a Swift dependency injection framework implemented using Swift macros. It provides compile-time DI container generation with static analysis validation via a CLI tool.

## Build and Test Commands

### Building
```bash
swift build                                    # Build all targets
swift build --target InnoDI                    # Build library only
swift build --target InnoDICLI                 # Build CLI tool only
swift build --target InnoDIMacros              # Build macros only
```

### Testing
```bash
swift test                                     # Run all tests
swift test --filter InnoDICoreTests            # Run core parsing tests
swift test --filter InnoDIMacrosTests          # Run macro expansion tests
```

### Running the CLI
```bash
swift run InnoDICLI --root /path/to/project   # Validate DI containers in a project
```

## Architecture

### Module Structure

The project uses a layered architecture with four main modules:

1. **InnoDI** (Public API)
   - Exports the `@DIContainer` and `@Provide` macro declarations
   - Defines `DIScope` enum (`.shared`, `.input`)
   - This is what library consumers import

2. **InnoDIMacros** (Macro Implementation)
   - `DIContainerMacro`: Member macro that generates an `init` and optional `Overrides` struct
   - `ProvideMacro`: Accessor macro (currently empty, used for syntax validation)
   - `SimpleDiagnostic`: Custom diagnostic messages for macro errors
   - Depends on `InnoDICore` for shared parsing logic

3. **InnoDICore** (Shared Parsing)
   - Contains parsing utilities used by both macros and CLI
   - `parseProvideArguments()`: Extracts scope and factory from `@Provide` attributes
   - `parseDIContainerAttribute()`: Extracts validate/root flags from `@DIContainer`
   - `findAttribute()`: Helper for locating attributes in syntax trees
   - This module prevents parsing logic duplication

4. **InnoDICLI** (Static Analysis)
   - Validates DI container usage across a codebase
   - Checks that container initializers receive all required `.input` dependencies
   - Verifies containers are reachable from root containers
   - Returns exit code 1 if validation fails

### How the Macros Work

**@DIContainer** generates:
- An `init` with parameters for:
  - `.input` scoped properties (required parameters)
  - `overrides: Overrides = .init()` (if any `.shared` properties exist)
- The init body:
  1. For `.shared` properties: `let prop = overrides.prop ?? factory()`
  2. Assigns all `.input` properties: `self.prop = prop`
  3. Assigns all `.shared` properties: `self.prop = prop`
- An `Overrides` struct (only if `.shared` properties exist):
  - Optional property for each `.shared` dependency
  - Empty `init()`

**@Provide** scope semantics:
- `.shared`: Singleton-like dependencies created by factory in init (requires `factory:` parameter)
- `.input`: Dependencies passed as init parameters (must not have `factory:`)

### Static Analysis Flow (CLI)

1. **Container Discovery**: `ContainerCollector` walks all Swift files to find `@DIContainer` types and extract their required `.input` properties
2. **Usage Analysis**: `ContainerUsageCollector` finds all container initialization calls and records:
   - Which labels were passed (for validation)
   - Container-to-container edges (for reachability analysis)
3. **Validation**:
   - Missing required inputs: Checks that all `.input` properties are passed as arguments
   - Unreachable containers: Performs graph traversal from root containers (explicit via `root: true` or implicit if no roots defined) to ensure all containers are reachable

## Key Design Patterns

### Centralized Parsing
All attribute parsing logic lives in `InnoDICore` to ensure macros and CLI interpret `@Provide` and `@DIContainer` identically. When adding new macro parameters, update both the parsing functions and the macro expansion logic.

### SwiftSyntaxBuilder Usage
Macros prefer `SwiftSyntaxBuilder` APIs over string concatenation for AST generation. This provides type safety and correct formatting. See `makeInitDecl()` and `makeOverridesStruct()` for examples.

### Access Level Propagation
The generated `init` and `Overrides` struct inherit the access level of the container type (public, internal, fileprivate, private) via `containerAccessLevel()`.

## Common Development Tasks

When modifying macro behavior:
1. Update parsing logic in `InnoDICore/Parsing.swift` first
2. Update macro expansion in `InnoDIMacros/DIContainerMacro.swift`
3. Add test cases to `Tests/InnoDIMacrosTests/`
4. Consider CLI implications in `InnoDICLI/main.swift`

When adding diagnostics:
- Use `SimpleDiagnostic` for error messages
- Attach diagnostics to the relevant syntax node for precise error location
- Follow existing patterns: `context.diagnose(Diagnostic(node:message:))`
