# InnoDI

<!-- innodi:guide version=7.0.1 -->

[English](README.md) | [한국어](README.ko.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [简体中文](README.zh-Hans.md) | [日本語](README.ja.md) | [Русский](README.ru.md)

> Aktueller kompakter Leitfaden für **InnoDI 7.0.1**, keine vollständige Übersetzung der englischen README oder des DocC-Katalogs. Maßgeblich ist die [englische README](README.md); eine ausführliche [koreanische README](README.ko.md) ist ebenfalls verfügbar. Die unten verlinkten Fachartikel sind auf Englisch; gepflegte koreanische Fassungen stehen unter [ko.lproj](Sources/InnoDI/InnoDI.docc/ko.lproj).

InnoDI erzeugt Dependency-Injection-Code mit Swift-Makros. Explizite Container, Prüfungen zur Übersetzungs- und Build-Zeit sowie ein Abhängigkeitsgraph machen die Verdrahtung überprüfbar. Dynamische Registrierungen und einen `@Injected`-Property-Wrapper bietet InnoDI nicht.

<!-- innodi:section requirements -->

## Voraussetzungen

- Swift-Tools-Version **6.2 oder neuer**; CI prüft Swift 6.2, 6.3 und 6.4
- Nur Apple-Plattformen: iOS 17+, macOS 14+, watchOS 10+, tvOS 17+, visionOS 1+
- Linux wird nicht in CI gebaut oder getestet; `InnoDITesting` importiert Apples Modul `os` bedingungslos
- `swift-syntax` ist exakt auf **604.0.0** festgelegt. Das lässt sich nicht im selben SwiftPM-Abhängigkeitsgraphen mit Mockable 0.6.4 auflösen, das `509.0.0..<604.0.0` verlangt
- Das SwiftPM-Scratch-Verzeichnis für Validierung, Sperren und Cache muss auf einem lokalen Dateisystem wie APFS liegen. NFS, SMB, WebDAV und FUSE werden standardmäßig abgewiesen; siehe [Sperrsicherheit](Sources/InnoDI/InnoDI.docc/lock-safety.md)

<!-- innodi:section installation -->

## Installation und verpflichtendes Validierungs-Plugin

Paket und Zielkonfiguration in der eigenen `Package.swift` ergänzen:

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

`InnoDI` ist das Kernprodukt. Für SwiftUI-Helfer zusätzlich `.product(name: "InnoDISwiftUI", package: "InnoDI")` verwenden. `InnoDITesting` gehört nur in Test- oder Preview-Unterstützungsziele, die generierte Mocks oder Override-Presets benötigen.

**Jedes Ziel**, das einen InnoDI-Container oder eine eigenständige `@DIEnvironmentBridge` deklariert, muss `InnoDIDAGValidationPlugin` einbinden. Das Plugin ist Teil des Korrektheitsvertrags: Es prüft unter anderem Initializer in anderen Dateien, Qualifier-Schatten und den globalen Graphen. Xcode- und Tuist-Projekte folgen der [Integrationsanleitung](Sources/InnoDI/InnoDI.docc/IntegrationGuide.md#build-plugin).

`validateDAG: false` und `INNODI_DISABLE_BUILD_VALIDATION=1` sind begrenzte Ausnahmen, keine normale Produktionskonfiguration. Produktions-CI muss die Build-Validierung eingeschaltet lassen; die genauen Grenzen beschreibt [Plugin Opt-Out](Sources/InnoDI/InnoDI.docc/PluginOptOut.md).

<!-- innodi:section quickstart -->

## Kleinstes Beispiel

Nach der Installation erstellt dieses unverändert aus der englischen README übernommene Beispiel einen Live-Container und einen Container mit Testwert. Bei standardmäßiger MainActor-Isolation des Ziels den Container explizit mit `@MainActor` oder `nonisolated` markieren; das Makro kann diese Build-Einstellung nicht erkennen.

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

## Welche API passt zu welcher Aufgabe?

| Aufgabe | API und wichtige Grenze |
| --- | --- |
| Einen Container definieren | `@DIContainer` für unterstützte, effektiv nicht-generische Structs; `@DIContainerRole` für explizite Rollen, Komponenten und Wurzeln |
| Externe Werte übergeben | `@Input`; keine Factory, kein `Type.self`, kein Property-Initializer und kein `with:` |
| Eine Abhängigkeit wiederverwenden | `@Provide(.shared, ...)`; standardmäßig sofortige Konstruktion, mit `initialization: .onDemand` erst beim ersten Zugriff |
| Bei jedem Zugriff neu konstruieren | `@Provide(.transient, ...)` |
| Geschwister verdrahten | Benannte Parameter einer äußeren Factory-Closure oder `Type.self` mit einem literalen Array wie `with: [\Self.baseURL]`; diese Key-Paths dürfen nur synchrone Provider referenzieren |
| Einen synchronen Zugriff aufschieben | `Lazy<T>`; folgt dem Scope des Ziels und besitzt keinen eigenen Cache |
| Einen transienten Provider wiederholt aufrufen | `Provider<T>`; erfordert ein synchrones `.transient`-Ziel |
| Untercontainer besitzen | `@SubContainer`; Hierarchie und Eingabebindungen explizit festlegen |
| Bereitschaft, Wiederholung und Schließen verwalten | `generateOwned: true`, `makeOwned`, `prepare`, `requireReady`, `withPrepared` |
| SwiftUI anbinden | `InnoDISwiftUI`, `@DIEnvironmentBridge` und generierte Feature-Root-Helfer |

Für `.shared` und `.transient` genau eine Konstruktionsquelle wählen: `factory:`, `asyncFactory:`, `Type.self` oder einen Property-Initializer. Factory-Effekte sind explizit: `asyncFactory:` verwenden und gegebenenfalls `async throws` schreiben. Sie werden nicht automatisch von Abhängigkeiten abgeleitet.

`Lazy<T>` und `Provider<T>` sind synchron und nicht `Sendable`; sie dürfen keine `asyncFactory`-Ziele referenzieren und müssen im ursprünglichen Isolationsbereich bleiben. Sie brechen keine Besitzzyklen. Auch bei `validateDAG: false` bleiben Besitzzyklus-, Deklarations- und explizite Effektprüfungen aktiv.

<!-- innodi:section lifecycle -->

## Asynchrone Bereitschaft und Lebensdauer

- Ein gewöhnlicher `.shared`-Provider mit `asyncFactory:` startet seine Task bereits im Initializer. Dieser Container beendet die Task nicht automatisch
- Bei einem asynchronen `.shared`-Provider mit `initialization: .onDemand` beginnt die Arbeit beim ersten Zugriff. Der Zugriff wirft immer, und `closeAsyncProviders()` schließt diese Provider und bricht laufende Arbeit ab. Containerkopien teilen den logischen Cache; unabhängig initialisierte Container bleiben getrennt
- `generateOwned: true` erzeugt einen separaten Owner und eine Containeransicht. `makeOwned` ist `async throws`, bedeutet aber **nicht bereit**. Bei `prepare` immer `report.isReady` prüfen; `requireReady` wirft bei einem nicht bereiten Ergebnis
- `withPrepared` führt die Operation erst nach erfolgreicher Vorbereitung der ausgewählten Teilstruktur aus und wartet anschließend auf `close()`, auch bei Fehlern. Nicht ausgewählte sofort gestartete Provider können dennoch arbeiten oder fehlschlagen
- Das Abbrechen eines wartenden Aufrufers beendet nur dessen Warten, nicht automatisch die gemeinsam genutzte Arbeit. Explizites Retry gilt für fehlgeschlagene oder abgebrochene Provider; `retryAndRequireReady` ist weder Refresh noch automatische Wiederholungsschleife
- `await owner.close()` schließt den Owner dauerhaft, verhindert spätere asynchrone Zugriffe einschließlich Cache-Zugriffen und fordert den Abbruch besessener Arbeit an. Es wartet nicht auf Factories, die Abbruch ignorieren, ruft kein Service-`shutdown()` auf und entzieht keine bereits ausgegebenen Werte. Geliehene Inputs, synchrone Werte und Kinder bleiben geliehen
- Es gibt kein automatisches Schließen beim Verlassen eines Scopes. Eigene Methoden und Protokollkonformitäten des ursprünglichen Containers werden nicht auf die Owner-Ansicht übertragen

Für Einzelheiten siehe [Owned Containers](Sources/InnoDI/InnoDI.docc/OwnedContainers.md) und [asynchrone Vorbereitung](Sources/InnoDI/InnoDI.docc/AsyncPreparation.md). In SwiftUI gehört das Schließen an den tatsächlichen Lebensdauer-Endpunkt, nicht pauschal in `onDisappear`.

<!-- innodi:section testing -->

## Tests, Overrides und Previews

Das Minimalbeispiel ersetzt `apiClient` über den generierten `Overrides`-Builder. Für eine einzelne Operation bietet `withOverrides` synchrone, werfende, asynchrone und asynchron werfende Varianten. Ein eigener verschachtelter Typ namens `Overrides` ist nicht erlaubt.

`InnoDITesting` ergänzt opt-in generierte Mocks, nebenläufigkeitssicheren Mock-Zustand, generationsabhängiges Zurücksetzen, Interaktionsprüfung und typisierte Override-Presets. Konkrete Deklarationen und Einschränkungen stehen in [Auto Mock](Sources/InnoDI/InnoDI.docc/AutoMock.md); SwiftUI-Previews in [SwiftUI Preview Helper](Sources/InnoDI/InnoDI.docc/SwiftUIPreviewHelper.md).

<!-- innodi:section diagnostics -->

## Diagnose, Migration und CI

Diese Befehle im InnoDI-Repository ausführen; `--root` auf den zu untersuchenden Workspace setzen. Die Testzeile testet das Paket im aktuellen Verzeichnis, auf einer unterstützten Apple-Plattform:

```bash
swift run InnoDI-Doctor --root /path/to/consumer
swift run InnoDI-Migrate --root /path/to/consumer --check
swift run InnoDI-Migrate --root /path/to/consumer --report --output migration-report.json
swift run InnoDI-DependencyGraph --root /path/to/consumer --validate-dag
swift run InnoDI-DependencyGraph --root /path/to/consumer --root-pruning all
swift run InnoDI-DependencyGraph --diff before.json after.json --check-contract
swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
```

`swift run` kann zunächst das jeweilige Werkzeug bauen. Die anschließende Standardanalyse von Doctor selbst bleibt schreibgeschützt.

Doctor ist standardmäßig schreibgeschützt: kein Auflösen von Paketen, kein Build und keine Cache-Löschung. Dynamische Manifeste und unvollständige Tuist-Zuordnungen werden nicht als gesund ausgegeben. Der Migrationsbericht verwendet Exit-Code `0` für unverändert, `1` für notwendige Änderungen und `2` für blockiert. `--check-contract` liefert `5`, wenn sich der Graphvertrag geändert hat; `before.json` und `after.json` müssen vorhandene, zielbezogene JSON-Graphartefakte sein.

Vor schreibenden Migrationsschritten Bericht und [Migrationsanleitung](Sources/InnoDI/InnoDI.docc/MigrationGuide.md#6x--70) lesen. Bei `--apply` gemeldete `RECOVERY`-Dateien nach dem Schließen von Editoren prüfen, bevor sie entfernt werden. Versionshinweise stehen zentral im [Changelog](CHANGELOG.md#701).

<!-- innodi:section documentation -->

## Vertiefung nach Aufgabe

Alle folgenden Fachartikel sind die kanonischen englischen Fassungen. Die entsprechenden gepflegten koreanischen Artikel stehen in [ko.lproj](Sources/InnoDI/InnoDI.docc/ko.lproj); vollständige deutsche DocC-Übersetzungen für 7.0.1 werden hier nicht zugesagt.

- [Konzepte verstehen](Sources/InnoDI/InnoDI.docc/Overview.md)
- [Ersten Container bauen](Sources/InnoDI/InnoDI.docc/Tutorial-01-Hello.md)
- [Inputs übergeben](Sources/InnoDI/InnoDI.docc/Tutorial-02-Inputs.md)
- [Abhängigkeiten verdrahten](Sources/InnoDI/InnoDI.docc/Tutorial-03-Wiring.md)
- [Konkrete Typen verwenden](Sources/InnoDI/InnoDI.docc/Tutorial-04-Concrete.md)
- [Untercontainer aufbauen](Sources/InnoDI/InnoDI.docc/Tutorial-05-SubContainer.md)
- [Containerregeln nachschlagen](Sources/InnoDI/InnoDI.docc/DIContainer.md)
- [Provider und Scopes wählen](Sources/InnoDI/InnoDI.docc/Provide.md)
- [Asynchrone Container besitzen](Sources/InnoDI/InnoDI.docc/OwnedContainers.md)
- [Vorbereitung und Retry planen](Sources/InnoDI/InnoDI.docc/AsyncPreparation.md)
- [Mocks und Tests schreiben](Sources/InnoDI/InnoDI.docc/AutoMock.md)
- [SwiftUI und Previews anbinden](Sources/InnoDI/InnoDI.docc/SwiftUIPreviewHelper.md)
- [SwiftPM, Xcode und Tuist integrieren](Sources/InnoDI/InnoDI.docc/IntegrationGuide.md)
- [Validierung verstehen](Sources/InnoDI/InnoDI.docc/Validation.md)
- [Globale Graphen prüfen](Sources/InnoDI/InnoDI.docc/DAGValidation.md)
- [Diagnosemeldungen beheben](Sources/InnoDI/InnoDI.docc/DiagnosticsGuide.md)
- [Dateiübergreifende Initializer prüfen](Sources/InnoDI/InnoDI.docc/ModuleWideInitDetection.md)
- [Ausnahmen vom Plugin bewerten](Sources/InnoDI/InnoDI.docc/PluginOptOut.md)
- [Grenzen der Validierung verstehen](Sources/InnoDI/InnoDI.docc/PolicyBoundaries.md)
- [Fehlmuster vermeiden](Sources/InnoDI/InnoDI.docc/AntiPatterns.md)
- [Sperren und Dateisysteme prüfen](Sources/InnoDI/InnoDI.docc/lock-safety.md)
- [Laufzeit-Auflösungen verfolgen](Sources/InnoDI/InnoDI.docc/RuntimeTracing.md)
- [Von 6.x auf 7.0 migrieren](Sources/InnoDI/InnoDI.docc/MigrationGuide.md)
- [Von Factory migrieren](Sources/InnoDI/InnoDI.docc/MigratingFromFactory.md)
- [Von Swinject migrieren](Sources/InnoDI/InnoDI.docc/MigratingFromSwinject.md)
- [Die passende Anleitung finden](Sources/InnoDI/InnoDI.docc/DocumentationGuide.md)
- [Assisted Factories und Sammlungen zusammensetzen](Sources/InnoDI/InnoDI.docc/Composition.md)
- [Die API von InnoDITesting nachschlagen](Sources/InnoDITesting/InnoDITesting.docc/InnoDITesting.md)

<!-- innodi:section history -->

Historisch: [deutsche README für 6.0.0](https://github.com/InnoSquadCorp/InnoDI/blob/6.0.0/README.de.md). Diese archivierte Fassung beschreibt nicht die aktuelle API.
