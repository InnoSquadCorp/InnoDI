# Compiler canaries

Each directory is a small fixture package that reproduces a compiler problem
InnoDI works around. Files carry a `.fixture` suffix so repository-wide Swift
scans, the dependency-graph CLI, and SwiftPM target inference never see them.

Run every canary with the active toolchain:

```bash
Tools/run-compiler-canaries.sh
```

The script materializes each package into a temporary directory, builds and
runs it, and reports `compiled`, `compiler-crash`, or `failed`. A result never
fails CI. Build logs are written to `build/compiler-canaries`.

## `enum-role-macro`

Swift 6.2.3 crashed with signal 11 while type-checking enum-typed arguments of
the multi-role attached `@DIContainerRole` macro, so InnoDI 6.0 uses the
string-backed `ContainerRole` token. The canary declares a macro with the same
role set and enum-typed `role:` and `isolation:` parameters, then applies it
with qualified and shorthand enum members.

- `compiler-crash` on the Swift 6.2 lane shows that the canary reproduces the
  crash. The lane runs it on manual dispatch because Swift 6.2 builds
  SwiftSyntax from source.
- `compiled` on every supported toolchain is the precondition for restoring an
  enum-typed role. The Xcode 27 preview lane runs the canary on every main push.

No matching upstream issue was found in `swiftlang/swift` as of 2026-09-29.
