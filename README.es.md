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
    @Input var baseURL: String
    @Provide(.shared, APIClient.self, with: [\Self.baseURL])
    var apiClient: APIClient
}

let client = AppContainer(baseURL: "https://api.example.com").apiClient
```

Los servicios compartidos costosos pueden construirse bajo demanda en el
primer acceso:

```swift
@Provide(.shared, initialization: .onDemand, factory: MetricsClient())
var metrics: MetricsClient
```

## Por que InnoDI

InnoDI esta pensado para equipos que quieren mantener el wiring de DI
explicito y revisable, detectando fallos lo antes posible.

- `@DIContainer` y `@Provide` generan APIs de contenedor desde structs Swift compatibles y efectivamente no genericos.
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
valor al contenedor como un slot `@Input`; los tests lo intercambian por un
arbol de llamadas con `withDependencies { $0.date = .constant(...) }
operation:`, sin reconstruir el contenedor ni revalidar su grafo. El builder
`Overrides` a nivel de contenedor sigue siendo la herramienta adecuada para
swaps de toda la app, como un `APIClient` falso; recurre a
`swift-dependencies` solo cuando el override deba vivir el tiempo de una
unica operacion.

## Requisitos

- Swift tools version `6.2` (CI valida Swift 6.2 y 6.3)
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
    .package(url: "https://github.com/InnoSquadCorp/InnoDI.git", from: "5.1.0")
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
declara contenedores InnoDI o un `@DIEnvironmentBridge` standalone. El
full-source pass target-scoped rechaza shadows de generated qualifiers en
declaraciones envolventes o en el mismo target, asi como qualifier shadows con
acceso `public` o `package` visibles en targets de dependencias importados, que
las macros adjuntas no pueden inspeccionar. Tambien rechaza direct-extension
attachments y bridge targets locales standalone antes de la compilacion de Swift:

Cuando un generated site es una class o esta anidado dentro de una class, el
primer inherited type —la posicion que puede nombrar su superclass— debe poder
resolverse mediante declarations y typealiases visibles en source. Un primer
inherited type disponible solo en el SDK o en un binary, no resuelto o ambiguo,
falla de forma cerrada con `generated-qualifier.inheritance-unverifiable`.
Mueve el generated site a un struct / enum o a un adapter visible en source, o
haz que la superclass chain este disponible para el source snapshot
target-scoped. Este preflight es un indice sintactico conservador, no un
reemplazo del type checker de Swift.

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

Desde 5.1, el mismo product tambien implementa la API nativa de build-tool
plugins de Xcode. Los proyectos Xcode nativos y los generados por Tuist pueden
adjuntar el package plugin directamente a cada container target. En un
workspace Tuist, el plugin detecta el workspace root y valida todos los sources
Swift de produccion para incluir referencias cross-project en el source DAG.

La API de plugins de Xcode no expone la topologia completa de dependencias entre
targets de Tuist. Por eso, el fallback de 5.1 conserva el full-source DAG y la
validacion de declarations, pero Xcode por si solo no puede demostrar todas las
reglas de module-edge hierarchy. Mantenga un check topology-aware en SwiftPM o
CI cuando las relaciones de modulo `@DIContainerRole(role: ContainerRole.component)` / `@DIContainerRole(role: ContainerRole.root)` sean un
release gate. Las variantes multi-destination comparten el plugin work
directory, por lo que no se declaran output files y Xcode puede indicar que el
validation command se ejecuta en cada build.

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
    @Input
    var baseURL: String

    @Provide(.shared, APIClient.self, with: [\Self.baseURL])
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

1. Un `init(...)` principal con parametros `@Input` obligatorios y overrides
   opcionales para miembros `.shared`, `.transient` y `@SubContainer`.
2. Un tipo `Overrides` anidado.
3. Un `init(<inputs...>, _ applyOverrides: (inout Overrides) -> Void)` de conveniencia.
4. Cuatro overloads de `withOverrides` para operaciones `sync`, `throws`,
   `async` y `async throws`.

Cada contenedor, incluso si no tiene miembros administrados, sintetiza toda la
estructura de overrides. Un tipo `Overrides` anidado declarado por el usuario
no es compatible con InnoDI 6.0 y emite
`container.overrides-name-conflict`; cambie su nombre para que la macro sea
duena de la ABI de overrides montable.

La macro tambien genera el alias reservado de soporte del compilador
`_InnoDIMountOverrides = Overrides` para el codigo de montaje del contenedor
padre. No declare ni use directamente ese nombre con guion bajo.

Cada miembro de instancia almacenado del contenedor debe usar `@Provide` o
`@SubContainer`; las propiedades calculadas y estaticas siguen disponibles.
Asi el inicializador generado posee todo el estado y no cambia silenciosamente
la ABI del inicializador memberwise.

`@DIContainer` solo admite declaraciones `struct` efectivamente no genericas
en el alcance de archivo o anidadas nominalmente. Ni la propia declaracion ni
ninguna declaracion envolvente puede tener parametros genericos o una clausula
`where`. Se rechazan `class`, `actor`, `enum`, `protocol`, las `extension`
anotadas directamente y los structs anidados en extensiones. Tambien se
rechaza cualquier declaracion en un alcance ejecutable o local, incluidas
funciones, closures, accessors y casos de `switch`. El mismo limite se aplica
al combinar `@DIContainerRole(role: ContainerRole.component)`.
Mueve el estado de runtime o especifico del tipo detras de dependencias de
protocolo o `@Input`.

Tambien se rechaza un contenedor declarado explicitamente `private`, porque
los contenedores hermanos no pueden acceder a su superficie de montaje
generada. Use `fileprivate` para montaje local al archivo o un contenedor con
acceso predeterminado dentro de un namespace privado.

El compilador Swift actual omite el contexto del accessor al expandir un
attached macro sobre un tipo dentro del body de una computed property. El
plugin de build validation y el CLI del dependency graph escanean el source
completo y rechazan tambien este caso limite. Conecta el plugin a cada target
que declare contenedores.

```swift
@DIContainer(validateDAG: Bool = true)
@DIContainerRole(role: String, mainActor: Bool = false, validateDAG: Bool = true)
```

| Parametro | Default | Significado |
|---|---|---|
| `role` | obligatorio en `@DIContainerRole` | `ContainerRole.local`, `.component` o `.root`. El rol root define el inicio de alcance del grafo; el rol component define el contrato de montaje entre módulos. |
| `validateDAG` | `true` | Activa la validacion global del DAG y los checks graph-derived locales. Con `false` se omiten el DAG global y los ciclos locales, pero siguen la validacion de declaraciones y la compatibilidad de efectos en edges sibling explicitos. |
| `mainActor` | `false` | Aplica `@MainActor` a los accessors de dependencias, todos los inicializadores generados, `Overrides`, los tipos de closure `applyOverrides` usados por los inicializadores de conveniencia, `withOverrides`, los overrides de child containers y el mounting de componentes, las closures de operación de los cuatro overloads `withOverrides` y los helpers de feature root. Con `@DIContainerRole(role: ContainerRole.component)`, también aísla el protocolo `<Container>Dependencies` y `init(dependencies:_:)` generados, y usa la conformidad dedicada `_InnoDIMainActorComponentMountable`. Los componentes sin esta opción siguen usando `_InnoDIComponentMountable`. El uso fuera del actor principal requiere un salto explícito. Recomendado para contenedores raíz de UI. |

En 6.0, los helpers genéricos de mounting deben distinguir ambos protocolos
marcadores. Conserva `_InnoDIComponentMountable` para componentes normales y,
para componentes con `mainActor: true`, añade un overload `@MainActor` con el
constraint `_InnoDIMainActorComponentMountable` y una closure de override
`@MainActor`.

Mantén los valores de container/component que no son `Sendable` en el actor
principal mediante un caller `@MainActor` o construyéndolos y consumiéndolos en
el mismo bloque `MainActor.run`. Un `await` directo es adecuado para una
operación aislada que devuelve un resultado `Sendable`, como una operación
`withOverrides`, no para transportar el contenedor fuera del actor.

`@DIContainer` no permite declaraciones `init` definidas por el usuario en el
tipo anotado ni en extensiones equivalentes.

### `@Provide` y scopes

InnoDI 6.0 admite `@Provide` solo en un `var` de instancia simple, almacenado y
directo del mismo struct compatible que lleva `@DIContainer`. Se rechazan
`let`, properties computed u observed, `lazy`, `weak`, `unowned`,
`static`/`class`, usos independientes e indirectamente anidados. InnoDI es
propietario del accessor generado; nunca adjuntes `_InnoDIProvideAccessor`
manualmente.

Los attributes y el access control de la declaracion del provider tambien
forman un contrato cerrado. Se rechazan los property wrappers, los attributes
condicionales o desconocidos, los modificadores de acceso del setter como
`private(set)` y los attributes de global actor personalizados. No se admite
ningún attribute de nivel de propiedad escrito en el código fuente aparte de
`@Provide`, incluido `@MainActor`; solicita el aislamiento del actor con
`@DIContainerRole(role: ContainerRole.local, mainActor: true)`. Los attributes de aislamiento que InnoDI
genera en la declaracion del provider y su accessor son soporte interno del
compilador. Una declaracion completa de miembro `@Provide` dentro de `#if`
tambien se rechaza con
`provide.conditional-declaration-unsupported`; manten la declaracion fuera de
la condicion y bifurca dentro de su factory o implementacion inyectada.

Cada property admite exactamente un `@Provide`; los attributes duplicados se
rechazan con `provide.duplicate-attribute`. Las direct provider properties y
los dependency parameters del root factory closure deben tener effective names
unicos dentro de cada grupo; las identidades duplicadas se rechazan antes de
generar lookup o storage code. Ambos tipos de declaracion deben usar identifiers
sin escape; 5.0 rechaza nombres de property o factory parameter entre backticks.
Los nombres de property `@SubContainer` tambien deben estar sin escape porque
de ellos se derivan el child storage, los overrides y las identidades de los
root helpers.

Las declaraciones generadas de storage/support reservan `_storage_`,
`_override_`, `_innoDI` y `_InnoDI`; tambien se reserva el nombre directo exacto
`InnoDI`. `Swift`, `_Concurrency` y los anchors del bridge de SwiftUI se reservan
en el type namespace visible para el attached macro. Consulta la matriz exacta
de 5.0 en la [Migration Guide](Sources/InnoDI/InnoDI.docc/MigrationGuide.md). El
full-source pass target-scoped rechaza declaraciones del enclosing scope o del
mismo target, y declaraciones visibles `public` / `package` de dependency
targets importados, cuando ocultan un generated qualifier que el attached macro
no puede ver.
Para un class bridge o una class envolvente, el scan tambien sigue una
superclass chain visible en source. Los type members heredados llamados `Swift`
o `SwiftUI` se rechazan, mientras que un member `InnoDISwiftUI` heredado es
seguro. Una declaracion `InnoDISwiftUI` visible de forma directa o lexical sigue
reservada. Como este es un indice sintactico conservador, un primer inherited
type disponible solo en el SDK o en un binary, no resuelto o ambiguo, falla de
forma cerrada con `generated-qualifier.inheritance-unverifiable` en vez de
asumir que la superclass no contiene shadows.

El tipo explicito de la property no puede ser un `some Protocol` opaco ni un
optional implicitamente desempaquetado `T!`; migra a `any Protocol` o a `T` /
`T?`, respectivamente. Una combinacion
deliberadamente falsificada del accessor de soporte del compilador con otro
property wrapper tambien puede recibir diagnosticos estructurales de Swift,
ademas del diagnostico de uso indebido de InnoDI.

Para generar un inventario de migracion legible por maquinas antes de escribir,
ejecuta `swift run InnoDI-Migrate --root . --report --output migration-report.json`.
El reporte schema-v1 contiene rutas y diagnosticos, nunca cuerpos de source, y
usa los codigos de salida `0` (clean), `1` (cambios requeridos) y `2` (blocked).

```swift
@Provide(
    _ scope: DIScope = .shared,
    _ type: Any.Type? = nil,
    with dependencies: [AnyKeyPath] = [],
    initialization: DIInitialization = .eager,
    factory: Any? = nil,
    asyncFactory: Any? = nil
)
```

| Scope | Significado | Reglas de construccion |
|---|---|---|
| `@Input` | Dependencia externa suministrada al inicializar el contenedor | No declara `factory:`, `asyncFactory:`, `Type.self`, initializer de property ni `with:` |
| `.shared` | Se crea una vez por instancia del contenedor y se reutiliza | Declara exactamente uno de `factory:`, `asyncFactory:`, `Type.self` o initializer de property |
| `.transient` | Se recrea en cada acceso | Declara exactamente uno de `factory:`, `asyncFactory:`, `Type.self` o initializer de property |

Reglas adicionales:

- En `.shared` / `.transient`, `factory:`, `asyncFactory:`, `Type.self` y el
  initializer de property son cuatro fuentes de construccion mutuamente
  excluyentes.
- `@Input` rechaza todas las fuentes de construccion y `with:`.
- Los parametros `@Input` del initializer generado son valores eager del tipo
  declarado `T`; Swift evalua expresiones de argumento `try` / `await` antes de
  llamar al initializer, como siempre. Los tipos de funcion non-optional
  escritos directamente se detectan y se generan como parametros escaping.
  Si un tipo de funcion non-optional esta oculto tras un typealias, usa
  `@Input(escaping: true)`. `escaping:` debe ser un Bool literal y
  solo es valido para `@Input`. Se rechazan formas obviamente no funcionales u
  optional-function; si un alias identifier/member aceptado conservadoramente
  no se resuelve realmente como funcion non-optional, Swift puede emitir su
  propio diagnostico.
- `asyncFactory` se admite para `.shared` y `.transient` y debe ser una closure
  `async`.
- `with:` solo se admite con la construccion `Type.self`. Cada elemento del
  array literal debe usar exactamente la forma canonica de miembro directo
  `\Self.member`, por ejemplo `with: [\Self.config]`; `with: []` tambien es
  valido. Se rechazan roots de contenedor con nombre, de modulo o de typealias,
  ademas de componentes anidados, optional chaining, subscripts y elementos
  calculados. Todos los providers referenciados deben tener construccion sincrona.
- El tipo declarado de la property determina la forma de almacenamiento: un
  tipo nominal concreto usa almacenamiento concreto y `any Protocol` usa
  almacenamiento existencial.
- La resolucion de nombres para parametros de factory y wiring con `with:` es estricta por nombre de miembro.

Los edges DI entre miembros sibling usan una sintaxis cerrada:

- Una closure literal raiz de `factory:` o `asyncFactory:` declara un edge por
  cada parametro con nombre. Las closures anidadas y los identificadores
  arbitrarios no agregan edges.
- La construccion `Type.self` declara edges desde su array literal de key paths
  canonicos `\Self.member` y solo puede apuntar a providers sincronos.
- Una expresion `factory:` que no sea closure o un initializer de property es
  una fuente de construccion opaca con cero edges y no puede referenciar otros
  miembros del contenedor. Usa parametros de la closure raiz para DI, o un
  simbolo global/estatico calificado cuando no se pretenda un edge DI.

Los efectos de factory son explicitos y no se infieren de las dependencias.
Usa `asyncFactory:` para un consumer asincrono y declara la closure como
`async throws` cuando consuma un provider asincrono que pueda lanzar errores.
La compatibilidad se valida en cada edge explicito incluso con
`validateDAG: false`.

| Provider | consumer sync | consumer `async` | consumer `async throws` |
|---|---:|---:|---:|
| sync | permitido | permitido | permitido |
| `async` | rechazado | permitido | permitido |
| `async throws` | rechazado | rechazado | permitido |

`Lazy<T>` y `Provider<T>` son wrappers deferred sincronos. Rechazan targets
asincronos.

## Modelo de validacion

InnoDI valida contenedores en capas:

1. Validacion de macros
2. Validacion de build
3. Validacion global del DAG

`validateDAG: false` es un opt-out intencionalmente estrecho. Excluye el DAG
global y los checks graph-derived de ciclo local, pero no la validacion de
declaraciones ni la compatibilidad de efectos en edges sibling explicitos de
closures raiz o `with:`.

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

- Los contenedores solo con `@Input` tambien sintetizan un builder vacio.
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
})
var consumer: Consumer
```

```swift
@Provide(.shared, factory: { (requests: Provider<Request>) in
    RequestLogger(requests: requests)
})
var logger: RequestLogger
```

Ambos wrappers son intencionalmente non-`Sendable`. Tambien permanecen
sincronos y no pueden apuntar a un miembro `asyncFactory`.

## Nested Containers y jerarquia

`@SubContainer` modela child containers poseidos por un parent:

```swift
@SubContainer(
    scope: .shared,
    with: [\.config, \.apiClient],
    featureRoot: FeatureRootScene.self
)
var feature: FeatureContainer
```

Reglas clave:

- `scope:` es obligatorio.
- Declara exactamente un `@SubContainer` en una `var` de instancia directa,
  simple y almacenada del parent `@DIContainer` compatible, fuera de `#if`.
  No se admiten wrappers, modificadores de storage/accessor, attributes
  desconocidos ni adjuntar manualmente
  `InnoDI._InnoDISubContainerAccessor`.
- El wiring implicito por nombre solo es una convenience cuando el parent
  tiene 0 o 1 candidato `@Provide`. Si hay varios candidatos, agrega wiring
  explicito en vez de depender de errores del initializer generado.
- `with:` reenvia un subconjunto explicito con el mismo nombre u orden. Debe
  ser un arreglo literal de key paths legible por el macro; variables en
  tiempo de ejecucion o elementos calculados no estan
  soportados.
- `with: []` es un subconjunto vacio explicito y llama a `Child()`.
- `bindings:` remapea labels de input del child a otros nombres del parent.
- `featureRoot:` / `featureRoots:` generan helpers de raiz SwiftUI en el parent
  container sin apilar otro peer macro sobre la misma property.
- Elige exactamente una forma de wiring: `with:` o `bindings:`.
- El `Overrides` del parent gana tanto un slot de reemplazo completo
  (`feature`) como un closure de override del child (`featureOverrides`).

Para ownership cross-module:

- `@DIContainerRole(role: ContainerRole.component)` marca children montables
- `@DIContainerRole(role: ContainerRole.root)` habilita validacion de jerarquia a nivel workspace

## Helpers de SwiftUI

`InnoDISwiftUI` agrega una capa pequena de integracion con SwiftUI:

- `.innodi(container)` aplica el environment bridge generado a un arbol de vistas.
- `@DIEnvironmentBridge` mapea miembros del contenedor a environment keys.
- `@SubContainer(..., featureRoot:)` y `featureRoots:` generan helpers de
  feature root predeterminados o con nombre.
- InnoDI 5.0 elimina el macro de compatibilidad obsoleto `@DIFeatureRoot`.
  Sustituyelo por los argumentos de feature root de `@SubContainer`.

## CLI y superficie de release

Renderizar el grafo:

```bash
swift run InnoDI-DependencyGraph --root . --root-pruning all
```

Validar el DAG global:

```bash
swift run InnoDI-DependencyGraph --root . --validate-dag
```

Explicar la inclusion, inspeccionar dependientes y buscar contenedores fuera
de todas las raices explicitas:

```bash
swift run InnoDI-DependencyGraph --root . --why FeatureContainer
swift run InnoDI-DependencyGraph --root . --dependents NetworkContainer
swift run InnoDI-DependencyGraph --root . --unused
```

Comparar dos artefactos JSON del grafo:

```bash
swift run InnoDI-DependencyGraph --diff before.json after.json
swift run InnoDI-DependencyGraph --diff before.json after.json --check-contract
```

`--check-contract` devuelve el codigo de salida 5 si cambia cualquier contrato
de scope, nodo o arista, para exigir en CI una actualizacion revisada del snapshot.

Inspeccionar el Swift generado por las macros para un target consumidor:

```bash
Tools/dump-macro-expansions.sh \
  --package-path /path/to/ConsumerPackage \
  --target App
```

Ejecuta el script desde un checkout de InnoDI y apunta `--package-path` al
consumidor. Usa un scratch build aislado, escribe el resultado combinado en
`.build/innodi/macro-expansions.swift` del consumidor y rechaza salidas dentro
de `Sources/` o `Tests/`. La cache normal del consumidor no se modifica. En
Xcode, **Expand Macro** sigue siendo la vía más rápida para una sola declaración.

Generar DocC:

```bash
Tools/generate-docc.sh
```

Las notas de release y de upgrade viven en [RELEASING.md](RELEASING.md).

## Collection Composition

Los contratos 6.0 de composition, provider collections y colisiones de claves se documentan en el README en ingles.

## Ejemplos

- [Examples/README.md](Examples/README.md)
- [Examples/SwiftUIExample](Examples/SwiftUIExample)
- [Examples/PreviewInjectionExample](Examples/PreviewInjectionExample)
- [Sources/InnoDIExamples/main.swift](Sources/InnoDIExamples/main.swift)
