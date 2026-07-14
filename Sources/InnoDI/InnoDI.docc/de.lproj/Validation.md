# Validation

InnoDI validiert Abhängigkeiten in mehreren Schichten.

## Macro Validation

Makrovalidierung prüft:

- Scope-Regeln
- direkte, einfache, gespeicherte Instanz-`var`-Platzierung von `@Provide`
- fehlende Factories
- Deklarationsreihenfolge
- lokale Zyklen
- strikte Namensauflösung
- Effektkompatibilität expliziter Sibling-Kanten
- unzulassige benutzerdefinierte `init`

Explizite Sibling-Kanten stammen nur aus benannten Parametern der root
`factory:`-/`asyncFactory:`-Closure-Literal oder aus `Type.self` mit literalen
`with:`-Key-Paths. Nicht-Closure-Factories und Property-Initializer sind opake
Zero-Edge-Quellen und dürfen keine Sibling-Member referenzieren.

`validateDAG: false` deaktiviert weder Deklarationsvalidierung noch
Effektkompatibilität; nur globale DAG-, lokale cycle- und andere graph-derived
Checks werden übersprungen.

## Build Validation

Die koordinierte Build-Pipeline fügt hinzu:

1. cross-file `init`-Validierung
2. semantische Referenzprüfung
3. Hierarchievalidierung
4. DAG-Validierung
5. Metrik- und Summary-Artefakte
