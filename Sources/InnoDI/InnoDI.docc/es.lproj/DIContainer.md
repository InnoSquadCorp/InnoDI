# DIContainer

`@DIContainer` marca un tipo como contenedor InnoDI y sintetiza la superficie
del contenedor.

## Declaracion

```swift
@DIContainer(root: Bool = false, validateDAG: Bool = true, mainActor: Bool = false)
```

## Superficie generada

`@DIContainer` sintetiza:

- un `init(...)` principal
- un tipo `Overrides` anidado
- un `init(<inputs...>, _ applyOverrides: ...)` de conveniencia
- cuatro overloads `withOverrides`

Todos los contenedores generan la estructura de overrides salvo que el usuario
ya haya declarado un tipo `Overrides` anidado.

## Parametros

- `root`: solo marca la entrada de render del grafo.
- `validateDAG`: activa la validacion global del DAG y los checks locales de
  cycle y closure/`with:`; con `false` esos checks se omiten, pero las
  referencias raw-expression y la validacion estructural siguen activas.
- `mainActor`: aplica `@MainActor` a la API generada del contenedor.

## See Also

- <doc:Validation>
- <doc:Provide>
