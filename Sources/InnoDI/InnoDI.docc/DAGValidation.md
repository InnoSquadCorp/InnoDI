# DAG Validation

`@DIContainer(validateDAG:)` controls whether a container participates in the
global dependency-graph gates. The flag is intentionally narrow, but the
trade-off it represents is easy to misuse, so this guide documents what it
actually skips, when opting out is acceptable, and how to keep the opt-out
from leaking into a production release.

## What `validateDAG: false` Disables

`validateDAG: false` disables exactly two layers:

1. The macro's local cycle plus closure and `with:` graph-derived diagnostics.
2. The container's contribution to global DAG validation
   (`swift run InnoDI-DependencyGraph --root . --validate-dag`).

It does **not** disable any of the following:

- Structural macro diagnostics (scope rules, missing factories, declaration
  order availability, async factory validity).
- Raw-expression `factory:` and initializer reference checks.
- Build-time hierarchy validation for `@DIComponent` and `@DIHierarchyRoot`.
- Cross-file custom `init` validation.
- The artifact contract documented in <doc:Validation>.

A consumer with `validateDAG: false` therefore still gets the same
compile-time safety surface as a default container, but loses the part of the
contract that prevents a real cycle from reaching production.

## When Opting Out Is Acceptable

The flag is reasonable in narrow cases:

- A staging build or feature-flag fixture that intentionally wires a temporary
  cycle that will be removed before merge.
- Ad-hoc reproduction containers used only inside a single test or a
  scratchpad executable that ships with the repository but never with the
  product.
- Migration windows where a container is being decomposed into smaller graphs
  and the in-flight intermediate graphs are known to fail global validation.

Each of these is a *temporary* state. If a `validateDAG: false` annotation
survives the work that justified it, the validation gap outlasts the original
constraint and silently widens.

## When Opting Out Is Dangerous

`validateDAG: false` is the wrong tool for any of the following:

- Production release branches.
- "I just want CI to be faster." (Use the synthetic-consumer benchmark to
  size the actual cost first; the global DAG validator caches its analysis
  through the build plugin and is rarely the bottleneck.)
- Avoiding a diagnostic that exposes a real cycle. The fix is to break the
  cycle with `Lazy<T>` or `Provider<T>`, restructure the graph, or split the
  container — not to silence the validator.

If you reach for `validateDAG: false` to "make the warning go away", revert
the change and treat the diagnostic as the source of truth.

## Configuration-Aware Enforcement

A common pattern is to keep validation enabled in production while letting
internal builds skip it during a known-bad migration window. The flag accepts
any compile-time `Bool` expression, so a build configuration boolean keeps
the default safe:

```swift
@DIContainer(validateDAG: !FAST_BUILD)
struct AppContainer {
    // ...
}
```

The corresponding `swiftSettings` line looks like this in `Package.swift`:

```swift
.target(
    name: "AppLib",
    swiftSettings: [
        // FAST_BUILD only flips on for the local-iteration scheme; release
        // and CI builds keep validateDAG on.
        .define("FAST_BUILD", .when(configuration: .debug))
    ]
)
```

For Xcode-based projects, set `FAST_BUILD` only on the iteration scheme's
debug `OTHER_SWIFT_FLAGS` (`-D FAST_BUILD`). The release scheme leaves it
unset and so keeps `validateDAG: true`.

## Reviewer Checklist

When `validateDAG: false` shows up in a diff, treat it as a load-bearing
change rather than a flag flip. Reviewer questions:

1. Which container is opting out, and what is the temporary condition that
   justifies it?
2. Is there a tracking issue and an expected removal date?
3. Does the diff also wire the configuration-aware fallback above so the
   release configuration keeps validation on?
4. Does the affected container have local tests that would catch the cycle
   the validator would have caught?

A repository-level rule (CODEOWNERS approval, PR template checkbox, or a
custom lint rule) keeps the answers visible at review time. The
`Tools/InnoDILintRules/` package ships an `innodi_validate_dag_in_production`
rule once that follow-up lands.

## See Also

- <doc:Validation>
- <doc:PolicyBoundaries>
- ``DIContainer(root:validateDAG:mainActor:)``
