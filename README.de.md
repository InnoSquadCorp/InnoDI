# InnoDI

[English](README.md) | [한국어](README.ko.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [简体中文](README.zh-Hans.md) | [日本語](README.ja.md) | [Русский](README.ru.md)

Makrogetriebenes Dependency Injection fur Swift mit Compile- und Build-
Validierung, Dependency-Graph-Werkzeugen, Hierarchieprufungen und SwiftUI-
Hilfen.

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

## Anforderungen

- Swift tools version `6.2`
- Plattformen:
  - iOS 17+
  - macOS 13+
  - watchOS 10+
  - tvOS 17+
  - visionOS 1+

### Dateisystemanforderungen des Buildzeit-Validators

Das Build-Plugin serialisiert Live-DAG-Validierungslaufe uber eine POSIX
`O_CREAT | O_EXCL`-Lockdatei unter dem Swift-Package-Manager-derived-data-
Verzeichnis. Das funktioniert auf lokalen Dateisystemen wie APFS, HFS+,
ext4, btrfs und xfs korrekt; netzwerkgestutzte Pfade haben aber wichtige
Einschrankungen.

- **NFSv3** garantiert keine atomare `O_EXCL`-Semantik; zwei Clients konnen
  beide glauben, den Lock erstellt zu haben. Nutze NFSv4 oder verschiebe
  derived data auf einen lokalen Pfad.
- **SMB/CIFS** bietet keine verlassliche `O_EXCL`-Atomizitat und wird nicht
  unterstutzt.
- **Docker / Kubernetes bind mounts** erben die Semantik des Host-
  Dateisystems. Ist der Host lokal, sind sie sicher.

Wenn dein Build-System derived data auf einem geteilten Volume ablegen muss,
zeige mit SPMs `--scratch-path` oder Xcodes derived-data-Speicherort vor dem
Aktivieren des Plugins auf ein lokales Verzeichnis.

## Installation

Fuge InnoDI zu `Package.swift` hinzu:

```swift
dependencies: [
    .package(url: "https://github.com/InnoSquadCorp/InnoDI.git", from: "4.0.0")
]
```

Dann binde die benotigten Produkte ein:

```swift
.target(
    name: "YourApp",
    dependencies: [
        "InnoDI",
        "InnoDISwiftUI"
    ]
)
```

Wenn du die SwiftUI-Hilfen nicht brauchst, reicht `InnoDI`.

## Schnellstart

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

Nutze eine Factory-Closure, wenn Namen oder Konstruktionslogik nicht zu
`Type.self` plus `with:` passen.

## Weiterfuhrende Dokumente

1. [Overview](Sources/InnoDI/InnoDI.docc/de.lproj/Overview.md)
2. [Validation](Sources/InnoDI/InnoDI.docc/de.lproj/Validation.md)
3. [Policy Boundaries](Sources/InnoDI/InnoDI.docc/de.lproj/PolicyBoundaries.md)
4. [Module-Wide Init Detection](Sources/InnoDI/InnoDI.docc/de.lproj/ModuleWideInitDetection.md)
5. [RELEASING.md](RELEASING.md)
6. [ROADMAP.md](ROADMAP.md)

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

| Scope | Bedeutung | Konstruktionsregeln |
|---|---|---|
| `.input` | Externe Abhangigkeit beim Container-Init | Kein `factory`, kein `asyncFactory` |
| `.shared` | Einmal pro Container-Instanz erzeugt und wiederverwendet | Benotigt `factory`, `asyncFactory` oder `Type.self` plus `with:` |
| `.transient` | Bei jedem Zugriff neu erzeugt | Benotigt `factory`, `asyncFactory` oder `Type.self` plus `with:` |

Weitere Regeln:

- `factory` und `asyncFactory` sind gegenseitig ausschliessend.
- `asyncFactory` muss eine `async`-Closure sein.
- Konkrete `.shared`- und `.transient`-Typen brauchen `concrete: true`.

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

Input-only-Container erzeugen ebenfalls einen leeren Builder. Wenn ein Child-
Container nur Inputs besitzt, kompilieren `<name>Overrides`-Closures trotzdem
und laufen als No-op.

## `Lazy<T>` und `Provider<T>`

- `Lazy<T>` erzeugt eine Soft-Edge und ist fur Zyklus-Flucht gedacht.
- `Provider<T>` tritt bei jedem Aufruf erneut in eine `.transient`-Abhangigkeit ein.

Beide Wrapper sind absichtlich non-`Sendable`.

## Verschachtelte Container und Hierarchie

`@SubContainer` modelliert Child-Container, die einem Parent gehoren.

- `scope:` ist Pflicht.
- Implizites Same-Name-Wiring ist nur eine Convenience, wenn der Parent null
  oder einen `@Provide`-Kandidaten hat.
- Bei mehreren Parent-Kandidaten ist `with:`, `withNames:` oder `bindings:`
  erforderlich.
- `with:` oder `withNames:` leitet ein explizites Same-Name-Subset weiter.
- `bindings:` mappt Child-Input-Labels auf andere Parent-Member-Namen.
- `Overrides` des Parents enthalt Vollersatz und Child-Override-Closure.

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
