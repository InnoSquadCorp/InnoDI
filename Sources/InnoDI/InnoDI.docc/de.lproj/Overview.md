# ``InnoDI``

Makrogetriebenes Swift-DI mit Validierung in mehreren Schichten.

## Overview

InnoDI macht aus unterstutzten, effektiv nicht-generischen Swift-Structs auf
Dateiebene oder mit nominaler Verschachtelung mit `@DIContainer` und `@Provide`
vollwertige DI-Container. Deklarationen in ausfuhrbaren oder lokalen Scopes,
einschliesslich Funktionen, Closures, Accessors und `switch`-Fallen, werden
nicht unterstutzt. Im Mittelpunkt stehen explizites Wiring, deterministische
Validierung und Graph-Tooling.

Die stabile 4.0.0-Baseline umfasst:

- makrogenerierte Container-APIs
- Compile- und Build-Validierung
- globales Graph-Rendering und DAG-Validierung
- `Lazy<T>` und `Provider<T>`
- `@SubContainer`, `@DIComponent`, `@DIHierarchyRoot`
- SwiftUI-Helfer in `InnoDISwiftUI`

4.1.0 erganzt diese Baseline um Release-Hardening:

- unsafe-filesystem Fail-Fast fur den Lock des Validation Coordinators
- geschichteter Lock mit `O_CREAT | O_EXCL` plus `flock` auf unterstutzten Dateisystemen
- Buildzeit-Diagnosen statt makrosynthetisierter `fatalError`-Accessors
- PR- und Release-Gates, die strict concurrency und die macro-source `fatalError` Allow-List erzwingen
- `@SubContainer` nutzt fur Same-Name-Wiring nur noch `with:`; der `withNames:` Escape Hatch wurde entfernt

## Topics

### Start Here

- <doc:Validation>
- <doc:PolicyBoundaries>
- <doc:IntegrationGuide>
- <doc:ModuleWideInitDetection>
- <doc:DiagnosticsGuide>

### Operations

- <doc:lock-safety>
- <doc:MigrationGuide>

### Container API

- <doc:DIContainer>
- <doc:Provide>
- ``DIComponent()``
- ``DIHierarchyRoot()``
