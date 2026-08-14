#!/bin/bash
# Lo que comparten probar-rama.sh y cerrar-rama.sh. Se carga con `source`; no se
# ejecuta suelto.
#
# Existe porque los dos necesitan las mismas setenta líneas de preámbulo
# —averiguar la raíz de verdad, validar la rama, encontrar su worktree, negarse a
# borrar el directorio desde el que corren, frenar con el árbol sucio— y dos
# copias de eso se separan en cuanto alguien arregla una sola.

# Para poder falsear el mundo de fuera en la matriz de pruebas. `curl` y `nc`
# están aquí por lo mismo que los demás: sin poder falsearlos, el camino en que
# la pila SÍ responde —el aviso, la URL, el mensaje final— no lo probaba nadie,
# porque el único caso que se podía escribir era el de que no respondiera.
GH="${GH:-gh}"
DOCKER="${DOCKER:-docker}"
AVISADOR="${AVISADOR:-terminal-notifier}"
CURL="${CURL:-curl}"
NC="${NC:-nc}"

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

# Deja `url_pr` puesta con la URL de la PR, o vacía si no hay ninguna. Se llama
# como una orden y no dentro de `$( )`: una asignación hecha en una sustitución
# de órdenes vive en un subshell y se pierde al volver, así que preguntar «dame
# la URL» tantas veces como líneas la mencionan costaba una llamada de red por
# línea. Tolera que no haya PR porque `probar-rama.sh --solo-pila` levanta una
# pila local de una rama que a lo mejor no se ha empujado nunca.
recordar_url_pr() {
  url_pr=$($GH pr view "$rama" --json url --jq .url 2>/dev/null || true)
}

# ── El CI ───────────────────────────────────────────────────────────────────
# ¿Hay algún workflow que se dispare con las PRs? YAML deja escribir el `on:` de
# cuatro maneras y hasta el 13-08-2026 esto solo reconocía una, la de mapa. Con
# `on: [push, pull_request]` —la de `prespuestos-obras`, que además es su único
# workflow— decía «este repositorio no tiene CI» teniéndolo, y eso convierte un
# repositorio con pruebas en uno que se fusiona a ojo.
#
# Se mira el árbol de la RAMA, no el de la raíz: una rama que AÑADE el CI es
# justo el caso en que la raíz todavía no lo tiene.
hay_ci_de_pr() {                        # hay_ci_de_pr <directorio>
  grep -qE \
    -e '^[[:space:]]*pull_request(_target)?[[:space:]]*:' \
    -e '^[[:space:]]*on[[:space:]]*:[[:space:]]*\[[^]]*pull_request' \
    -e '^[[:space:]]*on[[:space:]]*:[[:space:]]*pull_request(_target)?[[:space:]]*$' \
    -e '^[[:space:]]*-[[:space:]]*pull_request(_target)?[[:space:]]*$' \
    "$1"/.github/workflows/*.y*ml 2>/dev/null
}

# Sale 0 si está verde, 1 si está rojo, 2 si no hay checks. Imprime el porqué.
esperar_ci() {                          # esperar_ci [--vigilar]
  local vigilar=0 salida hay_workflows espera malos corriendo

  [ "${1:-}" = --vigilar ] && vigilar=1

  # ⚠️ **`--watch` y `--json` no se piden a la vez.** El propio `gh` lo rechaza
  # —«cannot use `--watch` with `--json` flag»— y saca la usage por stderr, que
  # aquí va a /dev/null. Juntos dejaban la salida SIEMPRE vacía, y una salida
  # vacía es justo lo que esta función lee como «no hay checks»: desde que el
  # 13-08-2026 se partió esto en `probar` y `cerrar` —que es cuando nació
  # `--vigilar`—, `cerrar-rama.sh` se negaba a fusionar CUALQUIER rama de
  # CUALQUIER repositorio, diciendo que la PR no había disparado ningún check
  # mientras `gh pr checks` enseñaba el verde al lado.
  #
  # Así que van por separado y en tres tiempos: se espera a que los checks
  # existan, se vigila hasta que terminen, y solo entonces se lee el veredicto.

  # 1. Que existan. Un workflow tarda unos segundos en registrarse y
  #    `gh pr checks` sale en cuanto ve que no hay ninguno, sin esperarlo.
  #    «No hay checks» tiene dos causas MUY distintas, y hasta el 13-08-2026 las
  #    dos daban el mismo mensaje —«este repositorio no tiene CI»—, que en welzy
  #    es falso: tiene `ci.yml`, y lo que pasa es que su `paths-ignore` deja
  #    fuera las PRs de solo markdown a propósito.
  if hay_ci_de_pr "${ruta_wt:-$raiz}"; then
    hay_workflows=1
  else
    hay_workflows=0
  fi

  hay_checks() { printf '%s' "$salida" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; }

  salida=$($GH pr checks "$rama" --json bucket,name,link 2>/dev/null) || true
  if [ "$hay_workflows" = 1 ]; then
    espera=0
    while ! hay_checks; do
      [ "$espera" -ge "${ESPERA_CHECKS:-60}" ] && break
      sleep 5
      espera=$((espera + 5))
      salida=$($GH pr checks "$rama" --json bucket,name,link 2>/dev/null) || true
    done
  fi

  if ! hay_checks; then
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

  # 2. Que terminen. Sin `--json`, que es lo único que `--watch` admite; su
  #    código de salida no decide nada, porque el veredicto lo da el paso 3.
  if [ "$vigilar" = 1 ]; then
    $GH pr checks "$rama" --watch --fail-fast >&2 || true
    salida=$($GH pr checks "$rama" --json bucket,name,link 2>/dev/null) || true
  fi

  # 3. El veredicto, leído del JSON y solo de ahí.
  malos=$(printf '%s' "$salida" |
    jq -r '.[] | select(.bucket == "fail" or .bucket == "cancel") | "    \(.name)  \(.link)"')
  if [ -n "$malos" ]; then
    aviso "" "El CI no está verde:" ""
    printf '%s\n' "$malos" >&2
    return 1
  fi

  # Pendiente no es verde. Se llega aquí si nadie vigiló, o si el `--watch` se
  # cayó a mitad: dar por bueno un check que aún corre es exactamente el
  # aprobado sin examen que este guión existe para no dar.
  corriendo=$(printf '%s' "$salida" |
    jq -r '.[] | select(.bucket == "pending") | "    \(.name)  \(.link)"')
  if [ -n "$corriendo" ]; then
    aviso "" "El CI todavía está corriendo:" ""
    printf '%s\n' "$corriendo" >&2
    return 1
  fi
  return 0
}

# ── ¿Ese verde probó el main de AHORA? ──────────────────────────────────────
# `ci.yml` no prueba la rama: prueba el resultado de FUSIONARLA con main en ese
# momento. Si main se mueve después, la PR sigue marcada en verde y ese verde ya
# no dice nada de lo que se va a fusionar. Medido el 13-08-2026: fusionada la PR
# #8, la #9 seguía reportando `CLEAN`.
#
# `ci.yml` deja escrita la suposición que lo hacía tolerable —«con un solo
# mantenedor fusionando de una en una no ocurre»— y esa suposición se cae en
# cuanto hay varios agentes con una rama cada uno, que es justo para lo que se
# montó todo esto.
#
# Sale 0 si el verde sigue valiendo, y 10 si ha tenido que meter main en la rama:
# entonces hay un CI nuevo y hay que volver a esperarlo.
epoch_iso() {                           # epoch_iso <2026-08-13T14:47:12Z>
  local t=${1%%.*}
  date -j -u -f '%Y-%m-%dT%H:%M:%S' "${t%Z}" +%s 2>/dev/null ||
    date -u -d "$1" +%s 2>/dev/null || true
}

asegurar_ci_fresco() {
  local ultimo main_epoch check_epoch
  ultimo=$($GH pr checks "$rama" --json completedAt --jq '[.[].completedAt] | max' 2>/dev/null || true)
  [ -n "$ultimo" ] && [ "$ultimo" != null ] || return 0

  git -C "$raiz" fetch origin --quiet
  main_epoch=$(git -C "$raiz" log -1 --format=%ct "origin/$principal" 2>/dev/null || true)
  check_epoch=$(epoch_iso "$ultimo")
  # Sin poder comparar no se inventa una respuesta: se deja pasar el verde que hay.
  [ -n "$main_epoch" ] && [ -n "$check_epoch" ] || return 0
  [ "$main_epoch" -gt "$check_epoch" ] || return 0

  aviso "" \
    "origin/$principal se ha movido desde que el CI de esta PR pasó:" \
    "ese verde probó otra fusión, no la que se haría ahora."
  paso "meto $principal en la rama y espero al CI nuevo"
  # Con merge y no con `--rebase` a propósito: el rebase reescribe los SHA de la
  # rama, y entonces el freno del borrado —«¿está esta rama dentro de
  # origin/main?»— diría que no y se negaría a limpiar.
  $GH pr update-branch "$numero" >&2 ||
    morir "" "No he podido meter $principal en la rama (¿conflicto?). No fusiono nada."
  return 10
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
  while $NC -z 127.0.0.1 "$p" >/dev/null 2>&1; do
    p=$(( p + 1 )); n=$(( n + 1 ))
    [ "$n" -gt 100 ] && morir "No encuentro un puerto libre entre 8100 y 8600."
  done
  printf '%s' "$p"
}
