# Module-Wide Init Detection

`@DIContainer` ограничивает пользовательские `init` и на уровне макроса, и на
уровне build validation.

## Macro Layer

- запрещает пользовательский `init` в annotated type body
- запрещает такой же `init` в same-file extension

## Build Layer

- расширяет то же правило на cross-file extension
- неоднозначные и неподдерживаемые случаи остаются вне детерминированного правила
