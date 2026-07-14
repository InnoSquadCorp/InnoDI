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
- ubicacion directa, simple y almacenada de instance `var` para `@Provide`
- factories faltantes
- orden de declaracion
- ciclos locales
- resolucion estricta por nombre
- compatibilidad de efectos en edges sibling explicitos
- `init` definidos por el usuario no permitidos
- validez de `asyncFactory`

Los edges sibling explicitos solo vienen de parametros con nombre de la closure
literal raiz de `factory:`/`asyncFactory:`, o de `Type.self` con key paths
literales en `with:`. Factories que no son closures e initializers de property
son fuentes opacas con cero edges y no pueden leer miembros sibling.

`validateDAG: false` no desactiva la validacion de declaraciones ni la
compatibilidad de efectos; solo omite el DAG global, ciclos locales y otros
checks graph-derived.

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
