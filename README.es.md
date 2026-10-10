# InnoDI

<!-- innodi:guide version=7.0.1 -->

[English](README.md) | [한국어](README.ko.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [简体中文](README.zh-Hans.md) | [日本語](README.ja.md) | [Русский](README.ru.md)

> Guía breve y actualizada para **InnoDI 7.0.1**, no una traducción completa del README inglés ni del catálogo DocC. El [README inglés](README.md) es la referencia canónica; también hay un [README coreano](README.ko.md) detallado. Las guías enlazadas están en inglés y sus versiones coreanas mantenidas están en [ko.lproj](Sources/InnoDI/InnoDI.docc/ko.lproj).

InnoDI genera código de inyección de dependencias mediante macros de Swift. Los contenedores explícitos, la validación durante la compilación y la construcción del proyecto, y el grafo de dependencias permiten revisar el cableado. No ofrece registro dinámico ni un property wrapper `@Injected`.

<!-- innodi:section requirements -->

## Requisitos

- Versión de herramientas Swift **6.2 o posterior**; CI valida Swift 6.2, 6.3 y 6.4
- Solo plataformas Apple: iOS 17+, macOS 14+, watchOS 10+, tvOS 17+, visionOS 1+
- Linux no se compila ni se prueba en CI; `InnoDITesting` importa el módulo `os` de Apple sin condiciones
- `swift-syntax` está fijado exactamente en **604.0.0**. No se puede resolver en el mismo grafo SwiftPM que Mockable 0.6.4, que requiere `509.0.0..<604.0.0`
- El directorio de trabajo temporal de SwiftPM que contiene los bloqueos y la caché de validación debe estar en un sistema de archivos local como APFS. NFS, SMB, WebDAV y FUSE se rechazan por defecto; consulta [seguridad de los bloqueos](Sources/InnoDI/InnoDI.docc/lock-safety.md)

<!-- innodi:section installation -->

## Instalación y plugin de validación obligatorio

Añade el paquete y la configuración del target a tu `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/InnoSquadCorp/InnoDI.git", from: "7.0.1")
]
```

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "InnoDI", package: "InnoDI")
    ],
    plugins: [
        .plugin(name: "InnoDIDAGValidationPlugin", package: "InnoDI")
    ]
)
```

`InnoDI` es el producto principal. Añade `.product(name: "InnoDISwiftUI", package: "InnoDI")` para los auxiliares de SwiftUI. Añade `InnoDITesting` únicamente a targets de pruebas o de soporte de previews que necesiten mocks generados o presets de sustitución.

**Cada target** que declare un contenedor InnoDI o un `@DIEnvironmentBridge` independiente debe incluir `InnoDIDAGValidationPlugin`. El plugin forma parte del contrato de corrección: comprueba, entre otras cosas, inicializadores en otros archivos, nombres que ocultan calificadores y el grafo global. Para Xcode y Tuist, sigue la [guía de integración](Sources/InnoDI/InnoDI.docc/IntegrationGuide.md#build-plugin).

`validateDAG: false` e `INNODI_DISABLE_BUILD_VALIDATION=1` son excepciones limitadas, no una configuración habitual de producción. La CI de producción debe mantener activa la validación de construcción; [Plugin Opt-Out](Sources/InnoDI/InnoDI.docc/PluginOptOut.md) explica los límites exactos.

<!-- innodi:section quickstart -->

## Ejemplo mínimo

Tras instalar el paquete, este ejemplo, copiado sin cambios del README inglés, crea un contenedor real y otro con un valor de prueba. Si el target usa aislamiento MainActor por defecto, marca el contenedor explícitamente con `@MainActor` o `nonisolated`; la macro no puede deducir esa opción de compilación.

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

let live = AppContainer(baseURL: "https://api.example.com")
let test = AppContainer(baseURL: "https://api.example.com") {
    $0.apiClient = APIClient(baseURL: "https://test.example.com")
}
precondition(live.apiClient.baseURL == "https://api.example.com")
precondition(test.apiClient.baseURL == "https://test.example.com")
```

<!-- innodi:section api -->

## Qué API usar para cada tarea

| Tarea | API y límite importante |
| --- | --- |
| Definir un contenedor | `@DIContainer` para structs compatibles y efectivamente no genéricos; `@DIContainerRole` para roles explícitos, componentes y raíces |
| Recibir valores externos | `@Input`; sin factory, `Type.self`, inicializador de propiedad ni `with:` |
| Reutilizar una dependencia | `@Provide(.shared, ...)`; construcción inmediata por defecto, o en el primer acceso con `initialization: .onDemand` |
| Construir en cada acceso | `@Provide(.transient, ...)` |
| Conectar miembros del mismo contenedor | Parámetros con nombre de la closure raíz de una factory, o `Type.self` con un array literal como `with: [\Self.baseURL]`; estos key paths solo admiten proveedores síncronos |
| Aplazar un acceso síncrono | `Lazy<T>`; sigue el scope del destino y no tiene caché propia |
| Invocar repetidamente un proveedor transitorio | `Provider<T>`; requiere un destino `.transient` síncrono |
| Poseer contenedores hijos | `@SubContainer`; jerarquía y enlaces de inputs explícitos |
| Gestionar preparación, reintentos y cierre | `generateOwned: true`, `makeOwned`, `prepare`, `requireReady`, `withPrepared` |
| Integrar SwiftUI | `InnoDISwiftUI`, `@DIEnvironmentBridge` y auxiliares generados para raíces de funcionalidades |

Para `.shared` y `.transient`, elige exactamente una fuente de construcción: `factory:`, `asyncFactory:`, `Type.self` o un inicializador de propiedad. Los efectos de las factories son explícitos: usa `asyncFactory:` y escribe `async throws` cuando corresponda. No se deducen de las dependencias.

`Lazy<T>` y `Provider<T>` son síncronos y no son `Sendable`; no pueden apuntar a miembros `asyncFactory` y deben permanecer en el dominio de aislamiento original. No rompen ciclos de propiedad. Incluso con `validateDAG: false` siguen activas las comprobaciones de ciclos de propiedad, declaraciones y compatibilidad de efectos en enlaces explícitos.

<!-- innodi:section lifecycle -->

## Preparación y ciclo de vida asíncronos

- Un proveedor `.shared` normal con `asyncFactory:` inicia su tarea en el inicializador. Ese contenedor no cancela la tarea automáticamente
- En un proveedor `.shared` asíncrono con `initialization: .onDemand`, el trabajo empieza en el primer acceso. El acceso siempre puede lanzar errores y `closeAsyncProviders()` cierra esos proveedores y cancela el trabajo en curso. Las copias del contenedor comparten la caché lógica; los contenedores inicializados por separado permanecen aislados
- `generateOwned: true` genera un propietario y una vista del contenedor separados. `makeOwned` es `async throws`, pero **no implica que esté listo**. Con `prepare`, comprueba siempre `report.isReady`; `requireReady` lanza un error si el resultado no está listo
- `withPrepared` ejecuta la operación solo cuando el subgrafo seleccionado está listo y espera a `close()` al terminar, también en caso de error. Los proveedores de inicio inmediato no seleccionados pueden seguir trabajando o fallar
- Cancelar al llamador que espera solo termina su espera, no cancela automáticamente el trabajo compartido. El reintento explícito se aplica a proveedores fallidos o cancelados; `retryAndRequireReady` no es una actualización ni un bucle automático de reintentos
- `await owner.close()` cierra el propietario de forma permanente, impide accesos asíncronos posteriores, incluidos los de caché, y solicita la cancelación del trabajo que posee. No espera a factories que ignoren la cancelación, no llama a `shutdown()` de los servicios ni revoca valores ya entregados. Los inputs, valores síncronos e hijos prestados siguen siendo prestados
- No hay cierre automático al salir del ámbito. Los métodos y conformidades de protocolo personalizados del contenedor original no pasan a la vista del propietario

Consulta [Owned Containers](Sources/InnoDI/InnoDI.docc/OwnedContainers.md) y [preparación asíncrona](Sources/InnoDI/InnoDI.docc/AsyncPreparation.md). En SwiftUI, vincula el cierre al final real del ciclo de vida, no de forma indiscriminada a `onDisappear`.

<!-- innodi:section testing -->

## Pruebas, sustituciones y previews

El ejemplo mínimo sustituye `apiClient` mediante el builder `Overrides` generado. Para una sola operación, `withOverrides` ofrece variantes síncronas, con errores, asíncronas y asíncronas con errores. No se permite declarar un tipo anidado propio llamado `Overrides`.

`InnoDITesting` añade de forma opcional mocks generados, almacenamiento seguro bajo concurrencia, reinicio por generaciones, validación de interacciones y presets de sustitución tipados. Consulta las declaraciones y restricciones en [Auto Mock](Sources/InnoDI/InnoDI.docc/AutoMock.md), y las previews en [SwiftUI Preview Helper](Sources/InnoDI/InnoDI.docc/SwiftUIPreviewHelper.md).

<!-- innodi:section diagnostics -->

## Diagnóstico, migración y CI

Ejecuta estos comandos desde el repositorio de InnoDI y apunta `--root` al workspace que quieras analizar. La línea de pruebas comprueba el paquete del directorio actual, en una plataforma Apple compatible:

```bash
swift run InnoDI-Doctor --root /path/to/consumer
swift run InnoDI-Migrate --root /path/to/consumer --check
swift run InnoDI-Migrate --root /path/to/consumer --report --output migration-report.json
swift run InnoDI-DependencyGraph --root /path/to/consumer --validate-dag
swift run InnoDI-DependencyGraph --root /path/to/consumer --root-pruning all
swift run InnoDI-DependencyGraph --diff before.json after.json --check-contract
swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
```

`swift run` puede compilar primero la herramienta. El análisis predeterminado de Doctor sigue siendo de solo lectura.

Doctor es de solo lectura por defecto: no resuelve paquetes, no compila ni elimina cachés. Los manifiestos dinámicos y los mapeos incompletos de Tuist no se presentan como correctos. El informe de migración usa los códigos de salida `0` si no hay cambios, `1` si se requieren cambios y `2` si está bloqueado. `--check-contract` devuelve `5` si cambia el contrato del grafo; `before.json` y `after.json` deben ser artefactos JSON existentes y acotados por target.

Antes de aplicar una migración que escriba archivos, revisa el informe y la [guía de migración](Sources/InnoDI/InnoDI.docc/MigrationGuide.md#6x--70). Si usas `--apply`, revisa los archivos `RECOVERY` indicados después de cerrar los editores y antes de eliminarlos. Las notas de versión se centralizan en el [changelog](CHANGELOG.md#701).

<!-- innodi:section documentation -->

## Guías por tarea

Los siguientes artículos son las versiones canónicas en inglés. Las versiones coreanas mantenidas están en [ko.lproj](Sources/InnoDI/InnoDI.docc/ko.lproj); esta página no promete un catálogo DocC completo en español para 7.0.1.

- [Entender los conceptos](Sources/InnoDI/InnoDI.docc/Overview.md)
- [Crear el primer contenedor](Sources/InnoDI/InnoDI.docc/Tutorial-01-Hello.md)
- [Pasar inputs](Sources/InnoDI/InnoDI.docc/Tutorial-02-Inputs.md)
- [Conectar dependencias](Sources/InnoDI/InnoDI.docc/Tutorial-03-Wiring.md)
- [Usar tipos concretos](Sources/InnoDI/InnoDI.docc/Tutorial-04-Concrete.md)
- [Crear subcontenedores](Sources/InnoDI/InnoDI.docc/Tutorial-05-SubContainer.md)
- [Consultar reglas de contenedores](Sources/InnoDI/InnoDI.docc/DIContainer.md)
- [Elegir proveedores y scopes](Sources/InnoDI/InnoDI.docc/Provide.md)
- [Gestionar contenedores asíncronos con propietario](Sources/InnoDI/InnoDI.docc/OwnedContainers.md)
- [Planificar preparación y reintentos](Sources/InnoDI/InnoDI.docc/AsyncPreparation.md)
- [Escribir mocks y pruebas](Sources/InnoDI/InnoDI.docc/AutoMock.md)
- [Integrar SwiftUI y previews](Sources/InnoDI/InnoDI.docc/SwiftUIPreviewHelper.md)
- [Integrar SwiftPM, Xcode y Tuist](Sources/InnoDI/InnoDI.docc/IntegrationGuide.md)
- [Entender la validación](Sources/InnoDI/InnoDI.docc/Validation.md)
- [Validar grafos globales](Sources/InnoDI/InnoDI.docc/DAGValidation.md)
- [Resolver diagnósticos](Sources/InnoDI/InnoDI.docc/DiagnosticsGuide.md)
- [Comprobar inicializadores entre archivos](Sources/InnoDI/InnoDI.docc/ModuleWideInitDetection.md)
- [Evaluar excepciones del plugin](Sources/InnoDI/InnoDI.docc/PluginOptOut.md)
- [Entender los límites de validación](Sources/InnoDI/InnoDI.docc/PolicyBoundaries.md)
- [Evitar antipatrones](Sources/InnoDI/InnoDI.docc/AntiPatterns.md)
- [Revisar bloqueos y sistemas de archivos](Sources/InnoDI/InnoDI.docc/lock-safety.md)
- [Trazar resoluciones en ejecución](Sources/InnoDI/InnoDI.docc/RuntimeTracing.md)
- [Migrar de 6.x a 7.0](Sources/InnoDI/InnoDI.docc/MigrationGuide.md)
- [Migrar desde Factory](Sources/InnoDI/InnoDI.docc/MigratingFromFactory.md)
- [Migrar desde Swinject](Sources/InnoDI/InnoDI.docc/MigratingFromSwinject.md)
- [Encontrar la guía adecuada](Sources/InnoDI/InnoDI.docc/DocumentationGuide.md)
- [Componer factories con inputs asistidos y colecciones](Sources/InnoDI/InnoDI.docc/Composition.md)
- [Consultar la API de InnoDITesting](Sources/InnoDITesting/InnoDITesting.docc/InnoDITesting.md)

<!-- innodi:section history -->

Archivo histórico: [README español de 6.0.0](https://github.com/InnoSquadCorp/InnoDI/blob/6.0.0/README.es.md). Esa versión no describe la API actual.
