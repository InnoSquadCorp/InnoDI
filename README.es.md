# InnoDI

[English](README.md) | [한국어](README.ko.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [简体中文](README.zh-Hans.md) | [日本語](README.ja.md) | [Русский](README.ru.md)

Framework de inyeccion de dependencias basado en macros para Swift con
validacion en compilacion y build, herramientas de grafo de dependencias,
validacion de jerarquia y helpers para SwiftUI.

## Ejemplo minimo util

<!-- innodi:compile -->
```swift
import InnoDI

struct APIClient { let baseURL: String }

@DIContainer
struct AppContainer {
    @Provide(.input) var baseURL: String
    @Provide(.shared, APIClient.self, with: [\AppContainer.baseURL], concrete: true)
    var apiClient: APIClient
}

let client = AppContainer(baseURL: "https://api.example.com").apiClient
```

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
InnoDI no ofrece intencionalmente un property wrapper `@Injected` ni una API de
registro dinamico. El tradeoff es usar initializers generados explicitos,
wiring revisable y validacion mas temprana.

## Cuando elegir InnoDI

Elige InnoDI cuando el wiring de dependencias debe ser visible en code review,
validarse antes del runtime y poder inspeccionarse como un artefacto de grafo.

| Si tu prioridad es... | Prefiere... | Por que |
| --- | --- | --- |
| Validacion compile/build-time de un dependency graph de app | InnoDI, [SafeDI](https://github.com/dfed/SafeDI) o [Needle](https://github.com/uber/needle) | InnoDI mantiene la superficie del contenedor en Swift expandido por macros y agrega diagnosticos locales, checks de build-support y un CLI DAG. |
| Runtime registration, late binding o composicion tipo plugin | [Swinject](https://github.com/Swinject/Swinject) o [Factory](https://github.com/hmlongco/Factory) | Los contenedores runtime facilitan cambiar registros dinamicamente. InnoDI favorece initializers generados explicitos y validacion temprana. |
| SwiftUI previews y scoped test overrides con poca ceremonia | [Factory](https://github.com/hmlongco/Factory), [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) o InnoDI | InnoDI encaja cuando esos overrides deben estar encima de un app container validado y helpers SwiftUI generados. |
| Hierarchical feature ownership y visibilidad del grafo | InnoDI, [Needle](https://github.com/uber/needle) o [SafeDI](https://github.com/dfed/SafeDI) | InnoDI modela child containers poseidos por el parent con `@SubContainer` y renderiza ownership edges en el CLI del grafo. |
| Menor costo de adopcion en una app existente | [Factory](https://github.com/hmlongco/Factory), [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) o adopcion incremental de InnoDI | InnoDI exige definir contenedores y aceptar macro/build validation; ese costo vale mas cuando necesitas wiring revisable, overrides generados y checks de grafo. |

En la practica, InnoDI tambien puede coexistir con herramientas runtime: usa
InnoDI para el grafo validado de la aplicacion y `swift-dependencies` o
factories pequenas dentro de feature logic cuando los valores runtime
locales sean una mejor abstraccion.

El patron de capas que mejor funciona separa *construccion* (InnoDI) de
*overrides efimeros por llamada* (`swift-dependencies`). El composition root
resuelve un `DependencyKey` (por ejemplo `@Dependency(\.date)`) y pasa el
valor al contenedor como un slot `.input`; los tests lo intercambian por un
arbol de llamadas con `withDependencies { $0.date = .constant(...) }
operation:`, sin reconstruir el contenedor ni revalidar su grafo. El builder
`Overrides` a nivel de contenedor sigue siendo la herramienta adecuada para
swaps de toda la app, como un `APIClient` falso; recurre a
`swift-dependencies` solo cuando el override deba vivir el tiempo de una
unica operacion.

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
lock POSIX por capas bajo el directorio scratch de Swift Package Manager:

1. `open(O_CREAT | O_EXCL | O_RDWR)` crea un unico lock file.
2. `flock(LOCK_EX | LOCK_NB)` agrega un lock exclusivo advisory sobre el descriptor.

InnoDI detecta automaticamente el filesystem que respalda ese lock directory.
Los filesystems locales como APFS, HFS+, ext4, btrfs, xfs y tmpfs estan
soportados. Los mounts NFS, SMB/CIFS, WebDAV y filesystems tipo FUSE se
rechazan por defecto porque builds concurrentes pueden corromper la cache de
validacion compartida cuando la atomicidad del lock no es fiable.

Si tu sistema de build debe poner derived data en un volumen compartido,
apunta `--scratch-path` de SPM o la ubicacion derived-data de Xcode a un
directorio local:

```sh
swift build --scratch-path /tmp/innodi-cache
```

El plugin no crea estado de lock/cache bajo `.build/innodi-dag-validation` en
el package root; mover el scratch path tambien mueve el validation state.

Los operadores pueden omitir el fail-fast de unsafe filesystem con
`INNODI_ALLOW_UNSAFE_LOCK=1`, pero InnoDI sigue emitiendo una advertencia
auditable y el riesgo queda en ese build environment. Para diagnosticos,
pasos de recuperacion y la tabla completa de filesystems, consulta
[Lock Safety](Sources/InnoDI/InnoDI.docc/lock-safety.md).

El validador en tiempo de compilacion expone dos escapes de opt-out para
iteracion rapida o entornos con restricciones: `@DIContainer(validateDAG: false)`
por contenedor y `INNODI_DISABLE_BUILD_VALIDATION=1` para cortocircuitar todo
el plugin de build. Cada PR ejecuta
`Tools/report-validate-dag-escape-hatches.sh`, que lista cada sitio que usa
estos escapes en el step summary del workflow, de modo que el crecimiento de
los escapes queda visible sin una puerta de CI separada. El CI de produccion
debe dejar ambos sin definir.

## Privacidad

InnoDI incluye un Apple Privacy Manifest (`PrivacyInfo.xcprivacy`) con sus dos
productos en tiempo de ejecucion, `InnoDI` e `InnoDISwiftUI`. El manifiesto
declara que no hay seguimiento de usuarios, no hay dominios de seguimiento, no
hay tipos de datos recolectados y no se usan APIs de Required Reason. Las
herramientas de tiempo de compilacion (InnoDIBuildSupport, dependency-graph
CLI, plugin de macros) no se integran en las apps finales y por lo tanto no
contribuyen al manifiesto. Si integras InnoDI en una app de iOS, watchOS,
tvOS o visionOS, SwiftPM agrupa automaticamente el manifiesto y aparece en el
informe agregado de privacidad de la app.

## Instalacion

Agrega InnoDI a tu `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/InnoSquadCorp/InnoDI.git", from: "4.2.1")
]
```

Luego agrega los productos que necesites:

```swift
.target(
    name: "YourApp",
    dependencies: [
        "InnoDI"
    ]
)
```

Agrega `InnoDISwiftUI` solo si tambien necesitas los helpers de SwiftUI:

```swift
.target(
    name: "YourApp",
    dependencies: [
        "InnoDI",
        "InnoDISwiftUI"
    ]
)
```

Activa el validador DAG en build-time agregando el plugin a cada target que
declara contenedores InnoDI:

```swift
.target(
    name: "YourApp",
    dependencies: [
        "InnoDI"
    ],
    plugins: [
        .plugin(name: "InnoDIDAGValidationPlugin", package: "InnoDI")
    ]
)
```

Para equipos que hayan medido que compilar la herramienta fuente es el costo
dominante de adopcion, el paquete complementario `InnoDIValidationTools`
proporciona un plugin de validacion macOS prebuilt opcional. Adjunta el source
plugin anterior o el prebuilt plugin, nunca ambos; los hosts no soportados y el
desarrollo local de paquetes deben seguir usando el source plugin.

## Inicio rapido

<!-- innodi:compile -->
```swift
import Foundation
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

    @Provide(.shared, APIClient.self, with: [\AppContainer.baseURL])
    var apiClient: any APIClientProtocol
}

let container = AppContainer(baseURL: "https://api.example.com")
_ = container.apiClient
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
4. [Anti-Patterns](Sources/InnoDI/InnoDI.docc/AntiPatterns.md)
5. [Module-Wide Init Detection](Sources/InnoDI/InnoDI.docc/es.lproj/ModuleWideInitDetection.md)
6. [RELEASING.md](RELEASING.md)
7. [ROADMAP.md](ROADMAP.md)

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

```swift
@Provide(.shared, factory: { (service: Lazy<Service>) in
    Consumer(service: service)
}, concrete: true)
var consumer: Consumer
```

```swift
@Provide(.shared, factory: { (requests: Provider<Request>) in
    RequestLogger(requests: requests)
}, concrete: true)
var logger: RequestLogger
```

Ambos wrappers son intencionalmente non-`Sendable`.

## Nested Containers y jerarquia

`@SubContainer` modela child containers poseidos por un parent:

```swift
@SubContainer(scope: .shared, with: [\.config, \.apiClient])
var feature: FeatureContainer
```

Reglas clave:

- `scope:` es obligatorio.
- El wiring implicito por nombre solo es una convenience cuando el parent
  tiene 0 o 1 candidato `@Provide`. Si hay varios candidatos, agrega wiring
  explicito en vez de depender de errores del initializer generado.
- `with:` reenvia un subconjunto explicito con el mismo nombre u orden. Debe
  ser un arreglo literal de key paths legible por el macro; variables en
  tiempo de ejecucion o elementos calculados no estan
  soportados.
- `with: []` es un subconjunto vacio explicito y llama a `Child()`.
- `bindings:` remapea labels de input del child a otros nombres del parent.
- Elige exactamente una forma de wiring: `with:` o `bindings:`.
- El `Overrides` del parent gana tanto un slot de reemplazo completo
  (`feature`) como un closure de override del child (`featureOverrides`).

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
