# Provide

`@Provide` declara un miembro del contenedor y su estrategia de construccion.

## Declaracion

```swift
@Provide(
    _ scope: DIScope = .shared,
    _ type: Any.Type? = nil,
    with dependencies: [AnyKeyPath] = [],
    factory: Any? = nil,
    asyncFactory: Any? = nil,
    concrete: Bool = false
)
```

## Modos de construccion

- `factory`
- `asyncFactory`
- `Type.self` mas `with:`

## Reglas

- `factory` y `asyncFactory` son mutuamente excluyentes.
- `.input` no permite `factory` ni `asyncFactory`.
- `.shared` y `.transient` requieren una estrategia de construccion.
- `asyncFactory` debe ser una closure `async`.
- El almacenamiento concrete `.shared` y `.transient` requiere `concrete: true`.
- La resolucion por nombre es estricta para parametros de factory y `with:`.

## See Also

- ``Provide(_:_:with:factory:asyncFactory:concrete:)``
- ``DIScope``
- <doc:Validation>
