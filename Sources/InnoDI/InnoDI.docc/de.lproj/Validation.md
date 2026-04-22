# Validation

InnoDI validiert Abhangigkeiten in mehreren Schichten.

## Macro Validation

Makrovalidierung pruft:

- Scope-Regeln
- fehlende Factories
- Deklarationsreihenfolge
- lokale Zyklen
- strikte Namensauflosung
- unzulassige benutzerdefinierte `init`

`validateDAG: false` deaktiviert keine strukturelle Validierung.

## Build Validation

Die koordinierte Build-Pipeline fugt hinzu:

1. cross-file `init`-Validierung
2. semantische Referenzprufung
3. Hierarchievalidierung
4. DAG-Validierung
5. Metrik- und Summary-Artefakte
