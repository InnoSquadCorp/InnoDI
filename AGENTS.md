# Repository Guidelines

## Project Structure

- `Sources/InnoDI`: public macros, runtime types, and source doc comments.
- `Sources/InnoDIMacros`: macro expansion, validation, diagnostics, and SwiftUI helper generation.
- `Sources/InnoDICore`: shared graph and analysis utilities used by macros and the CLI.
- `Sources/InnoDIBuildSupport`: coordinated validation, artifacts, and cache/lock handling.
- `Sources/InnoDIDependencyGraphCore`: graph collection, validation, and Mermaid/DOT/ASCII/JSON rendering.
- `Sources/InnoDIDependencyGraphCLI`: shared dependency-graph command implementation.
- `Sources/InnoDI-DependencyGraph`: public executable entry point.
- `Sources/InnoDISwiftUI`: SwiftUI environment bridge and feature-root integration helpers.
- `Tests/*`: Swift Testing suites for runtime, macros, build support, CLI, SwiftUI, and shared helpers.

## Build, Test, and Docs

- `swift build`
- `swift test`
- `swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors`
- `swift run InnoDI-DependencyGraph --root /path/to/project --root-pruning all`
- `Tools/generate-docc.sh`

## Documentation Contract

- `README.md` is the English canonical README.
- Localized README files mirror the same structure:
  - `README.ko.md`
  - `README.es.md`
  - `README.de.md`
  - `README.zh-Hans.md`
  - `README.ja.md`
  - `README.ru.md`
- `Sources/InnoDI/InnoDI.docc/*.md` is the English DocC base.
- `Sources/InnoDI/InnoDI.docc/*.lproj/*.md` are localized mirrors.
- `RELEASING.md` is the single release-note and upgrade-note source.

## Coding and Review Notes

- Prefer `SwiftSyntaxBuilder` over string-built AST when changing macro generation.
- Keep parser and graph semantics aligned across `InnoDIMacros`, `InnoDICore`, `InnoDIWorkspaceAnalysis`, and `InnoDIDependencyGraphCore`.
- When behavior changes, update tests and documentation in the same change.
