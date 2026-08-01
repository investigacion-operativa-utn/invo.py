# SPEC: sitio de GitHub Pages para invo.py

Segunda etapa. **Requisito previo:** `SPEC-migracion.md` ejecutado y
`python scripts/validar.py` saliendo 0. Si no se cumple, detenerse inmediatamente.

Este documento es la especificación completa del sitio. Está pensado para ejecutarse
de forma autónoma con `/goal`. Todo lo que necesitás para tomar decisiones está acá;
**no inventes criterios que no estén escritos**.

---

## 0. Contexto

`contenido.yml` es la única fuente de verdad del índice del curso: unidades, clases,
títulos y slugs de carpeta. `scripts/generar.py` ya lo consume para regenerar la tabla
del `README.md`.

Ahora ese mismo YAML debe alimentar un sitio estático navegable y buscable, publicado
en GitHub Pages.

## 1. Objetivo

Un sitio generado desde `contenido.yml`, con los notebooks renderizados como páginas
HTML legibles, búsqueda full-text, y versionado por cuatrimestre con selector.

**Principio no negociable:** el sitio es un *artefacto derivado*. No es un segundo
lugar donde vive el contenido. Se regenera en CI, nunca se edita a mano, y si se rompe
se descarta y se vuelve a generar. Ningún archivo de `material/` se duplica ni se
mueve por necesidades del sitio.

## 2. Condición de finalización

```
mkdocs build --strict sale 0, python scripts/validar_sitio.py sale 0,
git status está limpio, y docs/ está en .gitignore
```

Notar que la condición es **build local, no deploy**. El loop autónomo nunca escribe
en `gh-pages` ni hace push. El despliegue lo hace GitHub Actions cuando yo pusheo.
Esto es deliberado: el peor resultado posible de un loop descontrolado debe ser un
build roto en local, no un sitio público destruido.

## 3. Stack

| Pieza | Rol |
|---|---|
| MkDocs + Material | Motor del sitio, búsqueda, tema |
| `mkdocs-jupyter` | Renderiza `.ipynb` como páginas HTML |
| `mike` | Versionado por cuatrimestre con selector desplegable |
| `pymdown-extensions` (arithmatex) | LaTeX — hay bastante en simplex, colas y Markov |
| GitHub Actions | Build y deploy a la rama `gh-pages` |

Dependencias en `requirements-docs.txt` con versiones pineadas.

## 4. Decisiones pre-tomadas

| Tema | Decisión |
|---|---|
| `site_url` | `https://investigacion-operativa-utn.github.io/invo.py/` — es un *project page*, no un org page. El punto en el nombre del repo es válido pero la ruta `/invo.py/` es obligatoria o los links internos salen mal. |
| `docs_dir` | `docs/`, **generado por `generar.py` en tiempo de build**. Va a `.gitignore`. Nunca se commitea. |
| PDFs | Se **copian** a `docs/` durante el build, así se sirven desde el sitio con URL estable. Como `docs/` no se commitea, no duplican peso en el repo. |
| Notebooks | Se copian a `docs/` y `mkdocs-jupyter` los renderiza como páginas. Además, cada página de notebook lleva arriba un badge de Colab apuntando a `github.com/.../blob/main/<path original>`. Leer y ejecutar son dos caminos distintos y ambos deben existir. |
| Ejecución de notebooks | `execute: false`. **No ejecutar notebooks en CI**: algunos dependen de datos locales o de red, y un notebook que falla no puede tumbar el build del sitio. Se renderizan los outputs ya guardados. |
| Idioma | `language: es` en el tema y en el plugin de búsqueda. |
| Navegación | Dos vistas generadas desde los mismos datos: **por clase** (cronológica, la vista por defecto) y **por unidad temática**. |
| Páginas manuales | Las de `paginas/` (home, cómo cursar, bibliografía) se copian a `docs/` sin transformar. Son las únicas páginas escritas a mano. |
| Versionado | `mike`. Alias `latest` apuntando al cuatrimestre en curso, y `dev` para lo que está en `main`. Cada tag de cuatrimestre queda congelado en su propia subcarpeta. |
| Contenido de terceros | `material/externos/` se publica igual, pero su página lleva la nota de autoría y la aclaración de licencia. |
| Recursos en `SIN-ASIGNAR.md` | **No se publican.** No están asignados a ninguna clase; incluirlos en el nav sería inventar estructura. |

## 5. Fases

### Fase 1 — Extender el generador

`scripts/generar.py` pasa a producir también el árbol `docs/`:

- Una página índice por unidad temática y una por clase.
- Copia de PDFs, notebooks y xlsx desde `material/` a su ubicación en `docs/`.
- Copia de las páginas de `paginas/`.
- El bloque `nav` de `mkdocs.yml`.

Mantener la idempotencia: correr `generar.py` dos veces seguidas no produce diff en
archivos versionados.

Agregar `docs/` y `site/` a `.gitignore`.

Commit: `feat: generar árbol docs/ desde contenido.yml`.

### Fase 2 — Configuración de MkDocs

`mkdocs.yml` con el stack de la sección 3 y las decisiones de la sección 4.

Requisitos concretos:

- `strict: true` — un link interno roto debe fallar el build, no degradarse en silencio.
- Extensión `pymdownx.arithmatex` con `generic: true`, más el `extra_javascript` de MathJax.
- `mkdocs-jupyter` con `execute: false` y `include_source: true`.
- Búsqueda con `lang: es`.
- Selector de versión: `extra.version.provider: mike`.
- Modo claro/oscuro conmutable.
- Link al repo en el header.

Verificar con `mkdocs build --strict`. **No** correr `mkdocs serve` (bloquea el loop).

Commit: `feat: configuración de MkDocs Material`.

### Fase 3 — Validador

`scripts/validar_sitio.py`, según la sección 6.

Commit: `test: validador del sitio generado`.

### Fase 4 — CI

`.github/workflows/docs.yml`:

- Dispara en push a `main` y en push de tags.
- `permissions: contents: write` (mike pushea a `gh-pages`).
- `actions/checkout@v4` con `fetch-depth: 0` — mike necesita el historial completo.
- `concurrency` con un grupo único y `cancel-in-progress: false`, para que dos deploys
  simultáneos no se pisen en `gh-pages`.
- Instala `requirements-docs.txt`, corre `generar.py`, corre `validar_sitio.py`,
  y recién ahí despliega.
- En push a `main`: `mike deploy --push --update-aliases dev`.
- En push de tag: `mike deploy --push --update-aliases <tag> latest`.

Commit: `ci: build y deploy del sitio con mike`.

### Fase 5 — Documentación

Extender `CONTRIBUTING.md` con tres procedimientos, en imperativo y con los comandos
exactos:

1. Agregar una clase o recurso nuevo (editar solo `contenido.yml`).
2. Previsualizar el sitio en local.
3. Congelar un cuatrimestre al cierre.

Agregar al final de `MIGRACION.md` una sección con los **pasos manuales pendientes**
que no puedo automatizar (ver sección 8).

Commit: `docs: procedimientos de mantenimiento del sitio`.

## 6. Especificación de `scripts/validar_sitio.py`

Corre después de `mkdocs build --strict`. Sale 0 solo si todo se cumple; cada fallo
imprime la regla violada y el path.

1. **Cobertura**: toda carpeta de recurso referenciada en `contenido.yml` tiene al
   menos una página o archivo correspondiente en `site/`.
2. **Clases completas**: las 26 clases de `contenido.yml` aparecen en el nav generado.
3. **Sin fugas de contenido**: ningún recurso listado en `material/SIN-ASIGNAR.md`
   aparece en `site/`.
4. **PDFs servidos**: todo link a `.pdf` en el HTML generado resuelve a un archivo
   existente dentro de `site/`.
5. **Colab bien formado**: toda URL de Colab en el HTML tiene la forma
   `colab.research.google.com/github/investigacion-operativa-utn/invo.py/blob/main/<path>`
   y `<path>` existe en `material/`. **Los links de Colab apuntan al repo, nunca al
   sitio.**
6. **Notebooks no ejecutados**: los `.ipynb` bajo `material/` no cambiaron respecto de
   `HEAD`. El build no debe modificar las fuentes.
7. **Sin URLs locales**: no aparece `localhost`, `127.0.0.1` ni `file://` en el HTML.
8. **Base path correcto**: los links absolutos internos empiezan con `/invo.py/`.
9. **Matemática presente**: al menos una página de las unidades con LaTeX contiene
   marcado de MathJax renderizado. Detecta que arithmatex quedó mal configurado.
10. **Idempotencia**: correr `generar.py` no produce diff en archivos versionados.

## 7. Cuándo detenerse y pedir intervención

Detener el loop, dejar el estado escrito y devolver el control si:

- `validar.py` (el de la migración) deja de salir 0 en cualquier momento. **El sitio
  nunca justifica romper la estructura del material.**
- El check 6 falla: algo está ejecutando o reescribiendo los notebooks fuente.
- Un notebook rompe el render por outputs corruptos, widgets no serializables o tamaño
  excesivo. Reportar cuál. **No** editar el notebook para que compile.
- `mkdocs build --strict` falla por links rotos que vienen de `contenido.yml` y no de
  la configuración.
- Aparece la tentación de agregar contenido didáctico, resúmenes o descripciones de
  los PDFs para llenar una página vacía. **Está prohibido redactar material.** Una
  página índice escueta es correcta.

**No improvises criterios nuevos para desbloquearte.**

## 8. Pasos manuales (no automatizables)

Registrar en `MIGRACION.md` como pendientes para mí:

1. En Settings → Pages del repo, configurar el source como la rama `gh-pages`.
   Esto no se puede hacer desde el repo y el sitio no aparece hasta que se haga.
2. Después del primer deploy exitoso: `mike set-default --push latest`.
3. Verificar que el primer build de Actions haya creado la rama `gh-pages`. Si el
   workflow falla porque no existe, crearla vacía con
   `git switch --orphan gh-pages && git commit --allow-empty -m init && git push`.
