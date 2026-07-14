# Validation

InnoDI валидирует зависимости в несколько слоев.

## Macro Validation

Макро-валидация проверяет:

- правила scope
- размещение `@Provide` только на прямом обычном хранимом instance `var`
- отсутствие factory
- порядок объявления
- локальные cycle
- строгую резолюцию имен
- совместимость эффектов явных sibling edges
- недопустимые пользовательские `init`

Явные sibling edges создаются только именованными параметрами root literal
closure `factory:`/`asyncFactory:` либо `Type.self` с literal key paths
`with:`. Не-closure factory и property initializer — непрозрачные zero-edge
источники и не могут ссылаться на sibling members.

`validateDAG: false` не отключает проверку деклараций и совместимость эффектов;
пропускаются только global DAG, local cycle и другие graph-derived проверки.

## Build Validation

coordinated build pipeline добавляет:

1. cross-file проверку `init`
2. semantic reference check
3. hierarchy validation
4. DAG validation
5. вывод metrics / summary artifact
