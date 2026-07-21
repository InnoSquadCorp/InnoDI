# Руководство по интеграции

Используйте InnoDI как сгенерированный Swift-код вместе с build-time validation.
Большинство инструментов работает лучше, когда macro output считается
compiler-generated implementation detail, а написанные пользователем объявления
container остаются основной поверхностью для review.

## Periphery

- Запускайте Periphery с generated build settings, а не с hand-written source
  globs, чтобы macro-expanded members были видимы компилятору.
- Держите `@DIContainer`, `@Provide`, `@SubContainer` и generated override entry
  points reachable через tests, sample apps или explicit retention rules, если
  они вызываются только reflection-free wiring.
- Чтобы снизить generated-member noise, лучше retain container type или его public
  entry points, а не игнорировать весь module.

## SwiftLint

- Линтуйте user-authored source обычным образом.
- Не линтуйте macro-expanded output как hand-written code.
- Если конфигурация проверяет generated interface artifacts, исключите reserved
  generated prefixes InnoDI: `_storage_`, `_override_`, `_innoDI`, `_InnoDI`.

## SwiftFormat

- Форматируйте container declarations, которые вы пишете вручную.
- Не требуйте отдельный formatting pass для macro expansion snapshots в consumer
  projects.
- Сохраняйте attributes и factory closures читаемыми в месте объявления; именно
  этот source должны просматривать reviewers.

## Сгенерированные макросами члены

InnoDI генерирует initializers, storage, overrides и helper closures из container
declarations. Считайте эти generated members частью compiled API surface, но
оставляйте manual dependencies явно описанными в source container.

Когда инструмент сообщает о generated symbol, сначала сопоставьте его с ближайшим
`@DIContainer`, `@Provide` или `@SubContainer`, и только потом решайте, является ли
сообщение actionable.

## Build-плагин

Подключайте `InnoDIDAGValidationPlugin` к каждому target, который объявляет
containers или standalone `@DIEnvironmentBridge`. Target-scoped full-source
pass отклоняет невидимые для attached macro generated qualifier shadows во
включающих объявлениях и других source того же target, а также видимые
qualifier shadows с доступом `public` или `package` в импортированных dependency
targets. Он также отклоняет direct-extension attachments и standalone local
bridge targets до компиляции Swift.

Начиная с 5.1 этот package plugin также реализует `XcodeBuildToolPlugin`.
Подключайте его непосредственно к каждому container target в нативном Xcode
project или project, созданном Tuist. В Tuist workspace он находит workspace
root и создает единый production-source snapshot, чтобы cross-project container
references оставались видимыми для source-level validation.

Xcode plugin API не предоставляет полную cross-project target dependency
topology Tuist. Поэтому Tuist fallback проверяет полный source DAG и declaration
contracts, но правила module-edge hierarchy, зависящие от точного target graph,
по-прежнему требуют topology-aware SwiftPM или CI check. Multi-destination
variants могут использовать общий plugin work directory, поэтому Xcode commands
не объявляют outputs и Xcode может планировать validation при каждом build.

Для class bridge или container/bridge, вложенного в class, preflight рассматривает
первый inherited type как потенциальный superclass. Все пройденные class и
typealias должны быть source-visible в snapshot workspace. Первый inherited type,
доступный только в SDK или binary, unresolved либо ambiguous, отклоняется с
`generated-qualifier.inheritance-unverifiable`; используйте struct/enum или
source-visible adapter, если внешнюю иерархию нельзя индексировать. Консервативный
syntax-only index отклоняет унаследованные type members `Swift` и `SwiftUI`,
используемые при генерации bridge, но допускает унаследованный `InnoDISwiftUI`.
Прямые и enclosing declarations `InnoDISwiftUI` остаются зарезервированными.

Plugin теперь запускает DAG validator
in-process через build coordinator; standalone executable
`InnoDI-DependencyGraph` остается доступным для local inspection и CI artifacts.

Если derived data находится на network volume, используйте local SwiftPM scratch
path. Scratch path должен находиться на local disk и быть writable; замените
`/tmp` на подходящий local temporary directory для вашей OS или CI-среды, если
это необходимо.

```sh
swift build --scratch-path /tmp/innodi-cache
```

Классификация filesystem и lock recovery описаны в <doc:lock-safety>.
