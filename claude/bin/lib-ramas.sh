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

# ── Antes de empujar: lo que se puede comprobar sin GitHub ──────────────────
# El CI es el juez, pero tarda —doce minutos en welzy— y cobra el viaje entero
# por un `lint` que aquí se ve en veinte segundos. `verificar.sh` en la raíz del
# repositorio es ese subconjunto rápido: formato, lint, tipos y unitarios.
#
# Se ejecuta el del WORKTREE, no el de la raíz: es el que la rama ha podido
# cambiar, y una rama que rompe su propia verificación tiene que verlo. Si no
# hay ninguno se avisa y se sigue —como con el `docker-compose.yml`—, porque no
# todos los repositorios tienen uno todavía.
exigir_verificacion() {                 # exigir_verificacion <sin_verificar>
  [ -n "$ruta_wt" ] || return 0

  if [ "${1:-0}" = 1 ]; then
    aviso "OJO: --sin-verificar; esto no lo ha comprobado nadie en local."
    return 0
  fi

  local guion="$ruta_wt/verificar.sh"
  if [ ! -e "$guion" ]; then
    paso "aquí no hay verificar.sh: el CI es la única red"
    return 0
  fi
  # Sin permiso de ejecución es peor que no tenerlo: parece que algo comprueba
  # la rama, y no la comprueba nadie.
  [ -x "$guion" ] || morir "$guion existe pero no es ejecutable." \
    "Arréglalo:  chmod +x $guion"

  paso "verificar.sh"
  ( cd "$ruta_wt" && "$guion" ) >&2 ||
    morir "" "verificar.sh ha fallado: no empujo nada." \
             "El CI diría lo mismo, pero doce minutos más tarde."
}

# ── Antes de empujar: la revisión ───────────────────────────────────────────
# La PR se abre con lo que el revisor ya ha dicho DENTRO. Revisar después es
# abrir una PR que se corrige a base de commits de «arreglo lo revisado», que es
# justo lo que `probar-rama.sh` evita en el otro extremo con la pila local.
#
# Quien revisa es `/code-review`, y eso no lo puede lanzar un guión de bash: lo
# lanza la skill `probar`, aplica lo que salga, commitea y deja la marca. Aquí
# solo se comprueba que la marca esté puesta y sea de ESTOS commits — que es lo
# que convierte «acuérdate de revisar» en algo que no se puede olvidar.
#
# La marca vive en el directorio git del worktree: ni se commitea, ni viaja a
# nadie, y `git worktree remove` se la lleva con todo lo demás.
ruta_marca_revision() {                 # ruta_marca_revision → imprime la ruta
  local gitdir
  gitdir=$(git -C "$ruta_wt" rev-parse --absolute-git-dir 2>/dev/null) || return 1
  printf '%s/revisado' "$gitdir"
}

exigir_revision() {                     # exigir_revision <sin_revisar>
  [ -n "$ruta_wt" ] || return 0

  if [ "${1:-0}" = 1 ]; then
    aviso "OJO: --sin-revisar; la PR se abre sin que nadie haya leído el diff."
    return 0
  fi

  local marca cabeza revisado sha_revisado nivel_revisado pide tiene
  # Si no se puede leer la marca, no se pasa: un freno que no sabe responder
  # tiene que decir que no. Fallar hacia el lado permisivo es no tener freno los
  # días raros, que son justo los días en los que hace falta.
  marca=$(ruta_marca_revision) ||
    morir "No encuentro el directorio git de $ruta_wt," \
          "así que no puedo saber si esto está revisado. No empujo."
  cabeza=$(git -C "$ruta_wt" rev-parse HEAD)
  revisado=$(cat "$marca" 2>/dev/null || true)
  # Formato de la marca: «<sha> <nivel>». Las marcas viejas solo llevan el SHA, y
  # esas cuentan como nivel desconocido: se vuelve a marcar diciendo con qué
  # nivel se revisó, que es una línea, y no se da por bueno lo que nadie escribió.
  sha_revisado=${revisado%% *}
  nivel_revisado=${revisado#* }
  [ "$nivel_revisado" != "$revisado" ] || nivel_revisado=""

  if [ "$sha_revisado" = "$cabeza" ]; then
    # El segundo freno *(17-08-2026)*: que el nivel de la revisión sea al menos
    # el que pide el diff. Sin esto la escalera de tramos sería una sugerencia
    # que se concede a sí mismo quien la pide —el mismo agujero que `--solo-md`
    # tapó con su comprobación—, y el tramo barato se elegiría siempre.
    clasificar_diff ||
      morir "No he podido clasificar el diff de '$rama'," \
            "así que no sé qué revisión pide. No empujo."
    pide=$(orden_de_nivel "$nivel")
    tiene=$(orden_de_nivel "$nivel_revisado") || tiene=-1
    if [ "$tiene" -lt "$pide" ]; then
      aviso "" \
        "Esta rama es de tramo '$tramo' y pide una revisión a '$nivel':" \
        "  $motivo"
      morir "" \
        "La marca dice ${nivel_revisado:-«sin nivel» (marca de antes de los tramos)}." \
        "" \
        "  Revisa:  /code-review $rama $nivel --fix" \
        "  Marca:   marcar-revisado.sh $rama --nivel $nivel" \
        "  Mira:    clasificar-diff.sh $rama"
    fi
    paso "revisada a '$nivel_revisado' en ${cabeza:0:7} (pide '$nivel': $tramo)"
    return 0
  fi
  revisado="$sha_revisado"

  # Una marca vieja no es media revisión: es una revisión de otro código. Se
  # dice cuál era, porque el caso normal es «revisé, y luego commiteé una cosa
  # más», y ahí ayuda saber que solo falta volver a pasar por lo nuevo.
  [ -z "$revisado" ] ||
    aviso "" "La revisión que hay es de ${revisado:0:7}, y la rama va por ${cabeza:0:7}."

  morir "" \
    "Estos commits no han pasado por el revisor, y la PR se abre con sus" \
    "arreglos dentro, no antes de que los diga." \
    "" \
    "  En Claude Code:   la skill \`probar\` (/probar) — revisa, arregla, commitea y marca." \
    "  Ya está revisado: marcar-revisado.sh $rama" \
    "  Saltárselo:       probar-rama.sh $rama --sin-revisar"
}

# ── El atajo de solo markdown ───────────────────────────────────────────────
# Un cambio que solo toca `.md` no ejecuta nada: no hay lint que romper, ni
# tipos, ni pruebas que pasen de verdes a rojas, y la revisión a `max` se gasta
# leyendo prosa. `--solo-md` se salta los dos frenos de antes del push y, al
# cerrar, el despliegue.
#
# Lo que NO se salta es esta comprobación, y ese es todo el diseño: la bandera
# no se cree lo que le digan. Mira el diff de la rama contra el principal y se
# niega si asoma un fichero que no acabe en `.md`. Un atajo que se concede a sí
# mismo quien lo pide es un atajo que se pide el día que no tocaba —y aquí quien
# lo pide es un agente que acaba de decidir, él solo, que lo suyo «es solo
# documentación».
#
# `--no-renames` a propósito: con detección de renombrados, `git diff
# --name-only` imprime solo el destino, así que un `guion.sh → guion.md` pasaría
# por markdown puro cuando lo que ha ocurrido es que se ha borrado un guión.
#
# El estricto es el bueno: `.txt`, un `.png` de docs o un `LICENSE` sin
# extensión caen del lado de la cadena entera. La regla se explica en una frase
# —«si un fichero no acaba en .md, no hay atajo»— y una regla con lista de
# excepciones deja de poder explicarse a la tercera excepción.
# `core.quotePath=false` porque de serie git escapa las rutas no ASCII y las
# entrecomilla —`claude/skills/diseño.md` sale como `"dise\303\261o.md"`—, y eso
# no acaba en `.md`: un fichero con un acento en el nombre tumbaba el atajo
# diciendo que no era markdown.
#
# Y la salida de git se recoge ANTES de filtrarla, con su código de salida
# mirado, porque el `|| true` que necesita el `grep` —que sale 1 cuando no
# encuentra nada, que aquí es el caso bueno— se tragaba también un `git diff`
# roto. Una base que no se puede resolver dejaba la lista vacía, y una lista
# vacía es exactamente lo que este freno lee como «todo es markdown»: fallar
# hacia el lado permisivo es no tener freno los días raros.
diff_no_md() {                          # diff_no_md → imprime lo que no es .md
  local base="$principal" tocados
  if [ "$hubo_remoto" = 1 ]; then
    base="origin/$principal"
    [ "${ya_traido:-0}" = 1 ] || {
      git -C "$raiz" fetch origin --quiet --prune
      ya_traido=1
    }
  fi
  tocados=$(git -C "$raiz" -c core.quotePath=false \
              diff --name-only --no-renames "$base...$rama") || return 1
  printf '%s' "$tocados" | grep -v '\.md$' || true
}

exigir_solo_md() {                      # exigir_solo_md <qué-se-salta>
  local sobran base_dicha="$principal"
  [ "$hubo_remoto" != 1 ] || base_dicha="origin/$principal"
  # La declaración y la asignación van por separado a propósito: en
  # `local sobran=$(…)` el código de salida que se ve es el del `local`, que
  # siempre es 0, así que el fallo de dentro se perdería justo aquí.
  sobran=$(diff_no_md) ||
    morir "No he podido comparar '$rama' con $base_dicha," \
          "así que no puedo saber si esto es solo markdown. No sigo." \
          "Un freno que no sabe responder tiene que decir que no."
  if [ -n "$sobran" ]; then
    aviso "--solo-md, pero esta rama toca ficheros que no son markdown:" ""
    printf '%s\n' "$sobran" | sed 's/^/    /' >&2
    morir "" \
      "Eso no es documentación: lleva la cadena entera —verificar.sh, revisión" \
      "a max y, al cerrar, el despliegue—. Quítale el --solo-md."
  fi
  paso "solo markdown: ${1:-me salto los frenos}"
}

# ── El tramo de riesgo del diff ─────────────────────────────────────────────
# La generalización de `--solo-md` *(17-08-2026)*. Aquel atajo descubrió lo que
# valía: el freno lo elige un guión leyendo el diff, no el agente que acaba de
# decidir que lo suyo es sencillo. Lo que faltaba era el resto de la escalera —
# porque revisar a `max` un cambio de veinte líneas cuesta lo mismo que revisar
# a `max` uno de dos mil, y ese coste se pagaba en cada rama.
#
# Cuatro tramos y el nivel de `/code-review` que le toca a cada uno:
#
#   solo-md    ni un fichero fuera de .md         → ninguna revisión
#   trivial    ≤30 líneas, sin ficheros nuevos    → low
#   normal     lo demás                           → high
#   sensible   ruta delicada, o >600 líneas       → max
#
# Los dos umbrales salen del entorno para que la matriz pueda probarlos sin
# escribir seiscientas líneas de mentira.
NIVELES_ORDEN="ninguno low medium high max"

orden_de_nivel() {                      # orden_de_nivel <nivel> → 0..4
  local i=0 n
  for n in $NIVELES_ORDEN; do
    [ "$n" = "${1:-}" ] && { printf '%s' "$i"; return 0; }
    i=$((i + 1))
  done
  return 1
}

# Qué es «delicado» lo dice cada repositorio en `.claude/rutas-sensibles`, una
# glob por línea. Se lee la copia de la RAÍZ, no la del worktree, y eso es a
# propósito: leerla de la rama dejaría que una rama se rebajara el listón
# borrando de la lista justo lo que va a tocar. Por lo mismo, el propio fichero
# está en la lista de serie —cambiarlo es un cambio delicado— y el que decide es
# `main`, o sea una fusión que ya pasó por aquí.
RUTAS_SENSIBLES_DE_SERIE='*hooks/*
*bin/*.sh
*migracion*
*migration*
*auth*
.github/workflows/*
*settings.json
*rutas-sensibles
verificar.sh'

rutas_sensibles() {
  local fichero="$raiz/.claude/rutas-sensibles"
  if [ -f "$fichero" ]; then
    # Se admiten comentarios y líneas en blanco; sin ellos, un fichero que
    # alguien documenta deja de poder documentarse.
    grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$fichero" || true
  else
    printf '%s\n' "$RUTAS_SENSIBLES_DE_SERIE"
  fi
}

# Deja puestas: tramo, nivel, motivo, lineas_diff.
#
# Sale 1 si no ha podido comparar la rama con su base, y entonces NO deja tramo
# puesto: quien lo llame tiene que morir, por lo mismo que `exigir_solo_md` —un
# freno que no sabe responder tiene que decir que no, porque el lado permisivo
# es no tener freno justo los días raros.
clasificar_diff() {
  local base="$principal" tocados nuevos patron f sensible=0 fichero_malo="" patron_malo=""

  if [ "$hubo_remoto" = 1 ]; then
    base="origin/$principal"
    [ "${ya_traido:-0}" = 1 ] || {
      git -C "$raiz" fetch origin --quiet --prune
      ya_traido=1
    }
  fi

  tocados=$(git -C "$raiz" -c core.quotePath=false \
              diff --name-only --no-renames "$base...$rama") || return 1
  # Los binarios salen con `-` en las dos columnas y no se cuentan: sumarlos
  # como cero es más honesto que inventarles un tamaño en líneas.
  lineas_diff=$(git -C "$raiz" diff --numstat --no-renames "$base...$rama" |
                  awk '$1 != "-" { n += $1 + $2 } END { print n + 0 }') || return 1
  nuevos=$(git -C "$raiz" -c core.quotePath=false \
             diff --name-only --no-renames --diff-filter=A "$base...$rama" |
             grep -c . || true)

  if [ -z "$tocados" ]; then
    tramo=vacio; nivel=ninguno; motivo="el diff no toca ningún fichero"
    return 0
  fi

  # El mismo criterio que `--solo-md`, y llamando a la misma función: dos formas
  # de contestar «¿esto es solo markdown?» se separan en cuanto alguien arregla
  # una sola.
  local sobran
  sobran=$(diff_no_md) || return 1
  if [ -z "$sobran" ]; then
    tramo=solo-md; nivel=ninguno; motivo="todo lo que toca acaba en .md"
    return 0
  fi

  # Los paréntesis de apertura en los patrones del `case` no son adorno: el bash
  # 3.2 de Apple —el que ejecuta los hooks— rechaza un `case` sin ellos cuando
  # vive dentro de `$( )`, y esta función se llama así.
  while IFS= read -r patron; do
    [ -n "$patron" ] || continue
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      case "$f" in
        ($patron) sensible=1; fichero_malo="$f"; patron_malo="$patron"; break 2 ;;
      esac
    done <<FICHEROS
$tocados
FICHEROS
  done <<PATRONES
$(rutas_sensibles)
PATRONES

  if [ "$sensible" = 1 ]; then
    tramo=sensible; nivel=max
    motivo="toca $fichero_malo, que casa con '$patron_malo'"
  elif [ "$lineas_diff" -gt "${LIMITE_GRANDE:-600}" ]; then
    tramo=sensible; nivel=max
    motivo="$lineas_diff líneas cambiadas (más de ${LIMITE_GRANDE:-600})"
  elif [ "$lineas_diff" -le "${LIMITE_TRIVIAL:-30}" ] && [ "$nuevos" -eq 0 ]; then
    tramo=trivial; nivel=low
    motivo="$lineas_diff líneas, ningún fichero nuevo y nada delicado"
  else
    tramo=normal; nivel=high
    motivo="$lineas_diff líneas y $nuevos fichero(s) nuevo(s), nada delicado"
  fi
}

# ── La PR ───────────────────────────────────────────────────────────────────
# Lo único que hace falta saber ANTES de gastar tiempo en verificar y en revisar:
# que haya algo que empujar. Vivía dentro de `empujar_y_abrir_pr`, o sea DESPUÉS
# de los dos frenos, y con eso una rama sin un solo commit se comía el
# `verificar.sh` entero —minuto y medio de matrices en este repositorio— para
# acabar diciendo que no había nada que hacer.
#
# `ya_traido` para no traer dos veces: lo llaman probar-rama.sh al principio y
# `empujar_y_abrir_pr` después, y el segundo `fetch` no aportaría nada.
hay_algo_que_empujar() {
  [ "$hubo_remoto" = 1 ] || morir "Este repositorio no tiene remoto: no hay PR."

  [ "${ya_traido:-0}" = 1 ] || {
    git -C "$raiz" fetch origin --quiet --prune
    ya_traido=1
  }
  pendientes=$(git -C "$raiz" rev-list --count "origin/$principal..$rama")
  [ "$pendientes" -gt 0 ] ||
    morir "La rama '$rama' no tiene ningún commit que origin/$principal no tenga."
}

# Empuja y deja `numero` y `estado` puestos. Abre la PR si no la había.
empujar_y_abrir_pr() {
  hay_algo_que_empujar

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
  # Global a propósito —lo lee `anotar_rojo`—, y vacía desde ya: hay dos salidas
  # tempranas antes de que se llene, y bajo `set -u` mencionarla sin haberla
  # tocado mataría a quien la lea.
  checks_malos=""

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
  # Los nombres a secas, para que `anotar_rojo` pueda comparar esta ronda con
  # las anteriores. Ordenados y sin repetir: lo que importa es el conjunto.
  checks_malos=$(printf '%s' "$salida" |
    jq -r '.[] | select(.bucket == "fail" or .bucket == "cancel") | .name' |
    sort -u | tr '\n' ' ')
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

# ── Las rondas contra un CI rojo ────────────────────────────────────────────
# Un rojo se arregla sin preguntar, pero un bucle contra un rojo que no se va
# —un flaky, un secreto que falta— quema rondas de CI y revisiones de Opus sin
# mover nada. El freno existía desde el 14-08-2026, y vivía en la cabeza del
# modelo: «apunta los nombres de cada ronda y compáralos contra todas las
# anteriores». Eso es exactamente lo que un modelo hace mal y un fichero hace
# bien, así que *(17-08-2026)* se muda aquí.
#
# El fichero vive al lado de la marca de revisión, en el directorio git del
# worktree: no se commitea, no viaja, y se va con el worktree. Una línea por
# ronda, «<sha> <tab> <nombres de los checks que fallaron>».
ruta_rondas() {
  local gitdir
  gitdir=$(git -C "$ruta_wt" rev-parse --absolute-git-dir 2>/dev/null) || return 1
  printf '%s/rondas-ci' "$gitdir"
}

olvidar_rondas() {
  local f
  f=$(ruta_rondas) || return 0
  rm -f "$f"
}

# Apunta esta ronda y deja puesto `parar` a 1 si hay que dejar de intentarlo.
# Dos condiciones, y hacen falta las dos:
#
#   · tres rondas en rojo —o sea, dos arreglos automáticos ya gastados—;
#   · o un check que YA falló en una ronda anterior y vuelve a fallar, aunque
#     entre medias fallara otro distinto. Con `--fail-fast` los hermanos salen
#     como `cancel`, que también cuenta como rojo, así que el nombre del que
#     falla rota solo y «dos veces seguidas» no distinguiría nada.
anotar_rojo() {
  local f cabeza previos nombre rondas repetido=""
  parar=0
  f=$(ruta_rondas) || return 0
  cabeza=$(git -C "$ruta_wt" rev-parse HEAD)

  # Antes de apuntar, ¿alguno de los de ahora ya falló con OTRO commit? Con el
  # mismo commit no cuenta: relanzar sin tocar nada no es una ronda nueva.
  previos=$(grep -v "^$cabeza	" "$f" 2>/dev/null || true)
  # El `if` completo y no un `&& repetido=…`: bajo `set -e` una lista `a && b`
  # cuyo primer trozo falla deja el estado en 1, y aquí eso se paga tarde y en
  # otro sitio.
  for nombre in $checks_malos; do
    if printf '%s' "$previos" | grep -qF "$nombre"; then repetido="$nombre"; fi
  done

  grep -q "^$cabeza	" "$f" 2>/dev/null ||
    printf '%s\t%s\n' "$cabeza" "$checks_malos" >> "$f"
  rondas=$(grep -c . "$f" 2>/dev/null || true)
  [ -n "$rondas" ] || rondas=1

  if [ -n "$repetido" ]; then
    parar=1
    aviso "" \
      "PARO: '$repetido' ya había fallado en una ronda anterior." \
      "Un rojo que vuelve no lo arregla otra pasada: míralo tú."
  elif [ "$rondas" -ge "${RONDAS_MAXIMAS:-3}" ]; then
    parar=1
    aviso "" \
      "PARO: van $rondas rondas en rojo, y el arreglo automático son dos." \
      "El tiempo y el dinero son tuyos: mira los jobs de arriba."
  else
    aviso "" "Ronda $rondas en rojo. Quedan $(( ${RONDAS_MAXIMAS:-3} - rondas )) de arreglo automático."
  fi
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
