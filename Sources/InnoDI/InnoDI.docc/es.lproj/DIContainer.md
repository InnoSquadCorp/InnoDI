# DIContainer

`@DIContainer` marca un struct compatible y efectivamente no generico como
contenedor InnoDI y sintetiza la superficie del contenedor.

`@DIContainer` solo admite declaraciones `struct` efectivamente no genericas
en el alcance de archivo o anidadas nominalmente. Ni la propia declaracion ni
ninguna declaracion envolvente puede tener parametros genericos o una clausula
`where`. Se rechazan `class`, `actor`, `enum`, `protocol`, las `extension`
anotadas directamente y los structs anidados en extensiones. Tambien se
rechaza cualquier declaracion en un alcance ejecutable o local, incluidas
funciones, closures, accessors y casos de `switch`. El mismo limite se aplica
al combinar `@DIComponent`.
Mueve el estado de runtime o especifico del tipo detras de dependencias de
protocolo o `@Provide(.input)`.

Tambien se rechaza un contenedor declarado explicitamente `private`, porque
los contenedores hermanos no pueden acceder a su superficie de montaje
generada. Use `fileprivate` para montaje local al archivo o un contenedor con
acceso predeterminado dentro de un namespace privado.

El compilador Swift actual omite el contexto del accessor al expandir un
attached macro sobre un tipo dentro del body de una computed property. El
plugin de build validation y el CLI del dependency graph escanean el source
completo y rechazan tambien este caso limite. Conecta el plugin a cada target
que declare contenedores.

## Declaración

```swift
@DIContainer(root: Bool = false, validateDAG: Bool = true, mainActor: Bool = false)
```

## Superficie generada

`@DIContainer` sintetiza:

- un `init(...)` principal
- un tipo `Overrides` anidado
- un `init(<inputs...>, _ applyOverrides: ...)` de conveniencia
- cuatro overloads `withOverrides`

En un contenedor sin `mainActor: true`, los métodos `withOverrides` generados
con `async` o `async throws` y los tipos de sus closures de operación son
`nonisolated(nonsending)`. Conservan el executor del actor del caller, por lo
que valores arbitrarios de contenedor y closure que no son `Sendable` no cruzan
un límite de aislamiento. Los overloads síncronos no cambian. Con
`mainActor: true`, todos los overloads `withOverrides` y sus closures de
operación permanecen `@MainActor`.

Cada contenedor, incluso sin miembros administrados, genera toda la estructura
de overrides. Un tipo `Overrides` anidado declarado por el usuario no es
compatible con InnoDI 5.0 y emite `container.overrides-name-conflict`; cambie
su nombre para que la macro sea duena de la ABI de overrides montable.

La macro tambien genera el alias reservado de soporte del compilador
`_InnoDIMountOverrides = Overrides` para el codigo de montaje del contenedor
padre. No declare ni use directamente ese nombre con guion bajo.

Cada miembro de instancia almacenado debe usar `@Provide` o `@SubContainer`;
las propiedades calculadas y de tipo siguen disponibles. Asi el inicializador
sintetizado posee todo el estado y evita cambios en la ABI del inicializador
memberwise.

Cada `@Provide` debe ser un `var` de instancia simple, almacenado y directo de
este struct. Se rechazan accessors/observers, `let`, `lazy`, `weak`, `unowned`,
`static`/`class`, providers independientes o indirectamente anidados; los
accessors generados no se adjuntan manualmente.

Los edges sibling solo vienen de parametros con nombre de closures literales
raiz `factory:`/`asyncFactory:`, o de `Type.self` con key paths literales en
`with:`. Factories que no son closures e initializers de property son fuentes
opacas con cero edges y no pueden leer miembros sibling. La compatibilidad de
efectos sigue siendo obligatoria con `validateDAG: false`.

## Parámetros

- `root`: solo marca la entrada de render del grafo.
- `validateDAG`: activa el DAG global y los checks graph-derived locales; con
  `false` se omiten el DAG global y los ciclos locales, pero siguen la
  validación de declaraciones y la compatibilidad de efectos de edges sibling
  explícitos.
- `mainActor`: aísla con `@MainActor` los accessors de dependencias, todos los
  inicializadores generados, `Overrides`, los tipos de closure `applyOverrides`
  usados por los inicializadores de conveniencia, `withOverrides`, los
  overrides de child containers y el mounting de componentes, las closures de
  operación de los cuatro overloads `withOverrides` y los helpers de feature
  root. Con `@DIComponent`, el protocolo `<Container>Dependencies` y
  `init(dependencies:_:)` generados reciben el mismo aislamiento, y el
  componente usa la conformidad dedicada `_InnoDIMainActorComponentMountable`.
  Los componentes sin esta opción siguen usando `_InnoDIComponentMountable`.
  Mantén los valores generados que no son `Sendable` en el actor principal con
  un caller `@MainActor` o construyéndolos y consumiéndolos dentro del mismo
  bloque `MainActor.run`. Un `await` directo es adecuado para una operación
  aislada que devuelve un resultado `Sendable`, no para transportar el
  contenedor fuera del actor.

## See Also

- <doc:Validation>
- <doc:Provide>
