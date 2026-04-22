# DIContainer

`@DIContainer` markiert einen Typ als InnoDI-Container und erzeugt die
Container-Oberflache.

## Declaration

```swift
@DIContainer(root: Bool = false, validateDAG: Bool = true, mainActor: Bool = false)
```

## Generated Surface

- primary `init(...)`
- verschachtelter Typ `Overrides`
- Convenience-`init(<inputs...>, _ applyOverrides: ...)`
- vier `withOverrides`-Overloads

Alle Container erzeugen Overrides-Scaffolding, solange kein benutzerdefinierter
verschachtelter `Overrides`-Typ existiert.

## Parameters

- `root`: Einstiegspunkt nur fur das Graph-Rendering
- `validateDAG`: aktiviert globale DAG-Validierung und lokale cycle-/
  closure-`with:`-Checks; `false` uberspringt nur diesen Bereich
- `mainActor`: wendet `@MainActor` auf die generierte API an
