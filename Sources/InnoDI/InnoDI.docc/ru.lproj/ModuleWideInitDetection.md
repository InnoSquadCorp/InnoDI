# Module-Wide Init Detection

`@DIContainer` ограничивает пользовательские `init` и на уровне макроса, и на
уровне build validation.

## Macro Layer

Макровалидация отклоняет пользовательские `init` только в теле annotated type.
Attached macro не может надежно просматривать соседние extensions в том же
исходном файле.

## Обязательный Build Layer

`InnoDIDAGValidationPlugin` необходимо подключить к каждому target, который
объявляет контейнеры. Его full-source preflight отклоняет `init` в совпадающих
same-file и cross-file extensions, включая объявления внутри ветвей `#if`.

Без build-validation plugin запрет пользовательских `init` во всех extensions
не гарантируется. Неоднозначные и неподдерживаемые случаи остаются вне
детерминированного правила.
