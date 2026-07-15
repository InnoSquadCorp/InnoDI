# Module-Wide Init Detection

`@DIContainer` erzwingt die `init`-Regel sowohl im Makro als auch im Build.

## Macro Layer

Die Makrovalidierung lehnt benutzerdefinierte `init` nur im Body des annotierten
Typs ab. Attached Macros können benachbarte Extensions in derselben Quelldatei
nicht zuverlässig untersuchen.

## Erforderliche Build-Schicht

`InnoDIDAGValidationPlugin` muss an jedes Target gebunden werden, das Container
deklariert. Sein Full-Source-Preflight lehnt `init` in passenden same-file und
cross-file Extensions ab, einschließlich Deklarationen innerhalb von `#if`-
Zweigen.

Ohne das Build-Validation-Plugin ist das Verbot von `init` in allen Extensions
nicht gewährleistet. Mehrdeutige oder nicht unterstützte Fälle bleiben
außerhalb der deterministischen Regel.
