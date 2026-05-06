# InnoDI

[English](README.md) | [한국어](README.ko.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [简体中文](README.zh-Hans.md) | [日本語](README.ja.md) | [Русский](README.ru.md)

Makrogetriebenes Dependency Injection fur Swift mit Compile- und Build-
Validierung, Dependency-Graph-Werkzeugen, Hierarchieprufungen und SwiftUI-
Hilfen.

## Minimales nutzliches Beispiel

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

## Warum InnoDI

InnoDI ist fur Teams gedacht, die DI-Wiring explizit und reviewbar halten
wollen und Fehler fruher erkennen mochten.

- `@DIContainer` und `@Provide` erzeugen Container-APIs aus normalen Swift-Typen.
- Makrovalidierung erkennt lokale Fehler schon wahrend der Expansion.
- Build-Validierung und Graph-CLI erkennen cross-file-, cross-module- und globale Graphprobleme.
- `InnoDISwiftUI` reduziert wiederholtes Environment-Wiring an der Root-Grenze.

InnoDI ist keine Runtime-State-Machine. Runtime-Zustand gehort in die App-
Schicht oder in begleitende Frameworks wie `InnoFlow`, `InnoRouter` und
`InnoNetwork`.
InnoDI bietet bewusst keinen `@Injected` Property Wrapper und keine Dynamic-
Registration-API. Der Tradeoff sind explizite generierte Initializer,
reviewbares Wiring und fruhere Validierung.

## Wann InnoDI wahlen

Wahle InnoDI, wenn Dependency-Wiring im Code Review sichtbar bleiben, vor der
Runtime validiert und als Graph-Artefakt inspizierbar sein soll.

| Prioritat | Bevorzugen | Warum |
| --- | --- | --- |
| Compile/build-time validation eines App-Dependency-Graphen | InnoDI, [SafeDI](https://github.com/dfed/SafeDI) oder [Needle](https://github.com/uber/needle) | InnoDI halt die Container-Oberflache in macro-expanded Swift und kombiniert lokale Macro-Diagnosen, Build-Support-Checks und eine DAG CLI. |
| Runtime registration, late binding oder plugin-artige Composition | [Swinject](https://github.com/Swinject/Swinject) oder [Factory](https://github.com/hmlongco/Factory) | Runtime-Container erleichtern dynamische Registrierungen. InnoDI priorisiert explizite generierte Initializer und fruhe Validierung. |
| SwiftUI previews und scoped test overrides | [Factory](https://github.com/hmlongco/Factory), [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) oder InnoDI | InnoDI passt, wenn diese Overrides auf einem validierten App-Container und generated SwiftUI root helpers liegen sollen. |
| Hierarchical feature ownership und graph visibility | InnoDI, [Needle](https://github.com/uber/needle) oder [SafeDI](https://github.com/dfed/SafeDI) | InnoDI modelliert Parent-owned Child-Container mit `@SubContainer` und rendert Ownership-Edges in der Graph CLI. |
| Niedrigste Einstiegskosten in einer bestehenden App | [Factory](https://github.com/hmlongco/Factory), [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) oder inkrementelle InnoDI-Adoption | InnoDI verlangt Container-Definitionen und Macro/Build-Validierung; das lohnt sich vor allem fur reviewbares Wiring, generated Overrides und Graph-Checks. |

InnoDI kann in der Praxis mit Runtime-Tools koexistieren: nutze InnoDI fur den
validierten Application Graph und `swift-dependencies` oder kleine Factories
fur lokale Runtime-Werte innerhalb von Features.

Das Layering-Muster, das sich bewahrt, trennt *Konstruktion* (InnoDI) von
*kurzlebigen, aufrufgebundenen Overrides* (`swift-dependencies`). Der
Composition Root lost einen `DependencyKey` auf (z. B. `@Dependency(\.date)`)
und reicht den Wert als `.input` Slot an den Container weiter; Tests ersetzen
ihn pro Aufruf-Baum mit
`withDependencies { $0.date = .constant(...) } operation:`, ohne den Container
oder seinen validierten Graph neu zu erzeugen. Der container-weite
`Overrides`-Builder bleibt das richtige Werkzeug fur app-weite Swaps wie einen
gefakten `APIClient`; `swift-dependencies` greift man nur, wenn der Override
fur die Dauer einer einzigen Operation gelten soll.

## Anforderungen

- Swift tools version `6.2`
- Plattformen:
  - iOS 17+
  - macOS 13+
  - watchOS 10+
  - tvOS 17+
  - visionOS 1+

### Dateisystemanforderungen des Buildzeit-Validators

Das Build-Plugin serialisiert Live-DAG-Validierungslaufe uber einen
geschichteten POSIX-Lock unter dem Scratch-Verzeichnis von Swift Package
Manager:

1. `open(O_CREAT | O_EXCL | O_RDWR)` erstellt eine einzelne Lockdatei.
2. `flock(LOCK_EX | LOCK_NB)` legt einen advisory Exclusive-Lock auf den Descriptor.

InnoDI erkennt automatisch das Dateisystem hinter diesem Lock-Verzeichnis.
Lokale Dateisysteme wie APFS, HFS+, ext4, btrfs, xfs und tmpfs werden
unterstutzt. NFS-Mounts, SMB/CIFS, WebDAV und FUSE-artige Dateisysteme werden
standardmassig verweigert, weil parallele Builds den geteilten
Validierungscache beschadigen konnen, wenn Lock-Atomizitat nicht verlasslich
ist.

Wenn dein Build-System derived data auf einem geteilten Volume ablegen muss,
zeige mit SPMs `--scratch-path` oder Xcodes derived-data-Speicherort auf ein
lokales Verzeichnis:

```sh
swift build --scratch-path /tmp/innodi-cache
```

Das Plugin legt keinen Lock-/Cache-State unter `.build/innodi-dag-validation`
im Package Root an; ein verschobener Scratch Path verschiebt auch den
Validation-State.

Operatoren konnen den unsafe-filesystem Fail-Fast mit
`INNODI_ALLOW_UNSAFE_LOCK=1` umgehen. InnoDI schreibt dann weiterhin eine
auditierbare Warnung, und das Risiko bleibt bei dieser Build-Umgebung. Fur
Diagnose, Wiederherstellungsschritte und die vollstandige Dateisystemtabelle
siehe [Lock Safety](Sources/InnoDI/InnoDI.docc/lock-safety.md).

## Installation

Fuge InnoDI zu `Package.swift` hinzu:

```swift
dependencies: [
    .package(url: "https://github.com/InnoSquadCorp/InnoDI.git", from: "4.1.0")
]
```

Dann binde die benotigten Produkte ein:

```swift
.target(
    name: "YourApp",
    dependencies: [
        "InnoDI"
    ]
)
```

Fuge `InnoDISwiftUI` nur hinzu, wenn du die SwiftUI-Hilfen benotigst:

```swift
.target(
    name: "YourApp",
    dependencies: [
        "InnoDI",
        "InnoDISwiftUI"
    ]
)
```

Aktiviere den build-time DAG-Validator, indem du das Plugin an jedes Target
hangst, das InnoDI-Container deklariert:

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

## Schnellstart

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

Nutze eine Factory-Closure, wenn Namen oder Konstruktionslogik nicht zu
`Type.self` plus `with:` passen.

```swift
@Provide(.shared, factory: { (baseURL: String) in
    APIClient(baseURL: baseURL)
})
var apiClient: any APIClientProtocol
```

## Weiterfuhrende Dokumente

1. [Overview](Sources/InnoDI/InnoDI.docc/de.lproj/Overview.md)
2. [Validation](Sources/InnoDI/InnoDI.docc/de.lproj/Validation.md)
3. [Policy Boundaries](Sources/InnoDI/InnoDI.docc/de.lproj/PolicyBoundaries.md)
4. [Anti-Patterns](Sources/InnoDI/InnoDI.docc/AntiPatterns.md)
5. [Module-Wide Init Detection](Sources/InnoDI/InnoDI.docc/de.lproj/ModuleWideInitDetection.md)
6. [RELEASING.md](RELEASING.md)
7. [ROADMAP.md](ROADMAP.md)

## Kern-API

### `@DIContainer`

`@DIContainer` erzeugt:

1. ein primares `init(...)`
2. einen verschachtelten Typ `Overrides`
3. ein Convenience-`init(<inputs...>, _ applyOverrides: ...)`
4. vier `withOverrides`-Overloads fur `sync`, `throws`, `async` und `async throws`

Alle Container erzeugen die Overrides-Oberflache, sofern nicht bereits ein
verschachtelter Typ `Overrides` vom Benutzer definiert wird.

```swift
@DIContainer(root: Bool = false, validateDAG: Bool = true, mainActor: Bool = false)
```

| Parameter | Default | Bedeutung |
|---|---|---|
| `root` | `false` | Nur Render-Einstieg fur den Graphen. Wenn mindestens eine Root existiert, wird Mermaid-, DOT- und ASCII-Ausgabe auf die von den Roots erreichbaren Knoten und Kanten reduziert. |
| `validateDAG` | `true` | Aktiviert globale DAG-Validierung plus die lokalen cycle- und closure/`with:`-Checks der Makros. `false` uberspringt nur diese Checks; raw-expression-Referenzen in `factory:` und Initializern sowie strukturelle Validierung bleiben aktiv. |
| `mainActor` | `false` | Wendet `@MainActor` auf die generierte Container-API an. Fur UI-Roots empfohlen. |

### `@Provide` und Scopes

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

| Scope | Bedeutung | Konstruktionsregeln |
|---|---|---|
| `.input` | Externe Abhangigkeit beim Container-Init | Kein `factory`, kein `asyncFactory` |
| `.shared` | Einmal pro Container-Instanz erzeugt und wiederverwendet | Benotigt `factory`, `asyncFactory` oder `Type.self` plus `with:` |
| `.transient` | Bei jedem Zugriff neu erzeugt | Benotigt `factory`, `asyncFactory` oder `Type.self` plus `with:` |

Weitere Regeln:

- `factory` und `asyncFactory` sind gegenseitig ausschliessend.
- `asyncFactory` muss eine `async`-Closure sein.
- Konkrete `.shared`- und `.transient`-Typen brauchen `concrete: true`.
- Die Namensauflosung fur factory-Parameter und `with:`-Wiring ist streng
  an Member-Namen gebunden.

## Validierungsmodell

InnoDI validiert in drei Schichten:

1. Makrovalidierung
2. Build-Validierung
3. Globale DAG-Validierung

`validateDAG: false` ist absichtlich eng gefasst. Es deaktiviert die globale
DAG-Validierung sowie die lokalen cycle- und closure/`with:`-Graphchecks,
aber nicht die strukturelle Validierung und nicht die Compile-Time-Diagnosen
fur raw-expression-Referenzen.

## Overrides Builder

Mit dem erzeugten `Overrides`-Builder lassen sich nur die benotigten Member in
Tests uberschreiben.

```swift
let container = AppContainer(baseURL: "https://test.example.com") { overrides in
    overrides.apiClient = MockAPIClient()
}
```

Oder beschranke den Override auf eine einzelne Operation:

```swift
let result = try await AppContainer.withOverrides(baseURL: "https://test.example.com") { overrides in
    overrides.apiClient = MockAPIClient()
} operation: { container in
    try await container.apiClient.fetch()
}
```

Input-only-Container erzeugen ebenfalls einen leeren Builder. Wenn ein Child-
Container nur Inputs besitzt, kompilieren `<name>Overrides`-Closures trotzdem
und laufen als No-op.

## `Lazy<T>` und `Provider<T>`

- `Lazy<T>` erzeugt eine Soft-Edge und ist fur Zyklus-Flucht gedacht.
- `Provider<T>` tritt bei jedem Aufruf erneut in eine `.transient`-Abhangigkeit ein.

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

Beide Wrapper sind absichtlich non-`Sendable`.

## Verschachtelte Container und Hierarchie

`@SubContainer` modelliert Child-Container, die einem Parent gehoren:

```swift
@SubContainer(scope: .shared, with: [\.config, \.apiClient])
var feature: FeatureContainer
```

Wichtige Regeln:

- `scope:` ist Pflicht.
- Implizites Same-Name-Wiring ist nur eine Convenience, wenn der Parent null
  oder einen `@Provide`-Kandidaten hat. Bei mehreren Kandidaten muss
  explizites Wiring hinzugefugt werden statt sich auf vom Compiler
  generierte Initializer-Fehler zu verlassen.
- `with:` leitet eine explizite Same-Name-Untermenge bzw. -Reihenfolge weiter.
  Es muss ein literales Key-Path-Array sein, das der Macro lesen kann;
  Runtime-Variablen oder berechnete Elemente werden nicht unterstutzt.
- `with: []` ist eine explizit leere Untermenge und ruft `Child()` auf.
- `bindings:` mappt Child-Input-Labels auf andere Parent-Member-Namen.
- Genau eine Wiring-Form verwenden: `with:` oder `bindings:`.
- `Overrides` des Parents enthalt sowohl einen Vollersatz-Slot (`feature`)
  als auch eine Child-Override-Closure (`featureOverrides`).

Fur cross-module Ownership:

- `@DIComponent`
- `@DIHierarchyRoot`

## SwiftUI-Hilfen

`InnoDISwiftUI` bietet:

- `.innodi(container)`
- `@DIEnvironmentBridge`
- `@DIFeatureRoot`

## CLI und Release-Oberflache

```bash
swift run InnoDI-DependencyGraph --root .
swift run InnoDI-DependencyGraph --root . --validate-dag
Tools/generate-docc.sh
```

Release- und Upgrade-Notizen stehen in [RELEASING.md](RELEASING.md).

## Beispiele

- [Examples/README.md](Examples/README.md)
- [Examples/SwiftUIExample](Examples/SwiftUIExample)
- [Examples/PreviewInjectionExample](Examples/PreviewInjectionExample)
- [Sources/InnoDIExamples/main.swift](Sources/InnoDIExamples/main.swift)
