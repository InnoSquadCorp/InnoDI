# Module-Wide Init Detection

`@DIContainer` aplica restricciones de `init` personalizado en la macro y en
la validacion de build.

## Macro Layer

La macro rechaza `init` personalizados en:

- el cuerpo del tipo anotado
- extensiones del mismo archivo que apunten al mismo tipo

## Build Layer

La validacion de build extiende la misma regla a extensiones cross-file antes
de la validacion semantica y DAG.

## Boundaries

- se soportan rutas anidadas
- se excluyen extensiones con argumentos genericos
- se excluyen extensiones con `where`
- los casos ambiguos quedan fuera de la regla determinista
