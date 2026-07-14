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
- `mainActor`: isoliert Dependency-Accessors, alle generierten Initialisierer,
  `Overrides`, die `applyOverrides`-Funktionstypen von Convenience-
  Initialisierern, `withOverrides`, Child-Overrides und Component-Mounting, die
  Operations-Closures aller vier `withOverrides`-Overloads sowie Feature-Root-
  Helper mit `@MainActor`. Zusammen mit `@DIComponent` erhalten das generierte
  `<Container>Dependencies`-Protokoll und `init(dependencies:_:)` dieselbe
  Isolation; die Component konformiert dem dedizierten Protokoll
  `_InnoDIMainActorComponentMountable`. Components ohne diese Option verwenden
  weiterhin `_InnoDIComponentMountable`. Nicht-`Sendable` generierte Werte
  müssen über einen `@MainActor`-Aufrufer oder durch Erzeugung und Verwendung im
  selben `MainActor.run`-Block auf dem Main Actor bleiben. Ein direktes `await`
  passt für eine isolierte Operation mit `Sendable`-Ergebnis, nicht zum
  Transport des Containers aus dem Actor heraus.
