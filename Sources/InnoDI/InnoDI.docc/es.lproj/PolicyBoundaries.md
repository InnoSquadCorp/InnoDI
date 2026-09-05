# Policy Boundaries

InnoDI mantiene la validación determinista definiendo límites explícitos.

## Custom `init` Detection

- La macro rechaza `init` personalizados solo en el cuerpo del tipo anotado.
- El preflight obligatorio de `InnoDIDAGValidationPlugin` rechaza `init` en
  extensiones coincidentes del mismo archivo y de otros archivos, incluidas las
  declaraciones dentro de ramas `#if`.
- Sin el plugin de validación de build no se garantiza la prohibición en todas
  las extensiones, porque las macros adjuntas no pueden inspeccionar de forma
  fiable las extensiones hermanas.

## Limites de generated qualifiers y bridges

- Adjunte `InnoDIDAGValidationPlugin` a cada target que declare containers
  InnoDI o un `@DIEnvironmentBridge` standalone.
- El full-source pass target-scoped rechaza shadows de generated qualifiers en
  declaraciones envolventes, extensiones coincidentes y otros source del mismo
  target, asi como qualifier shadows con acceso `public` o `package` visibles en
  targets de dependencias importados, que las macros adjuntas no pueden
  inspeccionar.
- Tambien rechaza `@DIEnvironmentBridge` aplicado directamente a una extension o
  declarado en un scope local standalone. Mueva el bridge target al scope de
  archivo o nominal.
- Para un bridge de clase o un generated site anidado en una clase, el primer
  tipo heredado debe resolverse mediante declaraciones y typealiases visibles
  como source. Como este pass es un indice sintactico conservador y no el type
  checker semantico de Swift, un primer tipo heredado que solo exista en un SDK
  o binario, no se resuelva o sea ambiguo falla con
  `generated-qualifier.inheritance-unverifiable`.
- La cadena de superclases visible como source se inspecciona para detectar
  qualifier shadows. La generacion del bridge rechaza type members heredados
  llamados `Swift` o `SwiftUI`, pero un `InnoDISwiftUI` heredado es seguro. Las
  declaraciones directas y envolventes `InnoDISwiftUI` siguen reservadas.

## Matching Strategy

- `InnoDIMacros`, `InnoDICore` y el graph CLI comparten el mismo modelo nominal cuando es posible.
- Se soportan rutas anidadas como `Outer.Container`.
- Se excluyen extensiones con argumentos genéricos y extensiones con `where`.
- Los casos ambiguos quedan fuera de la regla semántica.

## Declaration Order

- `@Input` siempre está disponible.
- sync `.shared` puede leer inputs y shared previos.
- async `.shared` puede leer inputs, sync shared y async shared previos.
- `.transient` puede leer cualquier miembro, pero la resolución de nombres sigue siendo estricta.

## Efectos del provider

- Un provider sincrono puede consumirse desde factories sync, `async` y
  `async throws`.
- Un provider `async` requiere un consumer `async` o `async throws`.
- Un provider `async throws` requiere un consumer `async throws`.
- Los efectos no se infieren de las dependencias. El consumer debe usar
  `asyncFactory:` y, cuando corresponda, una closure `async throws`.
- `Lazy<T>` y `Provider<T>` son wrappers deferred sincronos y rechazan targets
  asincronos.

## Aislamiento y Sendability

- Los contenedores mantienen el almacenamiento generado dentro del valor del
  contenedor. InnoDI no registra dependencias en un registro global.
- `mainActor: true` aísla los accessors de dependencias, todos los
  inicializadores generados, `Overrides`, los tipos de closure `applyOverrides`
  usados por los inicializadores de conveniencia, `withOverrides`, los
  overrides de child containers y el mounting de componentes, las closures de
  operación de los cuatro overloads `withOverrides` y los helpers de feature
  root generados. Es la forma recomendada para contenedores raíz de UI.
- Con el rol component de `@DIContainerRole`, el protocolo de dependencias generado,
  `init(dependencies:_:)` y el tipo de closure de override quedan aislados con
  `@MainActor`, y el componente usa la conformidad dedicada
  `_InnoDIMainActorComponentMountable`. Los componentes normales siguen usando
  `_InnoDIComponentMountable` sin aislamiento. En 5.0, los helpers genéricos de
  mounting deben ofrecer constraints y tipos de closure separados para ambos
  marcadores.
- Mantén los valores de container/component generados y las dependencias que no
  son `Sendable` en el actor principal. Prefiere un caller `@MainActor` o un
  bloque `MainActor.run` que construya y consuma esos valores. Un `await`
  directo es adecuado cuando la operación aislada devuelve un resultado
  `Sendable`, como el resultado de una operación `withOverrides`; no permite
  transportar de forma segura un contenedor no `Sendable` fuera del actor.
- Los wrappers `Lazy<T>` y `Provider<T>` no transportan valores entre actors.
  Deben permanecer dentro del dominio de aislamiento del contenedor, salvo que
  `T` y la ruta de llamada ya sean seguros para transferirse.
- Las dependencias que no son `Sendable` deben pasar por límites explícitos del
  contenedor y quedar aisladas en la capa de la app, no ocultarse tras un
  lookup global.

## Forma de almacenamiento declarada

- Se prefiere diseño protocol-first.
- El tipo declarado de la property es la fuente de verdad: un tipo nominal
  concreto usa almacenamiento concreto y `any Protocol` usa almacenamiento
  existencial.
- La forma de almacenamiento no se selecciona mediante un flag de atributo ni
  una heurística del macro.
