# Policy Boundaries

InnoDI сохраняет детерминированность за счет явных границ.

## Обнаружение пользовательских `init`

- Макровалидация отклоняет пользовательские `init` только в теле annotated
  type.
- Обязательный full-source preflight `InnoDIDAGValidationPlugin` отклоняет
  `init` в совпадающих same-file и cross-file extensions, включая объявления
  внутри ветвей `#if`.
- Без build-validation plugin запрет во всех extensions не гарантируется,
  поскольку attached macro не может надежно просматривать соседние extensions.

## Matching Strategy

- общий nominal-path подход для макросов, Core и graph CLI
- поддержка вложенных путей вроде `Outer.Container`
- исключение generic argument extension и `where` extension
- неоднозначные случаи не приводят к спекулятивным совпадениям

## Эффекты provider

- Синхронный provider можно использовать в sync, `async` и `async throws`
  factories.
- Для `async` provider нужен consumer `async` или `async throws`.
- Для `async throws` provider нужен consumer `async throws`.
- Эффекты не выводятся из зависимостей. Consumer явно использует
  `asyncFactory:` и при необходимости closure `async throws`.
- `Lazy<T>` и `Provider<T>` — синхронные deferred wrappers, поэтому они
  отвергают асинхронные targets.

## Изоляция и Sendability

- Контейнеры хранят сгенерированное состояние внутри значения контейнера.
  InnoDI не помещает зависимости в глобальный registry.
- `mainActor: true` изолирует аксессоры зависимостей, все сгенерированные
  инициализаторы, `Overrides`, типы замыканий `applyOverrides` для convenience
  initializer, `withOverrides`, overrides дочерних контейнеров и mounting
  компонентов, операционные замыкания всех четырёх overload `withOverrides` и
  сгенерированные feature-root helpers. Этот вариант рекомендуется для
  корневых UI-контейнеров.
- При совместном использовании с `@DIComponent` сгенерированные dependency
  protocol, `init(dependencies:_:)` и тип override closure изолируются с помощью
  `@MainActor`, а компонент получает отдельную conformance
  `_InnoDIMainActorComponentMountable`. Обычные компоненты продолжают
  использовать неизолированный `_InnoDIComponentMountable`. В 5.0 generic
  mounting helpers должны предоставлять отдельные constraints и типы closures
  для обоих markers.
- Сгенерированные значения container/component и зависимости, не реализующие
  `Sendable`, должны оставаться на главном акторе. Предпочтителен caller с
  `@MainActor` либо блок `MainActor.run`, который и создаёт, и использует эти
  значения. Прямой `await` подходит, когда изолированная операция возвращает
  `Sendable`-результат, например результат операции `withOverrides`; он не
  позволяет безопасно вынести non-`Sendable` container за пределы актора.
- Wrappers `Lazy<T>` и `Provider<T>` не являются способом передачи между
  actors. Их следует считать частью области изоляции контейнера, если `T` и
  окружающий путь вызова ещё не безопасны для передачи.
- Зависимости, не реализующие `Sendable`, следует передавать через явные границы
  контейнера и изолировать на уровне приложения, а не скрывать за глобальным
  lookup.

## Форма хранения из объявленного типа

- Предпочтителен protocol-first подход к dependency design.
- Источником истины служит объявленный тип property: конкретный nominal type
  использует concrete storage, а `any Protocol` — existential storage.
- Форма хранения не выбирается флагом атрибута или эвристикой macro.
