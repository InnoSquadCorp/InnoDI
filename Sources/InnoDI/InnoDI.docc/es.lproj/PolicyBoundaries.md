# Policy Boundaries

InnoDI mantiene la validacion determinista definiendo limites explicitos.

## Custom `init` Detection

- La macro rechaza `init` personalizados en el tipo anotado.
- Tambien rechaza extensiones del mismo archivo que apunten al mismo tipo.
- La validacion de build extiende la regla a extensiones cross-file.

## Matching Strategy

- `InnoDIMacros`, `InnoDICore` y el graph CLI comparten el mismo modelo nominal cuando es posible.
- Se soportan rutas anidadas como `Outer.Container`.
- Se excluyen extensiones con argumentos genericos y extensiones con `where`.
- Los casos ambiguos quedan fuera de la regla semantica.

## Declaration Order

- `.input` siempre esta disponible.
- sync `.shared` puede leer inputs y shared previos.
- async `.shared` puede leer inputs, sync shared y async shared previos.
- `.transient` puede leer cualquier miembro, pero la resolucion de nombres sigue siendo estricta.

## Concrete Opt-In

- Se prefiere disenio protocol-first.
- El almacenamiento concrete `.shared` y `.transient` requiere `concrete: true`.
