# Provide

`@Provide` declara un miembro del contenedor y su estrategia de construccion.

InnoDI 5.0 admite `@Provide` solo en un `var` de instancia simple, almacenado y
directo del mismo struct compatible con `@DIContainer`. Se rechazan `let`,
properties computed/observed, `lazy`, `weak`, `unowned`, `static`/`class`, usos
independientes e indirectamente anidados. El accessor generado pertenece a
InnoDI; nunca adjuntes `_InnoDIProvideAccessor` manualmente.

Tambien se rechazan property wrappers, attributes condicionales o desconocidos,
modificadores de acceso del setter como `private(set)` y attributes de global
actor personalizados. No se admite ningún attribute de nivel de propiedad
escrito en el código fuente aparte de `@Provide`, incluido `@MainActor`;
solicita el aislamiento del actor con `@DIContainer(mainActor: true)`. El
aislamiento que InnoDI genera en la declaracion del provider y su accessor es
soporte interno del compilador. Una declaracion completa de miembro `@Provide`
dentro de `#if` produce `provide.conditional-declaration-unsupported`; manten la
declaracion fuera de la condicion y bifurca dentro de la factory o la
implementacion inyectada.

Cada property admite exactamente un `@Provide`; los attributes duplicados se
rechazan con `provide.duplicate-attribute`. El tipo explicito no puede ser un
`some Protocol` opaco ni un optional implicitamente desempaquetado `T!`; migra
a `any Protocol` o a `T` / `T?`, respectivamente. Una combinacion falsificada
del accessor de soporte del compilador con otro property wrapper tambien puede
recibir diagnosticos estructurales de Swift ademas del diagnostico de uso
indebido de InnoDI.

## Declaracion

```swift
@Provide(
    _ scope: DIScope = .shared,
    _ type: Any.Type? = nil,
    with dependencies: [AnyKeyPath] = [],
    factory: Any? = nil,
    asyncFactory: Any? = nil,
    escaping: Bool = false
)
```

## Valores input y funciones escaping

Los parametros `.input` del initializer generado son valores eager del tipo
declarado `T`. Swift evalua cada argumento antes de llamar al initializer, por
lo que `try makeValue()` y `await makeValue()` siguen siendo expresiones de
argumento validas. Los tipos de funcion non-optional escritos directamente se
detectan y generan como parametros escaping. Si el tipo esta oculto tras un
typealias, declara `@Provide(.input, escaping: true)`.

`escaping:` debe ser un Bool literal y solo es valido para `.input`. Las formas
obviamente no funcionales u optional-function se rechazan con diagnosticos
estables de InnoDI. Los tipos identifier/member se aceptan de forma conservadora
porque un attached macro no puede resolver aliases arbitrarios; Swift puede
agregar su propio diagnostico si el alias no es realmente una funcion
non-optional.

## Modos de construccion

- `factory`
- `asyncFactory`
- `Type.self`, opcionalmente con `with:`
- initializer de property

## Reglas

- `factory:`, `asyncFactory:`, `Type.self` y el initializer de property son
  fuentes de construccion mutuamente excluyentes.
- `.input` no permite ninguna fuente de construccion ni `with:`.
- `.shared` y `.transient` requieren exactamente una fuente de construccion.
- `with:` solo se admite con `Type.self` y providers sincronos.
- `asyncFactory` se admite para `.shared` y `.transient`, y debe ser una
  closure `async`.
- El tipo declarado de la property determina la forma de almacenamiento: un
  tipo nominal concreto usa almacenamiento concreto y `any Protocol` usa
  almacenamiento existencial.
- La resolucion por nombre es estricta para parametros de factory y `with:`.

## Contrato de edges sibling

- Solo los parametros con nombre de la closure literal raiz de `factory:` o
  `asyncFactory:` declaran edges. Closures anidadas e identificadores
  arbitrarios no agregan edges.
- `Type.self` declara edges desde un array literal `with:`. Cada elemento debe
  usar exactamente la forma canonica de miembro directo `\Self.member`, por
  ejemplo `with: [\Self.config]`; `with: []` tambien es valido. Se rechazan roots
  de contenedor con nombre, de modulo o de typealias, componentes anidados,
  optional chaining, subscripts y elementos calculados. Todos los targets deben
  usar construccion sincrona.
- Factories que no son closures e initializers de property son fuentes opacas
  de cero edges y no pueden referenciar miembros sibling. Usa parametros de la
  closure raiz o un simbolo global/estatico calificado.

## Compatibilidad de efectos del provider

Los efectos de factory son explicitos y no se infieren de las dependencias.
Usa `asyncFactory:` para un consumer asincrono y declara la closure como
`async throws` cuando consuma un provider asincrono que pueda lanzar errores.
La compatibilidad tambien se valida con `validateDAG: false`.

| Provider | consumer sync | consumer `async` | consumer `async throws` |
|---|---:|---:|---:|
| sync | permitido | permitido | permitido |
| `async` | rechazado | permitido | permitido |
| `async throws` | rechazado | rechazado | permitido |

`Lazy<T>` y `Provider<T>` siguen siendo wrappers deferred sincronos. Ambos
rechazan targets construidos mediante `asyncFactory:`.

## See Also

- ``Provide(_:_:with:initialization:factory:asyncFactory:escaping:)``
- ``DIScope``
- <doc:Validation>
