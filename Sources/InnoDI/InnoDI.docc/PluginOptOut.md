# Build Plugin Opt-Out

`InnoDIDAGValidationPlugin` attaches automatically to every target that
declares an InnoDI container, runs the validation coordinator, and serializes
graph artifacts under SwiftPM's plugin work directory. The coordinator is
incremental and cached, but the plugin still adds a per-target build step
and a swift-syntax invocation. Two narrow situations make opting out
defensible.

## When Opt-Out Is Reasonable

- **Throwaway PoCs and scratchpads** that import InnoDI but do not ship.
  The author wants the macro expansion + Swift compiler diagnostics, not
  the build-time gate.
- **Fast inner loops** during a refactor that intentionally puts the
  workspace in a known-bad state. Re-enable the gate before the change
  lands.
- **Build farms that already run the gate elsewhere** as a discrete CI
  job. Skipping the per-target plugin hook avoids double-running the
  same validator.

## When Opt-Out Is Wrong

- **Production release branches.** The plugin is the gate that produces
  the validation metrics artifact downstream tooling consumes; bypassing
  it removes the audit trail.
- **CI on shared infrastructure** that does not also run
  `swift run InnoDI-DependencyGraph --validate-dag` somewhere. Without a
  replacement, the global DAG gate is gone.
- **Anything user-facing.** The plugin's job is to keep a broken graph
  from reaching consumers; turning it off in the path that ships is the
  same as removing the contract.

## How to Opt Out

Set the environment variable at build invocation:

```sh
INNODI_DISABLE_BUILD_VALIDATION=1 swift build
```

Accepted values are `1`, `true`, `TRUE`, `yes`, `YES`. Anything else (or
the variable being unset) leaves the plugin enabled. The variable is read
once per invocation when the plugin schedules its commands; it does not
persist across builds, and Xcode's Build Settings sheet resets it when the
process restarts.

`INNODI_DISABLE_BUILD_VALIDATION=1` is independent from
`INNODI_ALLOW_UNSAFE_LOCK=1`. The latter still runs the validator but on
an unsafe filesystem; the former skips the validator entirely. They
should never both be on in the same build — that combination silently
ships a build with no validation and no audit trail.

## See Also

- <doc:DAGValidation>
- <doc:lock-safety>
