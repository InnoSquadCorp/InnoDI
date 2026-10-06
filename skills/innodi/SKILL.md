---
name: innodi
description: Implement, test, diagnose, or migrate Swift dependency injection with InnoDI when the project uses InnoDI or the user requests it. Use for InnoDI containers, providers, overrides, and async lifecycle; do not introduce InnoDI for unrelated dependency-injection work.
---

# InnoDI

Help the consumer use its resolved InnoDI API correctly. This skill supports stable **7.0.x** releases (`>=7.0.0, <7.1.0`). Its exact-release example and recorded validation baseline remain **7.0.0**; support for the patch series is not a claim that every patch was tested. It works without another InnoSquad skill or an MCP server.

## Establish the version before editing

Read the consumer's package declaration and applicable `Package.resolved`; identify the actual resolved version, revision, target, deployment floor, and Swift/Xcode version. A declared version range alone is not the installed version. For a local/path dependency, inspect that checkout and identify it as a local dependency.

- For stable 7.0.x, use [support.json](references/support.json) and the bundled references below. On a patch newer than the validated baseline, check its release notes and resolved manifest for relevant fixes and dependency/toolchain changes, then validate the affected consumer target. Do not downgrade just to match the example's pin.
- For versions outside 7.0.x, prereleases, or unreleased `main`, inspect the resolved source or exact release documentation before borrowing these examples. Do not silently upgrade, downgrade, or substitute a path dependency.
- For new adoption, check the latest published stable 7.0.x release and the project's toolchain and other macro dependencies first; read [compatibility.md](references/compatibility.md) when resolving or changing dependencies. The example's exact 7.0.0 pin is a reproducible baseline, not a requirement to select that patch.
- If the dependency cannot be resolved or inspected, state the API/version uncertainty. A successful bundled fixture does not validate the user's application.

## Choose the relevant workflow

| Task | Read and use |
|---|---|
| Add a container, wire services, create previews or test overrides | [implementation.md](references/implementation.md) and the [consumer source](assets/consumer/Sources/InnoDISkillExample/Services.swift) |
| Async preparation, failure, cancellation, retry, or shutdown | [async-lifecycle.md](references/async-lifecycle.md) and the [consumer tests](assets/consumer/Tests/InnoDISkillExampleTests/ConsumerTests.swift) |
| Upgrade 6.x, investigate diagnostics, or inspect graph output | [migration-diagnostics.md](references/migration-diagnostics.md) |
| SwiftUI host, child containers, assisted injection, multibinding, or generated mocks | Follow the exact-version upstream links in the relevant reference; the small consumer is not proof of these advanced paths |

Read only the references needed for the requested change. Adapt the smallest suitable example to the consumer's architecture.

## Keep these contracts intact

- Declare one container macro: `@DIContainer` or `@DIContainerRole`. Prefer macro-generated typed wiring over adding a runtime registration layer.
- Attach `InnoDIDAGValidationPlugin` to every target declaring a container or standalone `@DIEnvironmentBridge`. Fix the diagnostic instead of turning off DAG validation.
- Keep actor isolation explicit at the container boundary. Do not infer it from the target's default isolation setting or add unchecked `Sendable` to bypass compiler errors.
- Use `@Input` for borrowed dependencies and `@Provide` for construction. Override tests and previews before live construction; explicit optional `nil` uses `set(_:to:)`.
- Choose `generateOwned: true` only when its supported shapes and explicit async lifecycle fit the task. Creation is not readiness, reader cancellation is not provider cancellation, and `close()` does not shut down arbitrary returned objects.
- Keep synchronous `prewarm(.service)` separate from async `requireReady(.service)`. Neither is a generic service resolver.

## Verify the consumer and report the boundary

Build/test the changed consumer target with its normal concurrency, warning, and platform settings. Add behavior tests when changing lifetime, overrides, cancellation, or retry. Use a passing control to distinguish fixture mistakes from a library failure.

For this skill's own reusable example, run Python 3 and Swift on an Apple development host:

```bash
python3 scripts/validate_consumer.py --scratch-path /tmp/innodi-skill-validation
```

Run from this skill directory, or use the script's absolute path. The script builds the bundled consumer, verifies its remote exact pins and actual checkout revisions, and records logs plus JSON evidence outside the skill. It tests the recorded baseline, not every supported 7.0.x patch, and does not modify the user's dependency graph. First use downloads dependencies and can take several minutes.

State the resolved version, changed behavior, and actual validation result. Distinguish static guidance, compiled examples, runtime tests, and untested host/platform behavior. Do not claim plugin installation, AI selection quality, or release readiness from a Swift test pass.
