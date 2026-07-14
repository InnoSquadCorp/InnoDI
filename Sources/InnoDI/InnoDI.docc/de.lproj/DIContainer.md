# DIContainer

`@DIContainer` markiert einen unterstutzten, effektiv nicht-generischen Struct
als InnoDI-Container und erzeugt die Container-Oberflache.

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

Der aktuelle Swift-Compiler lasst beim Erweitern eines attached macro auf einem
Typ in einem computed-property-Body den Accessor-Kontext weg. Das
Build-Validation-Plugin und die Dependency-Graph-CLI scannen den vollstandigen
Quellbaum und erzwingen die Ablehnung dieses Randfalls. Binden Sie das Plugin an
jedes Target an, das Container deklariert.

## Declaration

```swift
@DIContainer(root: Bool = false, validateDAG: Bool = true, mainActor: Bool = false)
```

## Generated Surface

- primary `init(...)`
- verschachtelter Typ `Overrides`
- Convenience-`init(<inputs...>, _ applyOverrides: ...)`
- vier `withOverrides`-Overloads

Jeder unterstutzte Container erzeugt Overrides-Scaffolding, solange kein
benutzerdefinierter verschachtelter `Overrides`-Typ existiert.

## Parameters

- `root`: Einstiegspunkt nur fur das Graph-Rendering
- `validateDAG`: aktiviert globale DAG-Validierung und lokale cycle-/
  closure-`with:`-Checks; `false` uberspringt nur diesen Bereich
- `mainActor`: wendet `@MainActor` auf die generierte API an
