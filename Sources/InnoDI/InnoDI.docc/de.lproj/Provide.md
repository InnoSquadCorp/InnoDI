# Provide

`@Provide` deklariert ein Container-Mitglied und seine Erzeugungsstrategie.

InnoDI 5.0 unterstützt `@Provide` nur auf einer direkten, einfachen,
gespeicherten Instanz-`var` im selben unterstützten `@DIContainer`-struct.
`let`, computed/observed Properties, `lazy`, `weak`, `unowned`, `static`/`class`,
eigenständige und indirekt verschachtelte Verwendungen werden abgelehnt. Der
generierte Accessor gehört InnoDI; `_InnoDIProvideAccessor` darf nicht manuell
angefügt werden.

Property Wrapper, bedingte oder unbekannte Attribute, Setter-
Zugriffsmodifikatoren wie `private(set)` und eigene Global-Actor-Attribute
werden ebenfalls abgelehnt. Außer `@Provide` selbst ist kein im Quelltext
geschriebenes Property-Level-Attribut erlaubt; das schließt `@MainActor` ein.
Fordern Sie Actor-Isolation mit `@DIContainer(mainActor: true)` an. Die von
InnoDI auf Provider-Deklaration und Accessor erzeugten Isolationsattribute
dienen ausschließlich der internen Compiler-Unterstützung. Eine vollständige
`@Provide`-Member-Deklaration in `#if` erzeugt
`provide.conditional-declaration-unsupported`; lassen Sie die Deklaration
außerhalb der Bedingung und verzweigen Sie in der Factory oder injizierten
Implementierung.

Pro Property ist genau ein `@Provide` zulässig; doppelte Attribute werden mit
`provide.duplicate-attribute` abgelehnt. Der explizite Property-Typ darf weder
ein opakes `some Protocol` noch ein implicitly unwrapped optional `T!` sein.
Migrieren Sie zu `any Protocol` beziehungsweise zu explizitem `T` / `T?`.
Eine absichtlich gefälschte Kombination aus Compiler-Support-Accessor und
einem weiteren Property Wrapper kann neben der InnoDI-Misuse-Diagnose auch
strukturelle Swift-Diagnosen auslösen.

## Declaration

```swift
@Provide(
    _ scope: DIScope = .shared,
    _ type: Any.Type? = nil,
    with dependencies: [AnyKeyPath] = [],
    factory: Any? = nil,
    asyncFactory: Any? = nil,
    escaping: Bool = false
)
```

## Input-Werte und escaping Funktionen

Generierte `.input`-Initializer-Parameter sind eager Werte des deklarierten
Typs `T`. Swift wertet jedes Argument vor dem Initializer-Aufruf aus, daher
bleiben `try makeValue()` und `await makeValue()` gültige Argumentausdrücke.
Direkt geschriebene non-optionale Funktionstypen werden automatisch erkannt und
als escaping Parameter erzeugt. Ist ein non-optionaler Funktionstyp hinter
einem Typealias verborgen, deklarieren Sie `@Provide(.input, escaping: true)`.

`escaping:` muss ein literales Bool sein und ist nur für `.input` gültig.
Offensichtliche Nichtfunktions- und optionale Funktionsformen werden mit
stabilen InnoDI-Diagnosen abgelehnt. Identifier-/Member-Typen werden konservativ
akzeptiert, da ein Attached Macro beliebige Aliase nicht auflösen kann; Swift
kann eine eigene Diagnose ergänzen, wenn der Alias keine non-optionale Funktion
ist.

## Rules

- `factory:`, `asyncFactory:`, `Type.self` und Property-Initializer sind
  gegenseitig ausschließende Konstruktionsquellen.
- `.input` erlaubt keine Konstruktionsquelle und kein `with:`.
- `.shared` und `.transient` brauchen genau eine Konstruktionsquelle.
- `with:` ist nur mit `Type.self` und synchronen Providern zulässig.
- `asyncFactory` wird für `.shared` und `.transient` unterstützt und muss eine
  `async`-Closure sein.
- Der deklarierte Property-Typ bestimmt die Speicherform: Ein konkreter
  Nominaltyp verwendet konkreten Speicher, `any Protocol` existenziellen Speicher.

## Sibling-Edge-Vertrag

- Nur benannte Parameter der root `factory:`-/`asyncFactory:`-Closure-Literal
  deklarieren Sibling-Kanten. Verschachtelte Closures und beliebige Identifier
  erzeugen keine Kanten.
- `Type.self` deklariert Kanten aus einem literalen `with:`-Array. Jeder Eintrag
  muss exakt die kanonische Direct-Member-Schreibweise `\Self.member` verwenden,
  zum Beispiel `with: [\Self.config]`; `with: []` ist ebenfalls gültig. Benannte
  Container-, modulqualifizierte und Typealias-Roots sowie verschachtelte
  Komponenten, Optional Chaining, Subscripts und berechnete Elemente werden
  abgelehnt. Alle Targets müssen synchron konstruiert werden.
- Nicht-Closure-`factory:`-Ausdrücke und Property-Initializer sind opake
  Zero-Edge-Quellen und dürfen keine Sibling-Member referenzieren. Verwenden Sie
  root-Closure-Parameter oder ein qualifiziertes globales/statisches Symbol.

## Kompatibilität von Provider-Effekten

Factory-Effekte werden explizit angegeben und nicht aus Abhängigkeiten
abgeleitet. Verwenden Sie `asyncFactory:` für einen asynchronen Consumer und
deklarieren Sie die Closure als `async throws`, wenn sie einen werfenden
asynchronen Provider konsumiert. Die Prüfung gilt auch mit
`validateDAG: false`.

| Provider | synchroner Consumer | `async` Consumer | `async throws` Consumer |
|---|---:|---:|---:|
| synchron | erlaubt | erlaubt | erlaubt |
| `async` | abgelehnt | erlaubt | erlaubt |
| `async throws` | abgelehnt | abgelehnt | erlaubt |

`Lazy<T>` und `Provider<T>` bleiben synchrone Deferred-Wrapper. Beide lehnen
Targets ab, die mit `asyncFactory:` konstruiert werden.
