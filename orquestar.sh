#!/usr/bin/env bash
#
# orquestar.sh — ejecuta la migración de invo.py y la construcción del sitio.
#
# Uso:
#   ./orquestar.sh migracion     # etapa 1, se detiene para revisión humana
#   ./orquestar.sh sitio         # etapa 2, tras aprobar el diff de la etapa 1
#   ./orquestar.sh deploy        # publicación, requiere CONFIRMAR_DEPLOY=1
#
# Requiere: claude, gh (autenticado), python3, git.

set -euo pipefail

REPO="investigacion-operativa-utn/invo.py"
MAX_INTENTOS=4
TIMEOUT=45m
LOG="orquestacion-$(date +%Y%m%d-%H%M%S).log"

log()   { echo -e "\n\033[1;34m▸ $*\033[0m" | tee -a "$LOG"; }
error() { echo -e "\n\033[1;31m✗ $*\033[0m" | tee -a "$LOG"; exit 1; }
ok()    { echo -e "\n\033[1;32m✓ $*\033[0m" | tee -a "$LOG"; }

# ─────────────────────────────────────────────────────────────
# Verificaciones previas
# ─────────────────────────────────────────────────────────────

preflight() {
  command -v claude >/dev/null || error "claude no está instalado"
  command -v gh     >/dev/null || error "gh no está instalado"
  gh auth status    >/dev/null 2>&1 || error "gh no está autenticado (corré: gh auth login)"

  [[ -z "$(git status --porcelain)" ]] \
    || error "el árbol de trabajo tiene cambios sin commitear"

  [[ -f SPEC-migracion.md && -f SPEC-sitio.md ]] \
    || error "faltan SPEC-migracion.md o SPEC-sitio.md en la raíz"
}

# Corre claude en headless reintentando hasta que el validador pase.
# $1 = prompt inicial, $2 = comando validador, $3 = nombre de la etapa
ejecutar_hasta_validar() {
  local prompt="$1" validador="$2" etapa="$3"

  for intento in $(seq 1 "$MAX_INTENTOS"); do
    log "[$etapa] intento $intento de $MAX_INTENTOS"

    timeout "$TIMEOUT" claude -p "$prompt" \
      --dangerously-skip-permissions 2>&1 | tee -a "$LOG" || true

    if eval "$validador" >>"$LOG" 2>&1; then
      ok "[$etapa] validador en verde"
      return 0
    fi

    log "[$etapa] validador en rojo, reintentando con el error como contexto"
    prompt="El validador sigue fallando. Corré '$validador', leé los errores y
            arreglalos respetando el spec. No cambies el validador para que pase."
  done

  error "[$etapa] no convergió en $MAX_INTENTOS intentos — revisá $LOG"
}

# ─────────────────────────────────────────────────────────────
# Etapa 1: migración
# ─────────────────────────────────────────────────────────────

etapa_migracion() {
  preflight

  log "creando tag de retorno y rama de trabajo"
  git tag -f 2026-1C
  git push -f origin 2026-1C
  git switch -c reorg 2>/dev/null || git switch reorg

  ejecutar_hasta_validar \
    "Leé SPEC-migracion.md y ejecutalo completo, en orden, commiteando cada fase." \
    "python3 scripts/validar.py" \
    "migración"

  [[ -z "$(git status --porcelain)" ]] || error "quedaron cambios sin commitear"
  [[ -f MIGRACION.md ]] || error "no se generó MIGRACION.md"

  # Chequeo de integridad independiente del validador: ningún blob se perdió.
  log "verificando que no se haya perdido ningún archivo"
  comm -23 \
    <(git ls-tree -r 2026-1C --format='%(objectname)' | sort -u) \
    <(git ls-tree -r HEAD    --format='%(objectname)' | sort -u) \
    > /tmp/blobs-perdidos
  [[ ! -s /tmp/blobs-perdidos ]] \
    || error "$(wc -l < /tmp/blobs-perdidos) blobs desaparecieron — NO mergees"

  ok "migración completa"

  cat <<EOF

  ┌───────────────────────────────────────────────────────────┐
  │  COMPUERTA HUMANA                                         │
  └───────────────────────────────────────────────────────────┘

  Revisá antes de seguir:

    git diff --stat main..reorg
    cat MIGRACION.md
    cat material/SIN-ASIGNAR.md
    git log --follow -- material/markov/teoria/*/slides.pdf

  El último confirma que el historial sobrevivió a los git mv.

  Si te cierra:
    git switch main && git merge --no-ff reorg && ./orquestar.sh sitio

EOF
}

# ─────────────────────────────────────────────────────────────
# Etapa 2: sitio
# ─────────────────────────────────────────────────────────────

etapa_sitio() {
  preflight

  python3 scripts/validar.py >/dev/null 2>&1 \
    || error "validar.py no pasa — la etapa 1 no está consolidada"

  git switch -c sitio 2>/dev/null || git switch sitio

  ejecutar_hasta_validar \
    "Leé SPEC-sitio.md y ejecutalo completo, en orden, commiteando cada fase.
     No hagas push ni despliegues nada." \
    "mkdocs build --strict && python3 scripts/validar_sitio.py" \
    "sitio"

  git status --porcelain | grep -qE '^\?\?\s+(docs|site)/' \
    && error "docs/ o site/ no están en .gitignore"

  ok "sitio construido y validado en local"

  cat <<EOF

  Previsualizá con:   mkdocs serve

  Si te cierra:
    git switch main && git merge --no-ff sitio && CONFIRMAR_DEPLOY=1 ./orquestar.sh deploy

EOF
}

# ─────────────────────────────────────────────────────────────
# Etapa 3: publicación
# ─────────────────────────────────────────────────────────────

etapa_deploy() {
  [[ "${CONFIRMAR_DEPLOY:-}" == "1" ]] \
    || error "esta etapa publica al mundo. Corré: CONFIRMAR_DEPLOY=1 $0 deploy"

  preflight
  [[ "$(git branch --show-current)" == "main" ]] || error "tenés que estar en main"

  if ! git ls-remote --exit-code --heads origin gh-pages >/dev/null 2>&1; then
    log "creando rama gh-pages vacía"
    git switch --orphan gh-pages
    git commit --allow-empty -m "init gh-pages"
    git push -u origin gh-pages
    git switch main
  fi

  log "habilitando GitHub Pages"
  gh api -X POST "repos/$REPO/pages" \
    -f 'source[branch]=gh-pages' -f 'source[path]=/' 2>/dev/null \
    || log "Pages ya estaba habilitado"

  log "pusheando main y disparando el workflow"
  git push origin main
  sleep 5
  gh run watch --exit-status || error "el workflow falló — revisá: gh run view --log-failed"

  log "fijando 'latest' como versión por defecto"
  git fetch origin gh-pages
  mike set-default --push latest

  ok "sitio publicado en https://investigacion-operativa-utn.github.io/invo.py/"
  echo "Puede tardar un par de minutos en propagarse."
}

# ─────────────────────────────────────────────────────────────

case "${1:-}" in
  migracion) etapa_migracion ;;
  sitio)     etapa_sitio ;;
  deploy)    etapa_deploy ;;
  *)         echo "uso: $0 {migracion|sitio|deploy}"; exit 1 ;;
esac
