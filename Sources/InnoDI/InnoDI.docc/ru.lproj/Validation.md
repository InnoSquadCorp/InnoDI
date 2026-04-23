# Validation

InnoDI валидирует зависимости в несколько слоев.

## Macro Validation

Макро-валидация проверяет:

- правила scope
- отсутствие factory
- порядок объявления
- локальные cycle
- строгую резолюцию имен
- недопустимые пользовательские `init`

`validateDAG: false` не отключает структурную валидацию.

## Build Validation

coordinated build pipeline добавляет:

1. cross-file проверку `init`
2. semantic reference check
3. hierarchy validation
4. DAG validation
5. вывод metrics / summary artifact
