# Contributing to InnoDI

Thanks for contributing.

## Before Opening a PR

Please keep these checks green:

```bash
swift test
(cd Examples/SwiftUIExample && swift test)
(cd Examples/PreviewInjectionExample && swift test)
swift run InnoDI-DependencyGraph --root . --validate-dag
Benchmarks/run-validation-bench.sh --preset ci
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
- If benchmark artifacts or schema expectations change, update `RELEASING.md` and `MIGRATION.md`.
- If performance changes intentionally, refresh the relevant baseline and call it out in the PR description.

## Issues and Discussions

- Use issues for reproducible bugs, missing diagnostics, or feature requests.
- Include sample containers or CLI output when reporting graph or validation problems.
