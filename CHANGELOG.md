# Changelog

All notable changes to InnoDI should be recorded in this file.

The format is based on Keep a Changelog, adapted for the InnoDI release workflow in [RELEASING.md](RELEASING.md).

## Unreleased

### Added

- `Lazy<T>` escape hatch for breaking dependency cycles at the factory-parameter boundary. A factory parameter typed `Lazy<T>` is now classified as a *soft* dependency: it is excluded from both the per-container cycle detector (`container.dependency-cycle`) and the CLI's global `--validate-dag` check, while still being rendered in the dependency graph.
- `_LazyCell<T>` runtime class that backs the macro-generated `Lazy` wrappers so `struct` containers can forward-reference siblings without capturing `self`.
- `DependencyGraphEdge.isSoft` flag plus the `buildCycleDetectionAdjacency(nodes:edges:)` helper in `InnoDICore`, so macros and the CLI share one soft-edge contract.

### Changed

- `container.dependency-cycle` diagnostic message now suggests wrapping one factory parameter in `Lazy<T>` to break the cycle without restructuring.
- Mermaid, DOT, and ASCII renderers style soft edges distinctly: dashed arrows (`-.->`, `style=dashed`, `- ->`) with an ASCII legend that appears only when soft edges are present.
- `deduplicateEdges(_:)` in `InnoDICore` now follows a hard-wins rule when the same `(from, to, label)` triple is reported by multiple sites — a merged edge is soft only if *every* occurrence was soft.

## 3.0.1

### Changed

- Removed `swift-docc-plugin` from the main consumer package graph so SwiftPM users only resolve runtime/build dependencies needed to use InnoDI.
- Updated DocC generation to inject the DocC plugin only inside a temporary docs-only package during documentation builds.

## 3.0.0

### Added

- CI-friendly validation benchmark preset, baseline compare artifacts, and Markdown summary output.
- Docs entrypoint guidance for `README`, `Validation`, `PolicyBoundaries`, and `ModuleWideInitDetection`.
- Release governance documents for changelog, migration notes, and artifact schema expectations.
- OSS repository documents for licensing, contributing, security, and community conduct.
- Tag-based release workflow with release-gate validation checks and artifact uploads.
- Automated GitHub Release publication that uses the matching changelog section as the release body.

### Changed

- Validation benchmark workflow now distinguishes local exploration from CI regression gating.
- Promoted strict validation, semantic enforcement, and build-stage release contracts as the new major-version baseline for OSS consumers.
