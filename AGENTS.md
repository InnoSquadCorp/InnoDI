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
- `README.ko.md` mirrors the same structure. `README.{ja,zh-Hans,de,es,ru}.md`
  are maintained concise current-release guides, with an explicit scope notice
  and links to complete English references and historical 6.0.0 translations.
  Keep their version, required sections, install snippet, and safety boundaries
  aligned; do not imply they translate the full reference.
- `Sources/InnoDI/InnoDI.docc/*.md` is the English DocC base.
- `Sources/InnoDI/InnoDI.docc/ko.lproj/*.md` is the maintained localized
  mirror. The other `*.lproj` folders hold only a 6.0.0 translation notice.
- `CHANGELOG.md` is the single release-note and upgrade-note source; `RELEASING.md` defines the release process.

## Coding and Review Notes

- Prefer `SwiftSyntaxBuilder` over string-built AST when changing macro generation.
- Keep parser and graph semantics aligned across `InnoDIMacros`, `InnoDICore`, `InnoDIWorkspaceAnalysis`, and `InnoDIDependencyGraphCore`.
- When behavior changes, update tests and documentation in the same change.
