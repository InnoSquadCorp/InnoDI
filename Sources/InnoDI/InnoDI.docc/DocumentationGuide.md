# Documentation Guide

Choose a task, then follow its current API guide. This documentation targets
InnoDI 7.0.1. For another installed version, use that release's source tag.

## Installation and First Use

The repository README contains the complete SwiftPM installation steps and
platform requirements. Add `InnoDI`, optionally `InnoDISwiftUI`, and attach
`InnoDIDAGValidationPlugin` to every target declaring a container or standalone
`@DIEnvironmentBridge`. Adding a package alone does not attach the plugin.
Add `InnoDITesting` to test or preview-support targets when using its helpers.

- <doc:GettingStarted>: guided first container
- <doc:Tutorial-01-Hello>: a small synchronous application
- <doc:Tutorial-02-Inputs>: values supplied at construction
- <doc:Tutorial-03-Wiring>: named factory dependencies
- <doc:Tutorial-04-Concrete>: concrete and protocol storage
- <doc:IntegrationGuide>: SwiftPM, Xcode, Tuist, lint and format integration
- <doc:lock-safety>: local scratch storage and filesystem restrictions

Swift tools 6.2 is the minimum; supported deployment targets are iOS 17,
macOS 14, watchOS 10, tvOS 17 and visionOS 1 or newer. Linux is not a supported
package configuration. SwiftSyntax is pinned to 604.0.0, which conflicts with
Mockable 0.6.4's range. Check dependency resolution for the entire consumer
graph before selecting another macro package.

## API and Composition Map

| Need | Surface | Guide |
| --- | --- | --- |
| Describe the application graph | `@DIContainer`, `@DIContainerRole` | <doc:DIContainer> |
| Pass configuration or a runtime value | `@Input`, `@Input(escaping: true)` | <doc:Provide> |
| Create shared or fresh values | `@Provide`, `.shared`, `.transient`, `factory:`, `asyncFactory:` | <doc:Provide> |
| Defer synchronous work or prewarm selected services | `.onDemand`, `prewarm`, `Lazy`, `Provider` | <doc:Provide> |
| Mount a fixed child | `@SubContainer`, `with:`, `bindings:` | <doc:Tutorial-05-SubContainer> |
| Create a child with call-time arguments | `@Input(.assisted)`, `@AssistedFactory`, `@SubContainerFactory` | <doc:Composition> |
| Compose module contributions | `@Multibinding`, `DICollectionGroup`, keyed/provider collections | <doc:Composition> |
| Inspect graph contracts and reverse impact | `InnoDI-DependencyGraph` | <doc:DAGValidation> |
| Correlate generated runtime events | `DITraceContext`, `DIBoundedTraceBuffer` | <doc:RuntimeTracing> |

Factory parameter names and canonical direct-member `\Self.member` paths define
explicit graph edges. Arbitrary factory-body references are not discovered.
`validateDAG: false` is a limited escape hatch, not permission to bypass
ownership, declaration or effect checks; see <doc:PolicyBoundaries> and
<doc:PluginOptOut>.

## Lifecycle and SwiftUI

- <doc:OwnedContainers>: opt-in generated ownership, `makeOwned`, selected
  `prepare`, retry, `withPrepared` and awaited `close`
- <doc:AsyncPreparation>: ordinary async providers and manual `DIAsyncScope`
- <doc:Provide>: eager versus on-demand construction and cancellation
- <doc:SwiftUIPreviewHelper>: feature-root helpers,
  `DIContainerHost`, identity, previews and explicit close handling

Choose the lifecycle before adding asynchronous factories. `makeOwned` does
not mean ready; inspect `report.isReady` for report-returning preparation.
Ordinary eager async shared providers start during initialization and are not
cancelled by the container. Async on-demand providers have throwing accessors
and `closeAsyncProviders()`. Generated owners require explicit closure and do
not take ownership of borrowed input resources or arbitrary tasks inside a
service. A SwiftUI disappearance is not necessarily the end of ownership.

## Testing and Failure Recovery

Use generated `Overrides`/`withOverrides` to replace dependencies without a
runtime registration container. <doc:AutoMock> covers `@GenerateMock`, stub
validation, invocation inspection and reset boundaries. `InnoDITesting` adds
`DIOverridePreset`, MainActor-compatible validation adapters, effect validation and typed
helpers; its [module reference](https://github.com/InnoSquadCorp/InnoDI/blob/main/Sources/InnoDITesting/InnoDITesting.docc/InnoDITesting.md) describes those APIs.

For a failure, start with the emitted diagnostic identifier:

- <doc:DiagnosticsGuide>: recovery by diagnostic
- <doc:Validation>: which layer catches the error
- <doc:ModuleWideInitDetection>: cross-file initializer conflicts
- <doc:PolicyBoundaries>: unsupported declarations, isolation and wiring
- <doc:AntiPatterns>: graph designs to avoid

Run the read-only Doctor before migration. Run these commands from an InnoDI
checkout matching your installed version, replacing the consumer path:

```bash
swift run InnoDI-Doctor --root /path/to/consumer
swift run InnoDI-Migrate --root /path/to/consumer --check
swift run InnoDI-Migrate --root /path/to/consumer --report
swift run InnoDI-DependencyGraph --root /path/to/consumer --validate-dag
```

Review the report before using a write mode. A successful parse, Doctor report,
or graph check is not a successful consumer build. Build and test the actual
Apple target with its real isolation and import settings. Keep reported
`RECOVERY` files until the migrated sources have been reviewed.

## Upgrades and Documentation Languages

- <doc:MigrationGuide>: version-to-version source changes, including 6.x → 7.0
- <doc:MigratingFromFactory>: adopting InnoDI alongside or instead of Factory
- <doc:MigratingFromSwinject>: moving runtime registration into explicit wiring

The repository `CHANGELOG.md` is the release/upgrade source of truth.
`docs/plans`, `docs/reviews`, `docs/rfcs` and older changelog entries preserve
historical evidence; their proposals and old code are not current API recipes.
The examples use the local checkout, whereas README package snippets select a
published release. Do not treat passing a historical 7.0.0 fixture as evidence
that an actual 7.0.1 consumer was tested.

English is the complete canonical reference. Korean mirrors the English
README and DocC article sources. Japanese, Simplified Chinese, German, Spanish
and Russian READMEs provide current concise guides with explicit links into
the complete reference; their DocC directories remain historical 6.0.0 notices.
The generated DocC archive builds the English catalog. Translated source files
in the repository do not imply a language selector in the published archive.
