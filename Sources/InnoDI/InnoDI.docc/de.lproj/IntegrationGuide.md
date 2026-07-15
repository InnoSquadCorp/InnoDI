# Integrationsleitfaden

Verwenden Sie InnoDI als generierten Swift-Quellcode plus Build-Time-Validation.
Die meisten Werkzeuge funktionieren am besten, wenn sie Macro-Ausgabe als vom
Compiler erzeugtes Implementierungsdetail behandeln und die vom Nutzer
geschriebenen Container-Deklarationen als Review-Oberflaeche beibehalten.

## Periphery

- Fuehren Sie Periphery gegen die generierten Build Settings aus, nicht gegen
  handgeschriebene Source-Globs, damit macro-expanded members fuer den Compiler
  sichtbar sind.
- Halten Sie `@DIContainer`, `@Provide`, `@SubContainer` und generierte Override
  Entry Points ueber Tests, Sample Apps oder explizite Retention-Regeln erreichbar,
  wenn sie nur durch reflection-free wiring aufgerufen werden.
- Reduzieren Sie generated-member noise bevorzugt durch Retention des Container-Typs
  oder seiner public entry points, statt das ganze Modul zu ignorieren.

## SwiftLint

- Linten Sie user-authored source normal.
- Linten Sie macro-expanded output nicht so, als waere er handgeschriebener Code.
- Wenn Ihre Konfiguration generated interface artifacts prueft, schliessen Sie
  die reservierten InnoDI-Prefixe aus: `_storage_`, `_override_`, `_innoDI`
  und `_InnoDI`.

## SwiftFormat

- Formatieren Sie die Container-Deklarationen, die Sie schreiben.
- Verlangen Sie in Consumer-Projekten keinen separaten Formatting-Pass ueber
  Macro-Expansion-Snapshots.
- Halten Sie Attribute und Factory Closures an der Deklarationsstelle lesbar;
  diese Source ist die Flaeche, die Reviewer pruefen sollten.

## Von Macros generierte Member

InnoDI erzeugt Initializer, Storage, Overrides und Helper Closures aus
Container-Deklarationen. Behandeln Sie diese generated members als Teil der
kompilierten API-Oberflaeche, halten Sie manuelle Dependencies aber explizit im
Source-Container.

Wenn ein Tool ein generiertes Symbol meldet, ordnen Sie es zuerst der naechsten
`@DIContainer`-, `@Provide`- oder `@SubContainer`-Deklaration zu, bevor Sie
entscheiden, ob der Report actionable ist.

## Build-Plugin

Haengen Sie `InnoDIDAGValidationPlugin` an jedes Target, das Container oder eine
eigenstaendige `@DIEnvironmentBridge`-Deklaration enthaelt. Der target-scoped
Full-Source-Pass lehnt Generated-Qualifier-Verschattungen in umschliessenden
Deklarationen und im selben Target sowie sichtbare Qualifier-Verschattungen mit
`public`- oder `package`-Zugriff in importierten Dependency-Targets ab, die
Attached Macros nicht sehen koennen. Er lehnt auch direkte Extension-Attachments
und standalone lokale Bridge-Targets vor der
Swift-Kompilierung ab.

Bei einer Class-Bridge oder einem in einer Klasse verschachtelten Container bzw.
einer Bridge folgt der Preflight dem ersten geerbten Typ als potenzieller
Superklasse. Jede durchlaufene Klasse und jeder Typealias muss im Workspace
Snapshot als Source sichtbar sein. Ein nur im SDK oder Binary vorhandener,
unaufgeloester oder mehrdeutiger erster geerbter Typ wird mit
`generated-qualifier.inheritance-unverifiable` abgelehnt. Verwenden Sie einen
Struct/Enum oder einen source-sichtbaren Adapter, wenn die externe Hierarchie
nicht indexiert werden kann. Der konservative Syntax-Index lehnt geerbte
Typmember namens `Swift` oder `SwiftUI` fuer die Bridge-Generierung ab, akzeptiert
aber ein geerbtes `InnoDISwiftUI`. Direkte und umschliessende Deklarationen mit
dem Namen `InnoDISwiftUI` bleiben reserviert.

Das Plugin fuehrt den DAG-Validator jetzt in-process
ueber den Build Coordinator aus; das standalone Executable
`InnoDI-DependencyGraph` bleibt fuer lokale Inspektion und CI-Artefakte
verfuegbar.

Verwenden Sie einen lokalen SwiftPM scratch path, wenn derived data auf einem
Network Volume liegt. Der scratch path muss auf einer lokalen Disk liegen und
schreibbar sein; ersetzen Sie `/tmp` je nach OS oder CI-Umgebung durch ein
passendes lokales Temporary Directory.

```sh
swift build --scratch-path /tmp/innodi-cache
```

Filesystem-Klassen und Lock-Recovery sind in <doc:lock-safety> beschrieben.
