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

Cada contenedor compatible genera la estructura de overrides salvo que el
usuario ya haya declarado un tipo `Overrides` anidado.

## Parámetros

- `root`: solo marca la entrada de render del grafo.
- `validateDAG`: activa la validación global del DAG y los checks locales de
  cycle y closure/`with:`; con `false` esos checks se omiten, pero las
  referencias raw-expression y la validación estructural siguen activas.
- `mainActor`: aplica `@MainActor` a la API generada del contenedor.

## See Also

- <doc:Validation>
- <doc:Provide>
