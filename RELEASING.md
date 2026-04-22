# Releasing InnoDI

This document defines the minimum release quality bar for InnoDI.

Current stable public release target: `3.0.1`

## Release Checklist

Before tagging a release:

1. Update [CHANGELOG.md](CHANGELOG.md).
2. Decide whether [MIGRATION.md](MIGRATION.md) needs a new entry.
3. Run the main package test suite and example package tests/builds.
4. Run the global DAG check:
   - `swift run InnoDI-DependencyGraph --root . --validate-dag`
5. Decide whether any validation artifact schema version changed and document it below.
6. Confirm the release tag matches the README installation snippet.
7. Confirm the GitHub Actions `Release Gate` workflow will run from the intended tag.
8. Confirm the matching `## <tag>` section exists in [CHANGELOG.md](CHANGELOG.md); the release workflow publishes that body automatically.

## Artifact Schema Versioning

These artifacts are treated as release-quality contracts:

- validation metrics JSON artifact
- validation summary Markdown artifact

Versioning rules:

- additive fields: minor schema increment or paired document note
- changed semantics or removed fields: explicit version bump plus migration note
- Markdown summaries do not carry a standalone numeric schema field; they follow the paired JSON schema and release notes

Current tracked versions:

- `ValidationMetricsArtifact.currentVersion`: see [ValidationMetrics.swift](Sources/InnoDIBuildSupport/ValidationMetrics.swift)
- `sharedRunCacheVersion`: see [ValidationCoordinator.swift](Sources/InnoDIBuildSupport/ValidationCoordinator.swift)

## GitHub Release Notes

The tag-driven `Release Gate` workflow automatically creates the GitHub Release and uses the matching `## <tag>` section from [CHANGELOG.md](CHANGELOG.md) as the release body.

That changelog section should summarize:

- user-facing validation or diagnostics changes
- documentation or release-process changes
- migration impact, if any

## Documentation Expectations

Each release should leave these entrypoints consistent:

1. [README.md](README.md)
2. [Validation.md](Sources/InnoDI/InnoDI.docc/Validation.md)
3. [PolicyBoundaries.md](Sources/InnoDI/InnoDI.docc/PolicyBoundaries.md)
4. [ModuleWideInitDetection.md](Sources/InnoDI/InnoDI.docc/ModuleWideInitDetection.md)

If a release changes user-facing validation behavior, update those docs in the same change.

## Automated Release Artifacts

The release workflow publishes these assets to the GitHub Release:

- packaged DocC archive

Validation metrics and summary artifacts are still treated as release-quality
contracts, but they are produced as part of validation/build flows rather than
published as standalone release assets.

If artifact naming or schema changes, update this document and
[CHANGELOG.md](CHANGELOG.md) in the same release. If the coordinator cache salt
changes, update this document and the release-contract tests in the same
change.
