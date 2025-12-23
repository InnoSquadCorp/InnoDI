# Repository Guidelines

## Project Structure & Module Organization
- `Sources/InnoDI`: Public API surface (macros declarations, core types).
- `Sources/InnoDIMacros`: Macro implementations and diagnostics.
- `Sources/InnoDICore`: Shared parsing/analysis utilities used by macros and CLI.
- `Sources/InnoDICLI`: Static analysis CLI for validating container usage.
- `Tests/InnoDICoreTests`: SwiftTesting-based unit tests for core parsing.
- `.github/workflows`: CI workflows (if present) for automated checks.

## Build, Test, and Development Commands
- `swift build`: Build all targets (library, macros, CLI).
- `swift test`: Run test suites (SwiftTesting); macro tests are CI-only.
- `swift test --filter InnoDIMacrosTests`: Run macro tests when enabled in CI with `INNODI_RUN_MACRO_TESTS=1`.

## Coding Style & Naming Conventions
- Swift: 4-space indentation; follow Swift API Design Guidelines.
- Types: `UpperCamelCase` (e.g., `DIContainerMacro`).
- Functions/vars: `lowerCamelCase` (e.g., `parseProvideAttribute`).
- Files: One primary type per file; match type name to file name.
- Prefer `SwiftSyntaxBuilder` for generated syntax nodes; avoid string-built AST when possible.

## Testing Guidelines
- Frameworks: SwiftTesting for core unit tests; `SwiftSyntaxMacrosTestSupport` for macro tests.
- Naming: `*Tests.swift` files; test functions express behavior (e.g., `parseProvideAttributeInput`).
- Coverage: Focus on parsing rules and diagnostics first; add macro expansion tests for critical paths.

## Commit & Pull Request Guidelines
- No explicit commit message convention detected in-repo. Use clear, scoped messages (e.g., `macros: fix Provide diagnostics`).
- PRs should include: summary of changes, test commands run, and any behavior changes or diagnostics updates.

## Architecture Notes
- Keep macro parsing rules centralized in `InnoDICore` to prevent drift between `InnoDIMacros` and `InnoDICLI`.
- Treat `.shared` providers as app-level singletons; prefer `.input` for explicit, testable dependencies.
