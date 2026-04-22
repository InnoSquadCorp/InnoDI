# Validation

InnoDI validiert Abhängigkeiten in mehreren Schichten.

## Macro Validation

Makrovalidierung prüft:

- Scope-Regeln
- fehlende Factories
- Deklarationsreihenfolge
- lokale Zyklen
- strikte Namensauflösung
- unzulassige benutzerdefinierte `init`

`validateDAG: false` deaktiviert keine strukturelle Validierung.

## Build Validation

Die koordinierte Build-Pipeline fügt hinzu:

1. cross-file `init`-Validierung
2. semantische Referenzprüfung
3. Hierarchievalidierung
4. DAG-Validierung
5. Metrik- und Summary-Artefakte
