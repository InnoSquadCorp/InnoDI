# Contributing to InnoDI

Thanks for contributing.

## Before Opening a PR

Please keep these checks green:

```bash
swift test
(cd Examples/SwiftUIExample && swift test)
(cd Examples/PreviewInjectionExample && swift test)
swift run InnoDI-DependencyGraph --root . --validate-dag
```

Update docs in the same change when behavior changes:

- `README.md`
- `README.ko.md`
- `Sources/InnoDI/InnoDI.docc/Validation.md`
- `Sources/InnoDI/InnoDI.docc/PolicyBoundaries.md`
- `Sources/InnoDI/InnoDI.docc/ModuleWideInitDetection.md`

## PR Expectations

- Keep changes scoped and explain user-facing behavior changes.
- Add or update tests for validation, diagnostics, graph output, or examples when behavior changes.
- If validation artifacts or schema expectations change, update `RELEASING.md` and `MIGRATION.md`.

## Issues and Discussions

- Use issues for reproducible bugs, missing diagnostics, or feature requests.
- Include sample containers or CLI output when reporting graph or validation problems.
