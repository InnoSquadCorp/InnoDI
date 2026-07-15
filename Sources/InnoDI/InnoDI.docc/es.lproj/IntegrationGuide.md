# Guia de integracion

Use InnoDI como codigo Swift generado junto con validacion en tiempo de build.
La mayoria de las herramientas funcionan mejor cuando tratan la salida de las
macros como detalle de implementacion generado por el compilador y mantienen las
declaraciones de contenedores escritas por el usuario como la superficie de revision.

## Periphery

- Ejecute Periphery con los build settings generados, no con globs de fuentes
  escritos a mano, para que los miembros expandidos por macros sean visibles para
  el compilador.
- Mantenga `@DIContainer`, `@Provide`, `@SubContainer` y los entry points de
  override generados alcanzables mediante tests, sample apps o reglas explicitas
  de retencion cuando solo se invoquen por wiring sin reflection.
- Para reducir ruido de miembros generados, prefiera retener el tipo container o
  sus entry points publicos antes que ignorar todo el modulo.

## SwiftLint

- Aplique lint normalmente al source escrito por el usuario.
- No aplique lint a la salida macro-expanded como si fuera codigo escrito a mano.
- Si su configuracion revisa artifacts de interface generados, excluya los prefijos
  reservados de InnoDI: `_storage_`, `_override_`, `_innoDI` y `_InnoDI`.

## SwiftFormat

- Formatee las declaraciones de contenedores que usted escribe.
- No exija un formatting pass separado sobre snapshots de expansion de macros en
  proyectos consumidores.
- Mantenga atributos y factory closures legibles en el sitio de declaracion; esa
  es la fuente que los reviewers deben inspeccionar.

## Miembros generados por macros

InnoDI genera initializers, storage, overrides y helper closures a partir de las
declaraciones del container. Trate esos miembros generados como parte de la
superficie de API compilada, pero mantenga las dependencias manuales explicitas
en el source del container.

Cuando una herramienta reporte un simbolo generado, mapeelo al `@DIContainer`,
`@Provide` o `@SubContainer` mas cercano antes de decidir si el reporte es accionable.

## Plugin de build

Adjunte `InnoDIDAGValidationPlugin` a cada target que declare containers o un
`@DIEnvironmentBridge` standalone. El full-source pass target-scoped rechaza
shadows de generated qualifiers en declaraciones envolventes o en el mismo
target, asi como qualifier shadows con acceso `public` o `package` visibles en
targets de dependencias importados, que las macros adjuntas no pueden
inspeccionar. Tambien rechaza direct-extension attachments y bridge targets
locales standalone antes de la
compilacion de Swift.

Para un bridge de clase, o un container/bridge anidado en una clase, el
preflight sigue el primer tipo heredado como posible superclase. Cada clase y
typealias recorrido debe ser visible como source en el snapshot del workspace.
Un primer tipo heredado que solo exista en un SDK o binario, que no se resuelva
o que sea ambiguo se rechaza con
`generated-qualifier.inheritance-unverifiable`; use un struct/enum o un adapter
visible como source cuando la jerarquia externa no pueda indexarse. El indice
sintactico conservador rechaza para la generacion del bridge los type members
heredados llamados `Swift` o `SwiftUI`, pero acepta un `InnoDISwiftUI` heredado.
Las declaraciones directas y envolventes `InnoDISwiftUI` siguen reservadas.

El plugin ahora ejecuta el validador DAG in-process
mediante el build coordinator; el ejecutable standalone
`InnoDI-DependencyGraph` sigue disponible para inspeccion local y artifacts de
CI.

Use un SwiftPM scratch path local cuando derived data este en un volumen de red.
El scratch path debe estar en un disco local y ser writable; reemplace `/tmp` por
un directorio temporal local apropiado para su OS o entorno de CI si es necesario.

```sh
swift build --scratch-path /tmp/innodi-cache
```

Consulte <doc:lock-safety> para clasificaciones de filesystem y recuperacion de locks.
