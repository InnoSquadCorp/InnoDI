# Module-Wide Init Detection

`@DIContainer` aplica restricciones de `init` personalizado en la macro y en
la validacion de build.

## Macro Layer

La validación de la macro rechaza `init` personalizados solo en el cuerpo del
tipo anotado. Una macro adjunta no puede inspeccionar de forma fiable las
extensiones hermanas del archivo fuente.

## Capa de build obligatoria

Conecta `InnoDIDAGValidationPlugin` a cada target que declare contenedores. Su
preflight de todo el código fuente rechaza `init` en extensiones coincidentes
del mismo archivo y de otros archivos, incluidas las declaraciones dentro de
ramas `#if`, antes de la validación semántica y DAG.

Sin el plugin de validación de build, no se garantiza la prohibición de `init`
en todas las extensiones.

## Boundaries

- se soportan rutas anidadas
- se excluyen extensiones con argumentos genericos
- se excluyen extensiones con `where`
- los casos ambiguos quedan fuera de la regla determinista
