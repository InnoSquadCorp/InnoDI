# Contributing to InnoDI

Thanks for contributing.

## Before Opening a PR

Please keep these checks green:

```bash
swift test
swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
(cd Examples/SwiftUIExample && swift build && swift test)
(cd Examples/PreviewInjectionExample && swift build && swift test)
swift run InnoDI-DependencyGraph --root . --validate-dag
Tools/generate-docc.sh
```

## Documentation Contract

If behavior changes, update the docs in the same change.

Canonical sources:

- `README.md`
- `Sources/InnoDI/InnoDI.docc/*.md`
- `RELEASING.md`
- `ROADMAP.md`

Localized mirrors:

- `README.ko.md`
- `README.es.md`
- `README.de.md`
- `README.zh-Hans.md`
- `README.ja.md`
- `README.ru.md`
- `Sources/InnoDI/InnoDI.docc/*.lproj/*.md`

Keep the English docs authoritative, then mirror the same structure and meaning
into localized README and DocC files.

The generated DocC archive currently builds from the English base catalog, so
localized DocC files are maintained as source mirrors in the repository.

## PR Expectations

- Keep changes scoped and explain user-facing behavior changes.
- Add or update tests for validation, diagnostics, graph output, SwiftUI helpers, or examples when behavior changes.
- If release notes, upgrade guidance, artifact naming, or schema expectations change, update `RELEASING.md` in the same change.
- Prefer `SwiftSyntaxBuilder` over string-built AST when changing macro generation.

## Issues and Discussions

- Use issues for reproducible bugs, missing diagnostics, or feature requests.
- Include sample containers, diagnostics, or CLI output when reporting graph or validation problems.
