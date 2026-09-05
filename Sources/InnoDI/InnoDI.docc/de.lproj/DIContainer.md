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
`switch`-Falle. Diese Grenze gilt ebenso fur eine `@DIContainerRole` mit Component-Rolle.
Verschieben Sie Laufzeit- oder
typspezifischen Zustand hinter Protokollabhangigkeiten oder `@Input`.

Ein explizit `private` deklarierter Container wird ebenfalls abgelehnt, weil
Sibling-Container seine generierte Mount-Oberflache nicht erreichen. Verwenden
Sie `fileprivate` fur file-lokales Mounting oder einen Container mit
Default-Zugriff in einem privaten Namespace.

Der aktuelle Swift-Compiler lasst beim Erweitern eines attached macro auf einem
Typ in einem computed-property-Body den Accessor-Kontext weg. Das
Build-Validation-Plugin und die Dependency-Graph-CLI scannen den vollstandigen
Quellbaum und erzwingen die Ablehnung dieses Randfalls. Binden Sie das Plugin an
jedes Target an, das Container deklariert.

## Declaration

```swift
@DIContainer(validateDAG: Bool = true)
@DIContainerRole(role: String, mainActor: Bool = false, validateDAG: Bool = true)
```

## Generated Surface

- primary `init(...)`
- verschachtelter Typ `Overrides`
- Convenience-`init(<inputs...>, _ applyOverrides: ...)`
- vier `withOverrides`-Overloads

Für Container ohne `mainActor: true` sind die generierten `async`- und
`async throws`-`withOverrides`-Methoden sowie ihre Operation-Closure-Typen
`nonisolated(nonsending)`. Sie behalten den Actor-Executor des Aufrufers, sodass
beliebige non-`Sendable` Container- und Closure-Werte keine Isolationsgrenze
überschreiten. Synchrone Overloads bleiben unverändert. Mit `mainActor: true`
bleiben alle `withOverrides`-Overloads und Operation-Closures `@MainActor`.

Jeder Container, auch ohne verwaltete Member, erzeugt das vollstandige
Overrides-Scaffolding. Ein benutzerdefinierter verschachtelter `Overrides`-Typ
ist in InnoDI 6.0 nicht unterstutzt und erzeugt
`container.overrides-name-conflict`; benennen Sie ihn um, damit das Makro die
mountbare Override-ABI besitzen kann.

Das Makro erzeugt ausserdem den reservierten Compiler-Support-Alias
`_InnoDIMountOverrides = Overrides` fur generierten Parent-Mount-Code. Diesen
unterstrichenen Namen nicht direkt deklarieren oder referenzieren.

Jedes gespeicherte Instanz-Member muss `@Provide` oder `@SubContainer`
verwenden; berechnete und Typ-Properties bleiben verfugbar. So besitzt der
synthetisierte Initialisierer den gesamten Zustand und verhindert einen Drift
der Memberwise-Initializer-ABI.

Jedes `@Provide` muss eine direkte, einfache, gespeicherte Instanz-`var` dieses
struct sein. Accessor-/Observer-Blöcke, `let`, `lazy`, `weak`, `unowned`,
`static`/`class`, eigenständige und indirekt verschachtelte Provider werden
abgelehnt; generierte Accessors dürfen nicht manuell angefügt werden.

Sibling-Kanten stammen nur aus benannten Parametern von root
`factory:`-/`asyncFactory:`-Closure-Literalen oder aus `Type.self` mit
literalen `with:`-Key-Paths. Nicht-Closure-Factories und Property-Initializer
sind opake Zero-Edge-Quellen und dürfen keine Sibling-Member referenzieren.
Die Effektkompatibilität bleibt auch mit `validateDAG: false` verpflichtend.

## Parameters

- `root`: Einstiegspunkt nur fur das Graph-Rendering
- `validateDAG`: aktiviert globale DAG- und lokale graph-derived Checks;
  `false` uberspringt globalen DAG und lokale cycle-Checks, aber nicht
  Deklarationsvalidierung oder Effektkompatibilität expliziter Sibling-Kanten
- `mainActor`: isoliert Dependency-Accessors, alle generierten Initialisierer,
  `Overrides`, die `applyOverrides`-Funktionstypen von Convenience-
  Initialisierern, `withOverrides`, Child-Overrides und Component-Mounting, die
  Operations-Closures aller vier `withOverrides`-Overloads sowie Feature-Root-
  Helper mit `@MainActor`. Mit der Component-Rolle erhalten das generierte
  `<Container>Dependencies`-Protokoll und `init(dependencies:_:)` dieselbe
  Isolation; die Component konformiert dem dedizierten Protokoll
  `_InnoDIMainActorComponentMountable`. Components ohne diese Option verwenden
  weiterhin `_InnoDIComponentMountable`. Nicht-`Sendable` generierte Werte
  müssen über einen `@MainActor`-Aufrufer oder durch Erzeugung und Verwendung im
  selben `MainActor.run`-Block auf dem Main Actor bleiben. Ein direktes `await`
  passt für eine isolierte Operation mit `Sendable`-Ergebnis, nicht zum
  Transport des Containers aus dem Actor heraus.
