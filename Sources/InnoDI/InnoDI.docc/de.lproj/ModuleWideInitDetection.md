# Module-Wide Init Detection

`@DIContainer` erzwingt die `init`-Regel sowohl im Makro als auch im Build.

## Macro Layer

- kein benutzerdefiniertes `init` im annotierten Typ
- kein passendes `init` in derselben Datei-Extension

## Build Layer

- dieselbe Regel wird auf cross-file Extensions erweitert
- mehrdeutige oder nicht unterstützte Fälle bleiben außerhalb der Regel
