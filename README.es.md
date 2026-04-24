# InnoDI

[English](README.md) | [한국어](README.ko.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [简体中文](README.zh-Hans.md) | [日本語](README.ja.md) | [Русский](README.ru.md)

Framework de inyeccion de dependencias basado en macros para Swift con
validacion en compilacion y build, herramientas de grafo de dependencias,
validacion de jerarquia y helpers para SwiftUI.

## Por que InnoDI

InnoDI esta pensado para equipos que quieren mantener el wiring de DI
explicito y revisable, detectando fallos lo antes posible.

- `@DIContainer` y `@Provide` generan APIs de contenedor desde tipos Swift normales.
- La validacion de macros detecta errores locales durante la expansion.
- La validacion de build y el CLI del grafo detectan problemas cross-file,
  cross-module y de grafo global.
- `InnoDISwiftUI` reduce el wiring repetitivo del environment en el borde raiz.

InnoDI no es una state machine en runtime. El estado en runtime debe vivir en
la capa de la app o en frameworks companeros como `InnoFlow`, `InnoRouter` e
`InnoNetwork`.

## Requisitos

- Swift tools version `6.2`
- Plataformas:
  - iOS 17+
  - macOS 13+
  - watchOS 10+
  - tvOS 17+
  - visionOS 1+

### Requisitos de filesystem para el validador de build

El plugin de build serializa las ejecuciones live de validacion DAG con un
lock file POSIX `O_CREAT | O_EXCL` bajo el directorio derived data de Swift
Package Manager. Esto funciona correctamente en filesystems locales como
APFS, HFS+, ext4, btrfs y xfs, pero los paths respaldados por red tienen
matices importantes.

- **NFSv3** no garantiza semantica atomica de `O_EXCL`; dos clientes pueden
  creer que crearon el lock. Usa NFSv4 o mueve derived data a un path local.
- **SMB/CIFS** no ofrece atomicidad `O_EXCL` fiable y no esta soportado.
- **Docker / Kubernetes bind mounts** heredan la semantica del filesystem
  host. Si el host es local, son seguros.

Si tu sistema de build debe poner derived data en un volumen compartido,
apunta `--scratch-path` de SPM o la ubicacion derived-data de Xcode a un
directorio local antes de habilitar el plugin.

## Instalacion

Agrega InnoDI a tu `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/InnoSquadCorp/InnoDI.git", from: "4.0.0")
]
```

Luego agrega los productos que necesites:

```swift
.target(
    name: "YourApp",
    dependencies: [
        "InnoDI",
        "InnoDISwiftUI"
    ]
)
```

Importa solo `InnoDI` si no usas los helpers de SwiftUI.

## Inicio rapido

```swift
import InnoDI

protocol APIClientProtocol {
    func fetch() async throws -> Data
}

struct APIClient: APIClientProtocol {
    let baseURL: String
    func fetch() async throws -> Data { Data() }
}

@DIContainer
struct AppContainer {
    @Provide(.input)
    var baseURL: String

    @Provide(.shared, APIClient.self, with: [\.baseURL])
    var apiClient: any APIClientProtocol
}

let container = AppContainer(baseURL: "https://api.example.com")
let client = container.apiClient
```

Usa una factory closure cuando los nombres o la logica de construccion no
coincidan con `Type.self` mas `with:`:

```swift
@Provide(.shared, factory: { (baseURL: String) in
    APIClient(baseURL: baseURL)
})
var apiClient: any APIClientProtocol
```

## Leer a continuacion

Empieza por estos documentos en este orden:

1. [Overview](Sources/InnoDI/InnoDI.docc/es.lproj/Overview.md)
2. [Validation](Sources/InnoDI/InnoDI.docc/es.lproj/Validation.md)
3. [Policy Boundaries](Sources/InnoDI/InnoDI.docc/es.lproj/PolicyBoundaries.md)
4. [Module-Wide Init Detection](Sources/InnoDI/InnoDI.docc/es.lproj/ModuleWideInitDetection.md)
5. [RELEASING.md](RELEASING.md)
6. [ROADMAP.md](ROADMAP.md)

## API principal

### `@DIContainer`

`@DIContainer` sintetiza:

1. Un `init(...)` principal con parametros `.input` obligatorios y overrides
   opcionales para miembros `.shared`, `.transient` y `@SubContainer`.
2. Un tipo `Overrides` anidado.
3. Un `init(<inputs...>, _ applyOverrides: (inout Overrides) -> Void)` de conveniencia.
4. Cuatro overloads de `withOverrides` para operaciones `sync`, `throws`,
   `async` y `async throws`.

Todos los contenedores sintetizan la estructura de overrides salvo que el
usuario ya declare un tipo `Overrides` anidado, lo cual suprime la generacion.

```swift
@DIContainer(root: Bool = false, validateDAG: Bool = true, mainActor: Bool = false)
```

| Parametro | Default | Significado |
|---|---|---|
| `root` | `false` | Solo marca la entrada de render del grafo. Si existe al menos una raiz, la salida Mermaid, DOT y ASCII se reduce a la union de nodos y aristas alcanzables desde esas raices. |
| `validateDAG` | `true` | Activa la validacion global del DAG mas los checks graph-derived de ciclo local y closure/`with:`. Con `false` se omiten esos checks, pero las referencias raw-expression en `factory:` e inicializadores siguen diagnosticandose y la validacion estructural continua. |
| `mainActor` | `false` | Aplica aislamiento `@MainActor` a la API generada del contenedor. Recomendado para contenedores raiz de UI. |

`@DIContainer` no permite declaraciones `init` definidas por el usuario en el
tipo anotado ni en extensiones equivalentes.

### `@Provide` y scopes

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

| Scope | Significado | Reglas de construccion |
|---|---|---|
| `.input` | Dependencia externa suministrada al inicializar el contenedor | Sin `factory` ni `asyncFactory` |
| `.shared` | Se crea una vez por instancia del contenedor y se reutiliza | Requiere `factory`, `asyncFactory` o `Type.self` mas `with:` |
| `.transient` | Se recrea en cada acceso | Requiere `factory`, `asyncFactory` o `Type.self` mas `with:` |

Reglas adicionales:

- `factory` y `asyncFactory` son mutuamente excluyentes.
- `asyncFactory` debe ser una closure `async`.
- El almacenamiento concrete `.shared` y `.transient` requiere `concrete: true`.
- La resolucion de nombres para parametros de factory y wiring con `with:` es estricta por nombre de miembro.

## Modelo de validacion

InnoDI valida contenedores en capas:

1. Validacion de macros
2. Validacion de build
3. Validacion global del DAG

`validateDAG: false` es un opt-out intencionalmente estrecho. Excluye la
validacion global del DAG y los checks graph-derived de ciclo local y
closure/`with:` de la macro. No desactiva la validacion estructural ni suprime
los diagnosticos de referencias raw-expression en `factory:` o inicializadores.

## Overrides Builder

El builder `Overrides` generado permite cambiar solo los miembros que una
prueba necesita.

```swift
let container = AppContainer(baseURL: "https://test.example.com") { overrides in
    overrides.apiClient = MockAPIClient()
}
```

O limitar el override a una sola operacion:

```swift
let result = try await AppContainer.withOverrides(baseURL: "https://test.example.com") { overrides in
    overrides.apiClient = MockAPIClient()
} operation: { container in
    try await container.apiClient.fetch()
}
```

Puntos importantes:

- Los contenedores solo con `.input` tambien sintetizan un builder vacio.
- Si un child container es solo de input, los closures `<name>Overrides`
  compilan y se ejecutan como no-op hasta que el child tenga miembros overrideables.

## `Lazy<T>` y `Provider<T>`

Usa `Lazy<T>` cuando una factory necesita una referencia diferida que debe
quedar fuera de la deteccion de ciclos.

Usa `Provider<T>` cuando una factory necesita reingresar a una dependencia
`.transient` en cada llamada.

Ambos wrappers son intencionalmente non-`Sendable`.

## Nested Containers y jerarquia

`@SubContainer` modela child containers poseidos por un parent.

- `scope:` es obligatorio.
- El wiring implicito por nombre solo es una convenience cuando el parent
  tiene 0 o 1 candidato `@Provide`.
- Si hay varios candidatos, usa `with:`, `withNames:` o `bindings:`.
- `with:` o `withNames:` reenvia un subconjunto explicito con el mismo nombre.
- `bindings:` remapea labels de input del child a otros nombres del parent.
- El `Overrides` del parent gana tanto el reemplazo completo como el closure de override del child.

Para ownership cross-module:

- `@DIComponent` marca children montables
- `@DIHierarchyRoot` habilita validacion de jerarquia a nivel workspace

## Helpers de SwiftUI

`InnoDISwiftUI` agrega una capa pequena de integracion con SwiftUI:

- `.innodi(container)` aplica el environment bridge generado a un arbol de vistas.
- `@DIEnvironmentBridge` mapea miembros del contenedor a environment keys.
- `@DIFeatureRoot` genera helpers default o con nombre para feature roots.

## CLI y superficie de release

Renderizar el grafo:

```bash
swift run InnoDI-DependencyGraph --root .
```

Validar el DAG global:

```bash
swift run InnoDI-DependencyGraph --root . --validate-dag
```

Generar DocC:

```bash
Tools/generate-docc.sh
```

Las notas de release y de upgrade viven en [RELEASING.md](RELEASING.md).

## Ejemplos

- [Examples/README.md](Examples/README.md)
- [Examples/SwiftUIExample](Examples/SwiftUIExample)
- [Examples/PreviewInjectionExample](Examples/PreviewInjectionExample)
- [Sources/InnoDIExamples/main.swift](Sources/InnoDIExamples/main.swift)
