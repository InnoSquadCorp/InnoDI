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
    @Provide(.shared, APIClient.self, with: [\Self.baseURL], concrete: true)
    var apiClient: APIClient
}

let client = AppContainer(baseURL: "https://api.example.com").apiClient
```

## Warum InnoDI

InnoDI ist fur Teams gedacht, die DI-Wiring explizit und reviewbar halten
wollen und Fehler fruher erkennen mochten.

- `@DIContainer` und `@Provide` erzeugen Container-APIs aus unterstutzten, effektiv nicht-generischen Swift-Structs.
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

Der Build-Validator bietet zwei Opt-out-Escape-Hatches fuer schnelle
Iteration oder eingeschraenkte Umgebungen: `@DIContainer(validateDAG: false)`
pro Container und `INNODI_DISABLE_BUILD_VALIDATION=1` fuer einen Kurzschluss
des gesamten Build-Plugins. Jeder PR fuehrt
`Tools/report-validate-dag-escape-hatches.sh` aus und listet alle
Verwendungsstellen dieser Escape-Hatches im Step Summary des Workflows auf,
sodass das schleichende Wachstum der Escape-Hatches ohne separates CI-Gate
sichtbar bleibt. Produktions-CI muss beide unset lassen.

## Datenschutz

InnoDI liefert ein Apple Privacy Manifest (`PrivacyInfo.xcprivacy`) mit beiden
Laufzeitprodukten `InnoDI` und `InnoDISwiftUI` aus. Das Manifest deklariert
kein Benutzer-Tracking, keine Tracking-Domains, keine erfassten Datentypen und
keine Required-Reason-API-Nutzung. Build-Zeit-Tools (InnoDIBuildSupport,
dependency-graph CLI, Makro-Plugin) werden nicht in Endbenutzer-Apps
eingebettet und tragen daher nicht zum Manifest bei. Wird InnoDI in eine iOS-,
watchOS-, tvOS- oder visionOS-App eingebettet, bundelt SwiftPM das Manifest
automatisch und es erscheint im aggregierten Datenschutzbericht der App.

## Installation

Fuge InnoDI zu `Package.swift` hinzu:

```swift
dependencies: [
    .package(url: "https://github.com/InnoSquadCorp/InnoDI.git", from: "4.3.0")
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

Wenn Teams gemessen haben, dass das Kompilieren des Source-Tools der dominante
Einfuehrungsaufwand ist, stellt das Companion-Paket `InnoDIValidationTools` ein
optionales prebuilt macOS validation plugin bereit. Haenge entweder das source
plugin oben oder das prebuilt plugin an, niemals beide; unsupported hosts und
lokale Paketentwicklung sollten weiter das source plugin verwenden.

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

    @Provide(.shared, APIClient.self, with: [\Self.baseURL])
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

Jeder Container, auch ohne verwaltete Member, erzeugt die vollstandige
Overrides-Oberflache. Ein benutzerdefinierter verschachtelter Typ `Overrides`
ist in InnoDI 5.0 nicht unterstutzt und erzeugt
`container.overrides-name-conflict`; benennen Sie ihn um, damit das Makro die
mountbare Override-ABI besitzen kann.

Das Makro erzeugt ausserdem den reservierten Compiler-Support-Alias
`_InnoDIMountOverrides = Overrides` fur generierten Parent-Mount-Code. Diesen
unterstrichenen Namen nicht direkt deklarieren oder referenzieren.

Jedes gespeicherte Instanz-Member eines Containers muss `@Provide` oder
`@SubContainer` verwenden; berechnete und statische Properties bleiben
verfugbar. So bleibt der generierte Initialisierer vollstandig und die
Memberwise-Initializer-ABI driftet nicht.

`@DIContainer` unterstutzt ausschliesslich effektiv nicht-generische
`struct`-Deklarationen auf Dateiebene oder mit nominaler Verschachtelung. Weder
die Deklaration selbst noch eine umschliessende Deklaration darf generische
Parameter oder eine `where`-Klausel besitzen. `class`, `actor`, `enum`,
`protocol`, direkt annotierte `extension`-Deklarationen und in Extensions
verschachtelte Structs werden abgelehnt. Das gilt auch fur Deklarationen in
ausfuhrbaren oder lokalen Scopes, darunter Funktionen, Closures, Accessors und
`switch`-Falle. Diese Grenze gilt ebenso bei kombiniertem `@DIComponent`.
Verschieben Sie Laufzeit- oder
typspezifischen Zustand hinter Protokollabhangigkeiten oder `@Provide(.input)`.

Ein explizit `private` deklarierter Container wird ebenfalls abgelehnt, weil
Sibling-Container seine generierte Mount-Oberflache nicht erreichen. Verwenden
Sie `fileprivate` fur file-lokales Mounting oder einen Container mit
Default-Zugriff in einem privaten Namespace.

Der aktuelle Swift-Compiler lasst beim Erweitern eines attached macro auf einem
Typ in einem computed-property-Body den Accessor-Kontext weg. Das
Build-Validation-Plugin und die Dependency-Graph-CLI scannen den vollstandigen
Quellbaum und erzwingen die Ablehnung dieses Randfalls. Binden Sie das Plugin an
jedes Target an, das Container deklariert.

```swift
@DIContainer(root: Bool = false, validateDAG: Bool = true, mainActor: Bool = false)
```

| Parameter | Default | Bedeutung |
|---|---|---|
| `root` | `false` | Nur Render-Einstieg fur den Graphen. Wenn mindestens eine Root existiert, wird Mermaid-, DOT- und ASCII-Ausgabe auf die von den Roots erreichbaren Knoten und Kanten reduziert. |
| `validateDAG` | `true` | Aktiviert globale DAG-Validierung plus die lokalen graph-derived Checks des Makros. `false` uberspringt globale DAG- und lokale cycle-Checks; Deklarationsvalidierung und Effektkompatibilitat expliziter Sibling-Kanten bleiben aktiv. |
| `mainActor` | `false` | Isoliert Dependency-Accessors, alle generierten Initialisierer, `Overrides`, die `applyOverrides`-Funktionstypen von Convenience-Initialisierern, `withOverrides`, Child-Overrides und Component-Mounting, die Operations-Closures aller vier `withOverrides`-Overloads sowie Feature-Root-Helper mit `@MainActor`. Zusammen mit `@DIComponent` werden auch das generierte `<Container>Dependencies`-Protokoll und `init(dependencies:_:)` isoliert; die Component konformiert dem dedizierten Protokoll `_InnoDIMainActorComponentMountable`. Components ohne diese Option verwenden weiterhin `_InnoDIComponentMountable`. Zugriffe außerhalb des Main Actors erfordern einen expliziten Actor-Wechsel. Für UI-Root-Container empfohlen. |

Generische Component-Mounting-Helper müssen in 5.0 zwischen beiden
Markerprotokollen unterscheiden. Behalten Sie `_InnoDIComponentMountable` für
gewöhnliche Components bei und ergänzen Sie für `mainActor: true` eine
`@MainActor`-Überladung mit `_InnoDIMainActorComponentMountable`-Constraint und
einer `@MainActor`-Override-Closure.

Nicht-`Sendable` Container-/Component-Werte müssen über einen
`@MainActor`-Aufrufer oder durch Erzeugung und Verwendung im selben
`MainActor.run`-Block auf dem Main Actor bleiben. Ein direktes `await` passt für
eine isolierte Operation mit `Sendable`-Ergebnis, etwa ein `withOverrides`-
Ergebnis, nicht zum Transport des Containers aus dem Actor heraus.

### `@Provide` und Scopes

InnoDI 5.0 unterstützt `@Provide` nur auf einer direkten, einfachen,
gespeicherten Instanz-`var` in demselben unterstützten struct mit
`@DIContainer`. `let`, computed oder observed Properties, `lazy`, `weak`,
`unowned`, `static`/`class`, eigenständige und indirekt verschachtelte
Verwendungen werden abgelehnt. InnoDI besitzt den generierten Provider-Accessor;
`_InnoDIProvideAccessor` darf nie manuell angefügt werden.

Auch Attribute und Access-Control der Provider-Deklaration bilden einen
geschlossenen Vertrag. Property Wrapper, bedingte oder unbekannte Attribute,
Setter-Zugriffsmodifikatoren wie `private(set)` und eigene Global-Actor-
Attribute werden abgelehnt. Außer `@Provide` selbst ist kein im Quelltext
geschriebenes Property-Level-Attribut erlaubt; das schließt `@MainActor` ein.
Fordern Sie Actor-Isolation mit `@DIContainer(mainActor: true)` an. Die von
InnoDI auf Provider-Deklaration und Accessor erzeugten Isolationsattribute
dienen ausschließlich der internen Compiler-Unterstützung. Eine vollständige
`@Provide`-Member-Deklaration in `#if` wird ebenfalls mit
`provide.conditional-declaration-unsupported` abgelehnt. Lassen Sie die
Deklaration außerhalb der Bedingung und verzweigen Sie in der Factory oder
injizierten Implementierung.

Pro Property ist genau ein `@Provide` zulässig; doppelte Attribute werden mit
`provide.duplicate-attribute` abgelehnt. Der explizite Property-Typ darf weder
ein opakes `some Protocol` noch ein implicitly unwrapped optional `T!` sein.
Migrieren Sie zu `any Protocol` beziehungsweise zu einem expliziten `T` oder
`T?`. Eine absichtlich gefälschte Kombination aus Compiler-Support-Accessor
und einem weiteren Property Wrapper kann zusätzlich zur InnoDI-Misuse-Diagnose
auch strukturelle Swift-Diagnosen auslösen.

```swift
@Provide(
    _ scope: DIScope = .shared,
    _ type: Any.Type? = nil,
    with dependencies: [AnyKeyPath] = [],
    factory: Any? = nil,
    asyncFactory: Any? = nil,
    concrete: Bool = false,
    escaping: Bool = false
)
```

| Scope | Bedeutung | Konstruktionsregeln |
|---|---|---|
| `.input` | Externe Abhangigkeit beim Container-Init | Deklariert weder `factory:`, `asyncFactory:`, `Type.self`, Property-Initializer noch `with:` |
| `.shared` | Einmal pro Container-Instanz erzeugt und wiederverwendet | Deklariert genau eine Quelle: `factory:`, `asyncFactory:`, `Type.self` oder Property-Initializer |
| `.transient` | Bei jedem Zugriff neu erzeugt | Deklariert genau eine Quelle: `factory:`, `asyncFactory:`, `Type.self` oder Property-Initializer |

Weitere Regeln:

- Für `.shared` / `.transient` schließen sich `factory:`, `asyncFactory:`,
  `Type.self` und Property-Initializer als vier Construction-Quellen aus.
- `.input` lehnt jede Construction-Quelle und `with:` ab.
- Generierte `.input`-Initializer-Parameter sind eager Werte des deklarierten
  Typs `T`; Swift wertet `try`- / `await`-Argumentausdrücke wie üblich vor dem
  Initializer-Aufruf aus. Direkt geschriebene non-optionale Funktionstypen
  werden automatisch erkannt und als escaping Parameter erzeugt. Ist ein
  non-optionaler Funktionstyp hinter einem Typealias verborgen, verwenden Sie
  `@Provide(.input, escaping: true)`. `escaping:` muss ein literales Bool sein
  und ist nur für `.input` gültig. Offensichtliche Nichtfunktions- und optionale
  Funktionsformen werden abgelehnt; löst sich ein konservativ akzeptierter
  Identifier-/Member-Alias nicht als non-optionale Funktion auf, kann Swift
  eine eigene Diagnose ausgeben.
- `asyncFactory` wird für `.shared` und `.transient` unterstützt und muss eine
  `async`-Closure sein.
- `with:` ist nur mit der `Type.self`-Construction zulässig. Jeder Eintrag des
  literalen Arrays muss exakt die kanonische Direct-Member-Schreibweise
  `\Self.member` verwenden, etwa `with: [\Self.config]`; `with: []` ist ebenfalls
  gültig. Benannte Container-, modulqualifizierte und Typealias-Roots sowie
  verschachtelte Komponenten, Optional Chaining, Subscripts und berechnete
  Array-Elemente werden abgelehnt. Jeder referenzierte Provider muss synchron
  konstruiert werden.
- Konkrete `.shared`- und `.transient`-Typen brauchen `concrete: true`.
- Die Namensauflosung fur factory-Parameter und `with:`-Wiring ist streng
  an Member-Namen gebunden.

Sibling-DI-Kanten verwenden eine geschlossene Syntax:

- Eine root `factory:`- oder `asyncFactory:`-Closure-Literal erzeugt für jeden
  benannten Parameter eine Kante. Verschachtelte Closures und beliebige
  Identifier erzeugen keine Kanten.
- `Type.self` erzeugt Kanten aus einem literalen kanonischen
  `\Self.member`-Key-Path-Array und kann nur synchrone Provider referenzieren.
- Ein Nicht-Closure-`factory:`-Ausdruck oder Property-Initializer ist eine
  opake Zero-Edge-Konstruktionsquelle und darf keine Sibling-Member referenzieren.
  Verwenden Sie root-Closure-Parameter für DI-Wiring oder ein qualifiziertes
  globales/statisches Konstruktionssymbol, wenn keine DI-Kante beabsichtigt ist.

Factory-Effekte werden explizit angegeben und nicht aus Abhängigkeiten
abgeleitet. Verwenden Sie `asyncFactory:` für einen asynchronen Consumer und
deklarieren Sie die Closure als `async throws`, wenn sie einen werfenden
asynchronen Provider konsumiert. Die Effektkompatibilität wird auf jeder
expliziten Kante geprüft, auch mit `validateDAG: false`.

| Provider | synchroner Consumer | `async` Consumer | `async throws` Consumer |
|---|---:|---:|---:|
| synchron | erlaubt | erlaubt | erlaubt |
| `async` | abgelehnt | erlaubt | erlaubt |
| `async throws` | abgelehnt | abgelehnt | erlaubt |

`Lazy<T>` und `Provider<T>` sind synchrone Deferred-Wrapper und lehnen
asynchrone Targets ab.

## Validierungsmodell

InnoDI validiert in drei Schichten:

1. Makrovalidierung
2. Build-Validierung
3. Globale DAG-Validierung

`validateDAG: false` ist absichtlich eng gefasst. Es deaktiviert globale DAG-
und lokale cycle-/graph-derived Checks, aber weder die Deklarationsvalidierung
noch die Effektkompatibilität expliziter root-Closure-/`with:`-Sibling-Kanten.

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

Beide Wrapper sind absichtlich non-`Sendable`. Sie bleiben zudem synchron und
können kein `asyncFactory`-Member als Target verwenden.

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
- `@SubContainer(..., featureRoot:)` und `featureRoots:` erzeugen standardmäßige
  oder benannte Feature-Root-Helper.
- InnoDI 5.0 entfernt das veraltete Kompatibilitätsmakro `@DIFeatureRoot`.
  Ersetzen Sie es durch die Feature-Root-Argumente von `@SubContainer`.

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
