# Policy Boundaries

InnoDI bleibt deterministisch, indem einige Grenzen explizit gesetzt werden.

## Erkennung benutzerdefinierter `init`

- Die Makrovalidierung lehnt benutzerdefinierte `init` nur im Body des
  annotierten Typs ab.
- Der erforderliche Full-Source-Preflight von `InnoDIDAGValidationPlugin` lehnt
  `init` in passenden same-file und cross-file Extensions ab, einschließlich
  Deklarationen innerhalb von `#if`-Zweigen.
- Ohne das Build-Validation-Plugin ist das extensionsweite Verbot nicht
  gewährleistet, da Attached Macros benachbarte Extensions nicht zuverlässig
  untersuchen können.

## Matching Strategy

- Gemeinsames nominales Modell für Makros, Core und Graph-CLI
- Unterstützung für verschachtelte Pfade wie `Outer.Container`
- Ausschluss von generischen Argument-Extensions und `where`-Extensions
- Mehrdeutige Fälle bleiben außerhalb der semantischen Regel

## Provider-Effekte

- Ein synchroner Provider kann von synchronen, `async` und `async throws`
  Factories konsumiert werden.
- Ein `async` Provider benötigt einen `async` oder `async throws` Consumer.
- Ein `async throws` Provider benötigt einen `async throws` Consumer.
- Effekte werden nicht aus Abhängigkeiten abgeleitet. Der Consumer gibt
  `asyncFactory:` und bei Bedarf eine `async throws` Closure explizit an.
- `Lazy<T>` und `Provider<T>` sind synchrone Deferred-Wrapper und lehnen
  asynchrone Targets ab.

## Isolation und Sendability

- Container halten ihren generierten Speicher innerhalb des Containerwerts.
  InnoDI trägt Abhängigkeiten nicht in eine globale Registry ein.
- `mainActor: true` isoliert Dependency-Accessors, alle generierten
  Initialisierer, `Overrides`, die `applyOverrides`-Funktionstypen von
  Convenience-Initialisierern, `withOverrides`, Child-Overrides und Component-
  Mounting, die Operations-Closures aller vier `withOverrides`-Overloads sowie
  generierte Feature-Root-Helper. Dies ist die bevorzugte Form für UI-Root-
  Container.
- Zusammen mit `@DIComponent` werden das generierte Dependency-Protokoll,
  `init(dependencies:_:)` und der Override-Closure-Typ mit `@MainActor`
  isoliert; die Component konformiert dem dedizierten Protokoll
  `_InnoDIMainActorComponentMountable`. Gewöhnliche Components verwenden
  weiterhin das nicht isolierte `_InnoDIComponentMountable`. Generische
  Mounting-Helper müssen in 5.0 getrennte Constraints und Closure-Typen für
  beide Marker bereitstellen.
- Generierte Container-/Component-Werte und nicht-`Sendable` Abhängigkeiten
  müssen auf dem Main Actor bleiben. Verwenden Sie bevorzugt einen
  `@MainActor`-Aufrufer oder einen `MainActor.run`-Block, der die Werte sowohl
  erzeugt als auch verbraucht. Ein direktes `await` ist passend, wenn die
  isolierte Operation ein `Sendable`-Ergebnis liefert, etwa das Ergebnis einer
  `withOverrides`-Operation; einen nicht-`Sendable` Container darf es nicht aus
  dem Actor heraus transportieren.
- `Lazy<T>` und `Provider<T>` sind kein Transportmechanismus zwischen Actors.
  Sie bleiben in der Isolation des Containers, sofern `T` und der umgebende
  Aufrufpfad nicht bereits sicher übertragen werden können.
- Nicht-`Sendable` Abhängigkeiten sollten über explizite Containergrenzen
  weitergegeben und von der App-Schicht isoliert werden, statt sie hinter
  globalem Lookup zu verbergen.
