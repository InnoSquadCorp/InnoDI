# Validation

InnoDI valida definiciones de dependencias en capas.

## Read This Next

1. `README.es.md`
2. este documento
3. <doc:PolicyBoundaries>
4. <doc:ModuleWideInitDetection>

## Macro Validation

La validacion de macros revisa:

- reglas de scope
- factories faltantes
- orden de declaracion
- ciclos locales
- resolucion estricta por nombre
- `init` definidos por el usuario no permitidos
- validez de `asyncFactory`

`validateDAG: false` no desactiva la validacion estructural.

## Build Validation

El pipeline coordinado agrega:

1. validacion cross-file de `init`
2. checks de referencias semanticas
3. validacion de jerarquia
4. validacion DAG
5. artefactos de metricas y resumen

## Global DAG Validation

```bash
swift run InnoDI-DependencyGraph --root . --validate-dag
```

## Artifacts

- `validation-metrics.json`
- `validation-summary.md`
- `dag-validation-metrics.json`
- `dag-validation-summary.md`
