# RFC 0007 — Symbol-graph semantic validation (spike)

- **Status**: Draft (recommendation: reject; awaiting maintainer decision)
- **Authors**: InnoDI maintainers
- **Created**: 2026-09-29
- **Last updated**: 2026-09-29
- **Target release**: none; spike for the 7.0.0 train
- **Tracking plan**: [7.0.0 post-audit plan](../plans/7.0.0-post-audit.md), item X1

## Summary

The spike evaluated a post-compile validator that reads Swift symbol graphs
to see what the syntax-only layers cannot: typealiases, cross-module types,
and superclass chains. It fails all three go criteria in the plan. This RFC
recommends rejecting the validator and adding a compile-time type probe for
`Lazy` and `Provider` aliases instead, which the spike showed covers every
alias form inside the normal build.

## Go criteria

The plan set three criteria, all required:

1. Resolve at least three documented constraints.
2. Run in at most twice the time of the current validation coordinator.
3. Work in the Xcode plugin path.

## Method

All measurements used Xcode 27.0 with Swift 6.4 on macOS. Test packages
lived in a scratch directory. The pilot repositories, InnoSample and
Mulbyul, were only read; no command wrote into them.

- **Graph content**: a two-module package with typealias chains, a class
  hierarchy, a plain container, and a component-role container. Graphs came
  from `swift package dump-symbol-graph --minimum-access-level private` and
  from the compiler's `-emit-symbol-graph` during `swift build`.
- **Plugin APIs**: the `PackagePlugin` and `XcodeProjectPlugin` interfaces
  that ship with Xcode 27.
- **Cost**: a generated package with 500 files in 10 modules, one container
  per file, plus the syntax-only baseline on both pilots.

## Findings

### What symbol graphs contain

| Question | Result |
|---|---|
| Typealias chains across modules | Resolvable. Each hop carries the precise identifier of its target. |
| Superclass relationships and inherited nested types | Present for every module whose graph is extracted. |
| Member-macro output such as the generated `init`, `Overrides`, and `withOverrides` | Absent from both extraction paths. |
| Extension-macro output for component roles | Present, including the mountable conformance and the dependency protocol. |
| `@Input` and `@Provide` markers on members | Absent from declaration fragments. |
| Local types, such as a container declared in an accessor | Absent. Graphs list module-level declarations only. |

### Against the documented constraints

**Aliases of `Lazy` and `Provider`.** Symbol graphs resolve every alias form
the spike tried. A compile-time overload probe resolves the same forms
without them. A documentation-hidden overload set with deprecated overloads
for `Lazy<T>.Type` and `Provider<T>.Type` flagged all six tested forms and
no ordinary type:

- a same-module alias of a cross-module chain;
- a qualified cross-module alias of a generic alias;
- a nested cross-module alias;
- a `Provider` alias;
- a generic alias;
- a local alias of an alias nested in a type.

A deprecation warning raised from macro-generated code is reported at the
macro expansion, so the macro can emit the probe.

The spike also found that the macro-level `provide.lazy-aliased` warning
never fires in a real build. The compiler hands the macro only the attached
declaration, so a file-scope alias is invisible even in the same file. The
check fires only in unit tests that expand against the whole parsed file.
Every alias use still fails closed: InnoDI treats it as a hard edge, and the
generated call fails to type-check with an `aka 'Lazy<…>'` mismatch. The
build plugin's workspace scan lists top-level aliases in its validation
summary, but not in build output, and it does not follow nested aliases. The
misleading "co-locate the alias" guidance is fixed on the 7.0 train.

**Cross-module container types and superclass chains.** Symbol graphs could
verify the inherited-qualifier cases that fail closed today with
`generated-qualifier.inheritance-unverifiable`, but only after compilation.
The prebuild plugin decides before any module exists, so it cannot use the
graphs to accept those cases. The graphs cannot validate cross-module child
inputs, because the generated initializer and the `@Input` markers are
missing. Only component-role containers are identifiable.

**Containers declared in accessors.** The full-source preflight already
rejects them, as the `accessor-local-container-plugin` fixture shows.
Symbol graphs omit local types, so they add nothing here.

At most one constraint gains something the current layers lack, and only in
a post-build step. The first criterion fails.

### Cost

| Workload | Syntax `--validate-dag` | Symbol-graph dump, build up to date | First symbol-graph dump |
|---|---:|---:|---:|
| Generated package, 500 files in 10 modules | 0.23–0.27 s | 3.2–3.6 s | 19.9 s |
| Mulbyul Apple sources, 504 files | 1.6–1.8 s warm, 4.1 s cold | not measurable | not measurable |
| InnoSample, 177 files | 0.12–0.19 s | not measurable | not measurable |

An up-to-date dump costs about 13 to 15 times the syntax validation, before
any compilation. Every source change also recompiles the changed modules
before a graph exists. The second criterion fails. Both pilots are Tuist
projects whose app modules only build through generated Xcode projects, so
no graph could be dumped for them without writing into those repositories.

### Plugin path

- `BuildToolPlugin` has no package manager. Only `CommandPlugin` exposes
  `packageManager.getSymbolGraph(for:options:)`.
- `XcodePluginContext`, used by both `XcodeBuildToolPlugin` and
  `XcodeCommandPlugin`, exposes no package manager or symbol-graph API.

Xcode projects, including both pilots, cannot obtain symbol graphs from any
plugin. The third criterion fails.

## Recommendation

- Reject the symbol-graph validator. Do not schedule an opt-in or
  default-on version.
- Add the compile-time alias probe as a separate item. The macro would emit
  one probe call per hard factory parameter whose written type is not
  `Lazy<…>` or `Provider<…>`, skipping parameters whose target member is
  itself spelled as a wrapper. It covers every alias form in every build
  path, at no measurable cost, and replaces the macro-level alias check that
  never fires in a real build. It changes generated code and snapshots, and
  the plan's three snapshot bundles are already used, so its release is the
  maintainer's decision.
- Keep the syntax-only full-source preflight as the prebuild gate.
- Revisit symbol graphs if SwiftPM or Xcode gives build plugins post-compile
  access, or if symbol graphs start to include member-macro output.

## Alternatives considered

- **An opt-in `--semantic` CI command for SwiftPM packages.** It would cover
  only superclass chains, only for SwiftPM packages, and only after a build.
  Xcode projects would need custom `xcodebuild` and extraction steps. The
  benefit does not justify a supported surface.
- **Extracting SDK symbol graphs for inherited qualifiers.** SDK modules are
  large, and extraction would add to the cost above. The spike did not
  measure it.

## Reproduction

```bash
swift package dump-symbol-graph --minimum-access-level private --skip-synthesized-members
swift build -Xswiftc -emit-symbol-graph -Xswiftc -emit-symbol-graph-dir -Xswiftc /tmp/graphs -Xswiftc -symbol-graph-minimum-access-level -Xswiftc private
```

```bash
swift run -c release InnoDI-DependencyGraph --root /path/to/sources --validate-dag
```

The plugin API findings come from `PackagePlugin.swiftinterface` in the
toolchain and `XcodeProjectPlugin.swiftinterface` in Xcode's SwiftPM
framework.

## Open questions

- Whether the probe should warn or fail. A deprecation warning becomes an
  error under `-warnings-as-errors`, and an alias use almost always fails
  to compile anyway.
