#!/bin/bash
# Lo que comparten probar-rama.sh y cerrar-rama.sh. Se carga con `source`; no se
# ejecuta suelto.
#
# Existe porque los dos necesitan las mismas setenta líneas de preámbulo
# —averiguar la raíz de verdad, validar la rama, encontrar su worktree, negarse a
# borrar el directorio desde el que corren, frenar con el árbol sucio— y dos
# copias de eso se separan en cuanto alguien arregla una sola.

# Para poder falsear GitHub, Docker y el avisador en la matriz de pruebas.
GH="${GH:-gh}"
DOCKER="${DOCKER:-docker}"
AVISADOR="${AVISADOR:-terminal-notifier}"

morir() { printf '%s\n' "$@" >&2; exit 1; }
aviso() { printf '%s\n' "$@" >&2; }
paso()  { printf '  %s\n' "$*" >&2; }

# ── Dónde estamos ───────────────────────────────────────────────────────────
# Deja puestas: raiz, rama, principal, ruta_wt, hubo_remoto.
resolver_repo() {                       # resolver_repo <rama-o-vacío> <verbo>
  rama="${1:-}"
  local verbo="${2:-cerrar}"

  git rev-parse --git-dir >/dev/null 2>&1 || morir "Aquí no hay ningún repositorio git."
  # `worktree list` da siempre el principal el primero. `substr` y no `$2` porque
  # una ruta puede llevar espacios.
  raiz=$(git worktree list --porcelain | awk '$1 == "worktree" { print substr($0, 10); exit }')
  [ -n "$raiz" ] || morir "No consigo averiguar la raíz del repositorio."

  [ -n "$rama" ] || rama=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  [ -n "$rama" ] && [ "$rama" != HEAD ] || morir "No sé qué rama $verbo. Pásala como argumento."

  case "$rama" in
    main | master) morir "'$rama' es la rama principal, y no se $verbo." ;;
  esac

  git -C "$raiz" show-ref --quiet --verify "refs/heads/$rama" ||
    morir "Aquí no hay ninguna rama '$rama'."

  principal=$(git -C "$raiz" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
  principal=${principal#origin/}
  [ -n "$principal" ] || principal=main

  ruta_wt=$(git -C "$raiz" worktree list --porcelain | awk -v r="refs/heads/$rama" '
    $1 == "worktree" { w = substr($0, 10) }
    $1 == "branch" && $2 == r { print w; exit }')

  hubo_remoto=0
  git -C "$raiz" remote get-url origin >/dev/null 2>&1 && hubo_remoto=1
}

# Borrar el directorio desde el que se está ejecutando deja el shell en un sitio
# que ya no existe y el worktree a medio quitar. Solo lo exige quien va a borrar.
exigir_estar_fuera() {
  [ -n "$ruta_wt" ] || return 0
  local actual wt_real
  actual=$(pwd -P)
  wt_real=$(cd "$ruta_wt" 2>/dev/null && pwd -P || printf '%s' "$ruta_wt")
  case "$actual" in
    "$wt_real" | "$wt_real"/*)
      morir "Estás dentro del worktree que hay que borrar ($wt_real)." \
        "" \
        "Sal primero:  cd $raiz" \
        "(en Claude Code: ExitWorktree con action \"keep\")" ;;
  esac
}

# El freno. Lo único de todo esto que destruye trabajo es el borrado, y una PR
# abierta con el árbol sucio ya sale incompleta.
exigir_arbol_limpio() {                 # exigir_arbol_limpio <forzar>
  [ -n "$ruta_wt" ] || return 0
  local sucio
  sucio=$(git -C "$ruta_wt" status --porcelain)
  [ -n "$sucio" ] || return 0
  if [ "${1:-0}" != 1 ]; then
    aviso "El worktree tiene cambios sin guardar:" ""
    printf '%s\n' "$sucio" | sed 's/^/    /' >&2
    morir "" "No sigo. Commitéalos, o repítelo con --forzar si sobran."
  fi
  aviso "OJO: --forzar; se tiran estos cambios sin guardar:"
  printf '%s\n' "$sucio" | sed 's/^/    /' >&2
}

# ── La PR ───────────────────────────────────────────────────────────────────
# Empuja y deja `numero` y `estado` puestos. Abre la PR si no la había.
empujar_y_abrir_pr() {
  [ "$hubo_remoto" = 1 ] || morir "Este repositorio no tiene remoto: no hay PR."

  git -C "$raiz" fetch origin --quiet --prune
  local pendientes
  pendientes=$(git -C "$raiz" rev-list --count "origin/$principal..$rama")
  [ "$pendientes" -gt 0 ] ||
    morir "La rama '$rama' no tiene ningún commit que origin/$principal no tenga."

  paso "empujo $rama ($pendientes commit(s))"
  git -C "$raiz" push --quiet -u origin "$rama"

  if $GH pr view "$rama" --json number >/dev/null 2>&1; then
    estado=$($GH pr view "$rama" --json state --jq .state)
  else
    paso "no había PR: la abro"
    $GH pr create --head "$rama" --base "$principal" --fill >&2
    estado=OPEN
  fi
  numero=$($GH pr view "$rama" --json number --jq .number)
}

# ── El CI ───────────────────────────────────────────────────────────────────
# Sale 0 si está verde, 1 si está rojo, 2 si no hay checks. Imprime el porqué.
esperar_ci() {                          # esperar_ci [--vigilar]
  local vigilar=() codigo=0 salida hay_workflows espera malos
  [ "${1:-}" = --vigilar ] && vigilar=(--watch --fail-fast)

  codigo=0
  salida=$($GH pr checks "$rama" ${vigilar[@]+"${vigilar[@]}"} --json bucket,name,link 2>/dev/null) || codigo=$?

  # «No hay checks» tiene dos causas MUY distintas, y hasta el 13-08-2026 las dos
  # daban el mismo mensaje —«este repositorio no tiene CI»—, que en welzy es
  # falso: tiene `ci.yml`, y lo que pasa es que su `paths-ignore` deja fuera las
  # PRs de solo markdown a propósito.
  if grep -qE '^[[:space:]]*pull_request(_target)?[[:space:]]*:' "$raiz"/.github/workflows/*.y*ml 2>/dev/null; then
    hay_workflows=1
  else
    hay_workflows=0
  fi

  # Y si los hay, pueden tardar unos segundos en registrarse: `gh pr checks` sale
  # en cuanto ve que no hay ninguno, sin esperar a que aparezcan.
  if [ "$hay_workflows" = 1 ]; then
    espera=0
    while ! printf '%s' "$salida" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; do
      [ "$espera" -ge "${ESPERA_CHECKS:-60}" ] && break
      sleep 5
      espera=$((espera + 5))
      codigo=0
      salida=$($GH pr checks "$rama" ${vigilar[@]+"${vigilar[@]}"} --json bucket,name,link 2>/dev/null) || codigo=$?
    done
  fi

  if ! printf '%s' "$salida" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then
    if [ "$hay_workflows" = 1 ]; then
      aviso "" \
        "La PR #$numero está abierta. Este repositorio SÍ tiene CI, pero esta PR" \
        "no ha disparado ningún check: lo normal es un \`paths-ignore\` que la deja" \
        "fuera a propósito —welzy hace eso con las PRs de solo documentación—, y" \
        "lo que no es normal es que \`ci.yml\` esté roto y no cree ejecuciones."
    else
      aviso "" "La PR #$numero está abierta, pero este repositorio no tiene CI."
    fi
    aviso "«Sin checks» no es un aprobado."
    return 2
  fi

  malos=$(printf '%s' "$salida" |
    jq -r '.[] | select(.bucket == "fail" or .bucket == "cancel") | "    \(.name)  \(.link)"')
  if [ -n "$malos" ]; then
    aviso "" "El CI no está verde:" ""
    printf '%s\n' "$malos" >&2
    return 1
  fi
  [ "$codigo" -eq 0 ] || { aviso "" "El CI terminó con código $codigo."; return 1; }
  return 0
}

# ── La pila local de una rama ───────────────────────────────────────────────
# Un proyecto de Compose por rama, para que dos ramas levantadas a la vez no se
# pisen y para que la de la rama nunca toque los volúmenes de la de siempre.
proyecto_de_rama() {                    # proyecto_de_rama → imprime el nombre
  local repo suave
  repo=$(basename "$raiz")
  suave=$(printf '%s' "$rama" | tr '[:upper:]/' '[:lower:]-' | tr -cd '[:alnum:]-')
  printf '%s-%s' "$repo" "$suave"
}

# Puerto derivado del nombre de la rama: estable entre relanzamientos —la URL de
# una rama no cambia mientras viva— y verificado libre antes de usarlo.
puerto_de_rama() {                      # puerto_de_rama → imprime el puerto
  local semilla p n=0
  semilla=$(printf '%s' "$rama" | cksum | awk '{print $1}')
  p=$(( 8100 + semilla % 400 ))
  while nc -z 127.0.0.1 "$p" >/dev/null 2>&1; do
    p=$(( p + 1 )); n=$(( n + 1 ))
    [ "$n" -gt 100 ] && morir "No encuentro un puerto libre entre 8100 y 8600."
  done
  printf '%s' "$p"
}
