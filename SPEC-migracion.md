# SPEC: reorganización de invo.py + contenido.yml

Este documento es la especificación completa de la migración. Está pensado para
ejecutarse de forma autónoma con `/goal`. Todo lo que necesitás saber para tomar
decisiones está acá; **no inventes criterios que no estén escritos**.

---

## 0. Contexto

Repo de material didáctico de Investigación Operativa (UTN.BA, curso I4051).
Contiene PDFs de slides y apuntes, notebooks de Jupyter y algún xlsx, organizados
por unidad temática con subcarpetas `teoria/`, `practica/` y `casos/`.

El índice del curso —26 clases— está hardcodeado en una tabla enorme del `README.md`,
con badges de shields.io que linkean a archivos del repo y a notebooks abiertos en
Google Colab.

Problemas actuales:

- El índice es la única fuente de verdad y es puramente manual: se desincroniza del
  disco sin que nada lo detecte.
- Las convenciones de nombres son inconsistentes (prefijos `TEO_`/`PRA_`/`CAS_`/`TEMP_`,
  mezcla de `snake_case` y `kebab-case`, tildes en nombres de archivo).
- Algunos recursos son carpetas y otros archivos sueltos, lo que obliga a todo script
  a manejar dos casos.

## 1. Objetivo

Reorganizar el repo completo bajo una convención estricta y uniforme, y extraer el
índice del curso a un `contenido.yml` que pase a ser la única fuente de verdad, desde
la cual se regenera la tabla del `README.md`.

**Fuera de alcance en esta migración:** el sitio de GitHub Pages (MkDocs Material +
mkdocs-jupyter + mike). Viene después. No crees `mkdocs.yml`, ni workflows de
Actions, ni la carpeta `docs/`.

## 2. Condición de finalización

```
python scripts/validar.py sale con código 0, el árbol de trabajo de git está limpio,
y MIGRACION.md existe y documenta todas las decisiones tomadas.
```

`validar.py` es parte del entregable y se escribe **antes** de mover cualquier
archivo. Su especificación está en la sección 7.

## 3. Principio rector

> **El orden pedagógico vive en `contenido.yml`, no en el filesystem.**

El filesystem describe *qué es* cada recurso. El YAML describe *cuándo se dicta*.

Corolario operativo: **está prohibido numerar carpetas por clase** (`01-simulacion/`,
`clase-03/`, etc.). El orden de las unidades cambia entre cuatrimestres y renumerar
carpetas rompería paths por una razón puramente cosmética.

## 4. Estructura objetivo

```
contenido.yml
MIGRACION.md
scripts/
  generar.py
  validar.py
paginas/                        páginas escritas a mano (home, cómo cursar, bibliografía)
material/
  fundamentos/
  simulacion/
    teoria/<tema>/
    practica/<tema>/
    casos/<tema>/
  markov/
  filas-de-espera/
  proyectos/
  optimizacion/
  inventarios/
  externos/                     material de terceros
```

### Tres reglas, sin excepción

**R1 — Todo recurso es una carpeta.** Aunque contenga un solo archivo. No pueden
quedar `.pdf`, `.ipynb` ni `.xlsx` sueltos directamente dentro de `teoria/`,
`practica/` o `casos/`.

**R2 — Los archivos se nombran por rol, no por tema.** El tema ya está en el nombre
de la carpeta contenedora. Vocabulario cerrado de nombres de archivo permitidos:

| Archivo | Uso |
|---|---|
| `slides.pdf` | Presentación proyectada en clase |
| `apunte.pdf` | Texto extenso para leer, no proyectado |
| `enunciado.pdf` | Consigna de un ejercicio |
| `resolucion.pdf` | Resolución de un ejercicio |
| `formulario.pdf` | Hoja de fórmulas / tabla de referencia |
| `notebook.ipynb` | Notebook principal del recurso |
| `datos.xlsx` | Datos de entrada |

Si un recurso necesita dos archivos del mismo rol, se sufijan con un ordinal:
`apunte-1.pdf`, `apunte-2.pdf`. Si necesita un rol que no está en la tabla, **detenerse
y preguntar** (ver sección 8).

**R3 — Nombres de carpeta en ASCII, kebab-case, sin prefijos.** Sin tildes, sin `ñ`,
sin espacios, sin mayúsculas. Los prefijos `TEO_`/`PRA_`/`CAS_` son redundantes dentro
de `teoria/`/`practica/`/`casos/` y se eliminan. El slug de la carpeta se deriva del
título del recurso en el README, no del nombre de archivo actual.

## 5. Reglas de decisión pre-tomadas

Estas son las decisiones que en una sesión interactiva se consultarían. Ya están
tomadas. Aplicalas literalmente.

| Situación | Decisión |
|---|---|
| `introduccion_repaso/` y `recursos_python/` | Ambas van a `material/fundamentos/`, conservando la separación `teoria/`/`practica/`. El material de Python va a `material/fundamentos/practica/`. |
| `general/PRA_guia-ejercicios-palazzo.pdf` | Es obra de un tercero. Va a `material/externos/guia-ejercicios-palazzo/apunte.pdf`, con un `README.md` en esa carpeta indicando autoría y que **no** está cubierta por la licencia del repo. |
| Prefijo `TEMP_` | Se elimina del nombre. El recurso se marca con `provisorio: true` en `contenido.yml`. No se borra nada. |
| Un recurso referenciado desde dos clases distintas | Vive físicamente una sola vez. En `contenido.yml` la segunda aparición lo referencia por su ruta, sin duplicar el archivo. |
| Archivo en el repo que el README no referencia (huérfano) | **No se borra ni se mueve.** Queda donde está y se lista en `material/SIN-ASIGNAR.md` con su path. |
| Entrada del README que apunta a un archivo inexistente (link roto) | Se elimina la entrada de `contenido.yml` y se registra en `MIGRACION.md` bajo "links rotos preexistentes". |
| Dos recursos que colapsan al mismo slug | Se desambigua con un sufijo derivado de la unidad o del número de ejercicio. Registrar la colisión en `MIGRACION.md`. |
| Un recurso con dos PDFs de rol distinto (ej. `ejercicio-filas-10`: un apunte y unas slides) | Se conservan ambos con sus roles correspondientes: `enunciado.pdf` y `slides.pdf`. |
| Notebook cuyo link del README apunta a `github.com/.../blob/...` en vez de a Colab | Normalizar: en el generador, todo `.ipynb` produce badge de Colab. |
| Fuentes de PDFs (`.tex`, `.pptx`, etc.) si existen | Van a `fuentes/` dentro de la carpeta del recurso. Si `.gitignore` las excluye, **no** modificar `.gitignore`; anotarlo en `MIGRACION.md`. |

## 6. Fases

Ejecutar en orden. Cada fase termina en un commit propio.

### Fase 1 — Inventario y validador

1. Recorrer el árbol de archivos completo.
2. Parsear la tabla del `README.md` y extraer las 26 clases con sus recursos.
3. Producir `MIGRACION.md` con: tabla completa `path actual → path propuesto → rol`,
   lista de huérfanos, lista de links rotos, lista de colisiones de slug, lista de
   notebooks cuyo path cambia (ruptura de Colab), y si existen fuentes de PDFs.
   **Sin abreviar ni poner "etc.": todos los archivos, uno por uno.**
4. Escribir `scripts/validar.py` según la sección 7.
5. Registrar el estado de partida: `git ls-tree -r HEAD --format='%(objectname) %(path)'`
   guardado en `.migracion-baseline` (este archivo se borra al final).

Commit: `chore: inventario y validador de migración`.

### Fase 2 — Movimiento de archivos

Todos los `git mv` en **un único commit**, sin ningún cambio de contenido mezclado.
Esto preserva `git log --follow` y hace el diff revisable de un vistazo.

Usar `git mv` siempre, nunca `mv`. No borrar ningún archivo. No editar el contenido
de ningún PDF, notebook o xlsx.

Commit: `refactor: reorganizar material bajo convención uniforme`.

### Fase 3 — contenido.yml

Diseñar el esquema y poblarlo con las 26 clases. Campos mínimos por recurso: unidad,
tipo (`teoria`/`practica`/`casos`), título, slug de carpeta, clase asignada.

Los recursos concretos (qué archivos hay dentro de cada carpeta) **no se declaran**:
el generador los descubre escaneando, apoyándose en R1 y R2. Si al implementarlo
resulta que el descubrimiento no se sostiene contra los archivos reales, detenerse
y reportar (sección 8).

Commit: `feat: contenido.yml como fuente única del índice`.

### Fase 4 — Generador

`scripts/generar.py` lee `contenido.yml` y reescribe el bloque de tabla del `README.md`
entre los marcadores `<!-- AUTO:inicio -->` y `<!-- AUTO:fin -->`.

- Agregar los marcadores la primera vez.
- **No tocar el resto del README**: equipo docente, bibliografía, licencia,
  recursos generales.
- Las URLs de Colab y los badges de shields.io se derivan del rol y del path. No se
  escriben a mano en el YAML.
- Generar dos vistas desde los mismos datos: índice por clase (cronológico) e índice
  por unidad temática.
- El generador debe ser **idempotente**: correrlo dos veces seguidas no produce diff.

Commit: `feat: generar índice del README desde contenido.yml`.

### Fase 5 — Cierre

Actualizar `LICENSE.md` para excluir explícitamente `material/externos/`. Borrar
`.migracion-baseline`. Completar `MIGRACION.md` con las decisiones efectivamente
tomadas y las desviaciones respecto de este spec.

Commit: `docs: registro de migración y ajuste de licencia`.

## 7. Especificación de `scripts/validar.py`

Sale 0 solo si **todas** estas condiciones se cumplen. Cada fallo debe imprimir qué
regla se violó y en qué path.

1. **Integridad**: el conjunto de hashes de blob del árbol actual contiene todos los
   hashes de `.migracion-baseline`. Ningún archivo se perdió ni se modificó en
   contenido. *(Esta es la verificación más importante: si falla, algo se borró.)*
2. **R1**: no hay archivos sueltos en `material/*/teoria|practica|casos/`. Todo es carpeta.
3. **R2**: todo nombre de archivo dentro de una carpeta de recurso pertenece al
   vocabulario cerrado de roles (o su forma sufijada con ordinal).
4. **R3**: todo nombre de carpeta y archivo bajo `material/` es ASCII, kebab-case, sin
   prefijos `TEO_`/`PRA_`/`CAS_`/`TEMP_`.
5. **Esquema**: `contenido.yml` parsea y valida contra el esquema declarado.
6. **Sin referencias colgantes**: toda carpeta referenciada desde `contenido.yml`
   existe en disco.
7. **Sin huérfanos silenciosos**: toda carpeta de recurso bajo `material/` está
   referenciada por `contenido.yml` *o* listada en `material/SIN-ASIGNAR.md`.
8. **Idempotencia**: correr `generar.py` no produce diff en el árbol de trabajo.
9. **Links vivos**: todo link relativo del `README.md` resuelve a un archivo existente.
10. **Colab bien formado**: toda URL de Colab del README tiene la forma
    `colab.research.google.com/github/investigacion-operativa-utn/invo.py/blob/main/<path>`
    y `<path>` existe y termina en `.ipynb`.
11. **Sin numeración de clase en paths**: ninguna carpeta bajo `material/` matchea
    `^\d+[-_]` ni contiene `clase`.

## 8. Cuándo detenerse y pedir intervención

Detener el loop, escribir el estado en `MIGRACION.md` y devolver el control si:

- El check 1 (integridad) falla en cualquier momento.
- Un recurso necesita un rol de archivo que no está en la tabla de R2.
- El descubrimiento automático de recursos (Fase 3) no se sostiene contra los archivos
  reales.
- Aparece un caso ambiguo que no está cubierto por la sección 5.
- Hay más de 10 links rotos preexistentes (sugiere que el parseo del README está mal,
  no que el repo esté roto).

**No improvises criterios nuevos para desbloquearte.** Un loop detenido con una
pregunta clara es un resultado mejor que un repo reorganizado según reglas inventadas.
