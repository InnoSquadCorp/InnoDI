# Macro Plugin JSON Decode Investigation

> **Status**: Open investigation
> **Created**: 2026-04-26
> **Target**: Track the non-fatal `Internal Error: DecodingError.dataCorrupted`
> stderr emitted during some `swift test` builds.

This document is internal. It records the current reproduction surface and the
next narrowing steps so the warning does not get lost just because the test
suite still exits successfully.

## Observed symptom

During local runs of the package test suite and the strict-concurrency suite,
SwiftPM occasionally prints:

```text
Internal Error: DecodingError.dataCorrupted: Data was corrupted.
Debug description: Corrupted JSON. Underlying error: unexpected end of file
```

The suite then continues and passes. The message is emitted by
`SwiftCompilerPluginMessageHandling.CompilerPluginMessageHandler` while reading
host-to-plugin JSON. The failure shape is consistent with the compiler host
closing a macro-plugin message stream while the plugin process is still trying
to decode the next message.

## Current scope

- Local toolchain: Apple Swift 6.3 (`swiftlang-6.3.0.123.5`,
  `clang-2100.0.123.102`), target `arm64-apple-macosx26.0`
- SwiftSyntax dependency: `602.0.0`
- Macro plugin target: `InnoDIMacros`
- Public macro modules that can trigger the plugin:
  - `InnoDI`
  - `InnoDISwiftUI`
- The issue is not currently known to corrupt generated code or fail tests.
- Treat this as a reliability investigation unless a minimal reproduction ties
  it to a specific InnoDI macro expansion path.

## Local verification on 2026-04-26

All commands below exited `0`.

| Command | Result | JSON decode log |
| --- | --- | --- |
| `swift test` | 464 tests passed | Reproduced twice while compiling `InnoDIRuntimeTests` |
| `swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors` | 464 tests passed | Reproduced while compiling `InnoDI` and `InnoDISwiftUI` |
| `swift test --filter InnoDISwiftUITests` after `swift package clean` | 3 tests passed | Reproduced during the pre-test package build, around `InnoDI` compilation |
| `swift test --filter InnoDIRuntimeTests` after `swift package clean` | 36 tests passed | Reproduced while compiling `InnoDIRuntimeTests` |
| `swift test --filter InnoDIMacrosTests` after `swift package clean` | 188 tests passed | Reproduced while compiling `InnoDIRuntimeTests` during the pre-test package build |
| `swift build --target InnoDI` after `swift package clean` | Build passed | Not reproduced |
| `swift build --target InnoDISwiftUI` after `swift package clean` | Build passed | Not reproduced |

Current narrowing: the warning reproduces during SwiftPM test-bundle builds,
not during standalone `InnoDI` or `InnoDISwiftUI` target builds. The smallest
observed surface is therefore still the package test build rather than a single
library target. The repeated association with `InnoDIRuntimeTests` compilation
suggests a macro-plugin process lifecycle / host stream shutdown race is more
likely than generated-code corruption, but this is not closed until a fixture
or upstream issue proves that boundary.

## Reproduction commands

Run these from the package root, preferably after removing `.build` when trying
to maximize plugin-process churn:

```sh
swift test
swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
swift test --filter InnoDISwiftUITests
swift test --filter InnoDIRuntimeTests
swift test --filter InnoDIMacrosTests
swift build --target InnoDISwiftUI
swift build --target InnoDI
```

Record whether the stderr line appears, the build step immediately before it,
and whether the process still exits `0`.

## Next narrowing steps

1. Re-run the filtered test commands above with a fresh `.build` and note the
   smallest target that reproduces the message.
2. If only targets importing `InnoDISwiftUI` reproduce it, isolate the
   SwiftUI peer macros (`@DIEnvironmentBridge`, `@DIFeatureRoot`) with a small
   fixture.
3. If runtime or macro tests reproduce it independently, bisect by macro family
   (`@DIContainer`, `@Provide`, `@SubContainer`, hierarchy macros).
4. If the smallest reproduction is still toolchain-level, file or prepare an
   upstream SwiftSyntax/Swift compiler report with the command, Swift version,
   SwiftSyntax version, stderr excerpt, and exit status.

## Acceptance criteria for closing

- A specific InnoDI macro path is fixed and covered by a regression test, or
- the issue is classified as a SwiftSyntax/toolchain process-lifecycle issue
  with a documented minimal reproduction and upstream issue link.
