#!/bin/bash
# Matriz de abrir-rama.sh y cerrar-rama.sh. Monta su propio remoto, su propio
# repositorio y un GitHub de mentira, así que se ejecuta desde donde sea y no
# toca nada de verdad.
#
# El `gh` falso no devuelve JSON y ya: fusiona **de verdad** en un espejo del
# remoto. Sin eso, la comprobación de «¿está esta rama dentro de origin/main
# antes de borrarla?» —que es el único freno que separa limpiar de perder
# trabajo— se estaría probando contra una mentira.
#
# Al tocar cualquiera de los dos scripts: lánzalo, y rompe a propósito el caso
# que te importe para verlo fallar. Un test que no puede fallar es la falsa
# confianza de siempre.
set -uo pipefail

bin=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fallos=0
caso_actual=""

caso()  { caso_actual="$1"; printf '\n--- %s ---\n' "$1"; }
ok()    { printf '  ok      %s\n' "$1"; }
mal()   { printf '  FALLO   %s\n' "$1"; fallos=$((fallos + 1)); }
afirmar() { # afirmar <descripción> <condición...>
  local d=$1; shift
  if "$@" >/dev/null 2>&1; then ok "$d"; else mal "$d"; fi
}
negar() {   # negar <descripción> <condición...>
  local d=$1; shift
  if "$@" >/dev/null 2>&1; then mal "$d"; else ok "$d"; fi
}

# ── El GitHub de mentira ────────────────────────────────────────────────────
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'FALSO'
#!/bin/bash
set -eu
[ "${1:-}" = pr ] || exit 1
accion=$2
shift 2

case $accion in
  view)
    rama=$1
    printf '%s' "$rama" > "$ESTADO/rama"
    # Sin PR, el `gh` de verdad no imprime nada y sale 1 — también con
    # `--json url`. Hasta el 14-08-2026 este doble contestaba una URL ANTES de
    # mirar si la PR existía, así que el único caso que `recordar_url_pr`
    # existe para tolerar —una rama que nadie ha empujado, o sea `--solo-pila`
    # a la primera— no lo recorría ninguna prueba, y la línea en blanco que
    # eso imprime no la veía nadie hasta usarlo de verdad.
    [ -f "$ESTADO/pr-$rama" ] || exit 1
    case " $* " in
      *" --jq .url "*)    echo "https://example.test/pr/1" ;;
      *" --jq .state "*)  cat "$ESTADO/pr-$rama" ;;
      *" --jq .number "*) echo 1 ;;
    esac
    ;;
  create)
    rama=""
    while [ $# -gt 0 ]; do [ "$1" = --head ] && rama=$2; shift; done
    printf '%s' "$rama" > "$ESTADO/rama"
    echo OPEN > "$ESTADO/pr-$rama"
    echo "https://example.test/pr/1"
    ;;
  checks)
    # El `gh` de verdad RECHAZA `--watch` junto a `--json`, y este tiene que
    # rechazarlo igual: mientras se lo tragaba, la matriz daba verde con
    # `cerrar-rama.sh` incapaz de fusionar nada —salida vacía leída como «no hay
    # checks»—. Un doble más permisivo que el original no prueba el original.
    vigila=0; pide_json=0
    for bandera in "$@"; do
      case "$bandera" in
        --watch) vigila=1 ;;
        --json)  pide_json=1 ;;
      esac
    done
    if [ "$vigila" = 1 ] && [ "$pide_json" = 1 ]; then
      echo 'cannot use `--watch` with `--json` flag' >&2
      exit 1
    fi

    # Cuándo acabaron los checks, para saber si el verde es anterior al main de
    # ahora. El `--jq` de gh imprime un escalar en crudo, sin comillas, igual
    # que `jq -r`.
    case " $* " in
      *" --json completedAt "*)
        case "${ESCENARIO:-verde}" in
          # main se mueve y NO para: el guión tiene que rendirse, no fusionar.
          *-terco) echo "2020-01-01T00:00:00Z" ;;
          # main se movió después del verde, pero al meterlo en la rama el CI
          # nuevo ya es posterior. Sin esto no habría forma de salir del bucle.
          *-viejo)
            if grep -q update-branch "$ESTADO/gh.log" 2>/dev/null; then
              echo "2999-01-01T00:00:00Z"
            else
              echo "2020-01-01T00:00:00Z"
            fi ;;
          *) echo "2999-01-01T00:00:00Z" ;;   # el verde es más nuevo que main
        esac
        exit 0 ;;
    esac

    # Con `--watch` el de verdad bloquea hasta que terminan y NO imprime JSON;
    # aquí no hay nada que esperar, así que solo se calla.
    [ "$vigila" = 1 ] && exit 0

    case "${ESCENARIO:-verde}" in
      verde*)    echo '[{"bucket":"pass","name":"CI","link":"https://example.test/1"}]' ;;
      rojo)      echo '[{"bucket":"fail","name":"CI","link":"https://example.test/1"}]'; exit 1 ;;
      # El mismo rojo con OTRO nombre. Hace falta para el freno de las rondas:
      # con un solo nombre no se puede distinguir «otro check ha fallado» de
      # «vuelve a fallar el mismo», que es justo lo que decide si se sigue
      # intentando o se para.
      rojo-otro) echo '[{"bucket":"fail","name":"OTRO","link":"https://example.test/2"}]'; exit 1 ;;
      # Los nombres de verdad llevan espacios, y estos dos comparten palabra. Es
      # el caso que rompía el freno: pegando los nombres con espacios, `build`
      # de uno casaba con el otro y la cadena se paraba en el primer rojo
      # diciendo que un check se repetía.
      rojo-largo1) echo '[{"bucket":"fail","name":"build (ubuntu-latest)","link":"https://example.test/3"}]'; exit 1 ;;
      rojo-largo2) echo '[{"bucket":"fail","name":"build (macos-latest)","link":"https://example.test/4"}]'; exit 1 ;;
      corriendo) echo '[{"bucket":"pending","name":"CI","link":"https://example.test/1"}]' ;;
      *)         exit 1 ;;   # sin checks: gh no imprime JSON ninguno
    esac
    ;;
  update-branch)
    printf 'update-branch %s\n' "$*" >> "$ESTADO/gh.log"
    ;;
  merge)
    rama=$(cat "$ESTADO/rama")
    git -C "$ESPEJO" fetch -q origin
    git -C "$ESPEJO" checkout -q main
    git -C "$ESPEJO" merge -q --no-ff "origin/$rama" -m "Merge pull request #1 from t/$rama"
    git -C "$ESPEJO" push -q origin main
    echo MERGED > "$ESTADO/pr-$rama"
    # Muchos repositorios tienen activado «borrar la rama al fusionar».
    if [ "${ESCENARIO:-}" = verde-borra ]; then git -C "$ESPEJO" push -q origin --delete "$rama"; fi
    ;;
esac
FALSO
chmod +x "$TMP/bin/gh"
export GH="$TMP/bin/gh"

# Docker de mentira: no levanta nada, pero apunta todo lo que le piden. Las
# comprobaciones de la pila se hacen sobre ese registro, no sobre contenedores
# de verdad — la matriz no puede depender de que haya un Docker vivo.
#
# Qué volúmenes existen lo dice VOLUMENES (nombres separados por comas). Hasta el
# 13-08-2026 respondía que no existía ninguno, pase lo que pase, y con eso el
# clonado del volumen —el `volume create` y el `cp -a` que copian tus datos— no
# lo ejercitaba ni el docker falso: siempre se caía por la rama de «no hay nada
# que clonar».
cat > "$TMP/bin/docker" <<'FALSO'
#!/bin/bash
set -u
# El puerto no va en los argumentos sino delante, en el entorno, así que se
# apunta aparte o no habría forma de comprobar cuál se eligió.
if [ -n "${WEB_BIND_PORT:-}" ]; then
  printf 'WEB_BIND_PORT=%s %s\n' "$WEB_BIND_PORT" "$*" >> "$ESTADO/docker.log"
else
  printf '%s\n' "$*" >> "$ESTADO/docker.log"
fi
case "$1 ${2:-}" in
  "volume inspect")
    case ",${VOLUMENES:-}," in
      *",$3,"*) exit 0 ;;
      *)        exit 1 ;;
    esac ;;
  # `volume ls -q --filter name=^<proyecto>_`, que es como cerrar-rama.sh busca
  # lo que Compose no se lleva. Se responde con los de VOLUMENES que encajan con
  # ese patrón: si el doble contestara siempre lo mismo, el barrido parecería
  # correcto aunque se llevara por delante el volumen de la pila de siempre.
  "volume ls")
    patron=""
    for arg in "$@"; do
      case "$arg" in name=*) patron=${arg#name=} ;; esac
    done
    [ -n "$patron" ] || exit 0
    printf '%s' "${VOLUMENES:-}" | tr ',' '\n' | grep -E -- "$patron" || true
    exit 0 ;;
  # Un volumen que no se deja borrar —lo normal es que algo lo tenga cogido—,
  # para poder comprobar que eso se dice en vez de darse por hecho.
  "volume rm")
    [ "${VOLUMEN_ATASCADO:-0}" = 1 ] && exit 1
    exit 0 ;;
esac
case "$*" in
  *"ps -aq")
    # Qué pilas están levantadas lo dice PILAS (proyectos separados por comas).
    # Hasta el 14-08-2026 esto contestaba «hay un contenedor» pasara lo que
    # pasara, así que el camino de «aquí no había ninguna pila» —el normal desde
    # que levantarla se pide— no lo recorría ninguna prueba, y `cerrar-rama.sh`
    # podía presumir de una limpieza que no había hecho sin que nadie lo viera.
    proy=""; anterior=""
    for a in "$@"; do
      [ "$anterior" = -p ] && proy=$a
      anterior=$a
    done
    case ",${PILAS:-}," in
      *",$proy,"*) echo "contenedor-de-mentira" ;;
    esac ;;
esac
exit 0
FALSO
chmod +x "$TMP/bin/docker"
export DOCKER="$TMP/bin/docker"

cat > "$TMP/bin/avisador" <<'FALSO'
#!/bin/bash
printf '%s\n' "$*" >> "$ESTADO/avisos.log"
FALSO
chmod +x "$TMP/bin/avisador"
export AVISADOR="$TMP/bin/avisador"

# curl y nc de mentira. RESPONDE dice si la pila contesta; PUERTOS_PILLADOS,
# cuántos puertos seguidos se dan por ocupados antes de encontrar uno libre.
cat > "$TMP/bin/curl" <<'FALSO'
#!/bin/bash
printf '%s\n' "$*" >> "$ESTADO/curl.log"
[ "${RESPONDE:-0}" = 1 ]
FALSO
chmod +x "$TMP/bin/curl"
export CURL="$TMP/bin/curl"

cat > "$TMP/bin/nc" <<'FALSO'
#!/bin/bash
# `nc -z host puerto` sale 0 si hay alguien escuchando. Se finge que los
# primeros PUERTOS_PILLADOS lo están, para probar que se busca el siguiente.
n=$(cat "$ESTADO/nc.cuenta" 2>/dev/null || echo 0)
if [ "$n" -lt "${PUERTOS_PILLADOS:-0}" ]; then
  printf '%s' "$((n + 1))" > "$ESTADO/nc.cuenta"
  exit 0
fi
exit 1
FALSO
chmod +x "$TMP/bin/nc"
export NC="$TMP/bin/nc"

cat > "$TMP/bin/desplegar.sh" <<'FALSO'
#!/bin/bash
printf '%s\n' "$*" >> "$ESTADO/despliegues.log"
[ "${DESPLIEGUE_FALLA:-0}" = 1 ] && exit 1
exit 0
FALSO
chmod +x "$TMP/bin/desplegar.sh"
export DESPLEGAR="$TMP/bin/desplegar.sh"

# ── Un repositorio nuevo por caso ───────────────────────────────────────────
#
# Se monta UNA vez y se copia *(17-08-2026)*. Hay noventa y pico casos, y montar
# cada uno son ocho órdenes de git: la matriz tardaba 72 s con `sys 33s`, o sea
# casi todo arrancando procesos. Copiar el molde y reescribir la URL del remoto
# son dos, y da exactamente el mismo repositorio: lo único que un `cp -a` no
# puede traer bien son las rutas absolutas de dentro, que son esas dos.
plantilla=""
montar() {
  local d
  d=$(mktemp -d "$TMP/caso.XXXXXX")

  if [ -n "$plantilla" ]; then
    cp -a "$plantilla/." "$d"
    git -C "$d/repo"   remote set-url origin "$d/remoto.git"
    git -C "$d/espejo" remote set-url origin "$d/remoto.git"
    ( cd "$d" && pwd -P | tr -d '\n' )
    return 0
  fi

  git init -q --bare -b main "$d/remoto.git"
  git init -q -b main "$d/repo"
  git -C "$d/repo" config user.email t@t
  git -C "$d/repo" config user.name t
  printf '.claude/worktrees/\n' > "$d/repo/.gitignore"
  printf 'uno\n' > "$d/repo/f"
  git -C "$d/repo" add -A
  git -C "$d/repo" commit -qm inicial
  git -C "$d/repo" remote add origin "$d/remoto.git"
  git -C "$d/repo" push -q -u origin main
  git -C "$d/repo" remote set-head origin -a >/dev/null
  git -C "$d/repo" fetch -q origin
  git clone -q "$d/remoto.git" "$d/espejo"
  git -C "$d/espejo" config user.email t@t
  git -C "$d/espejo" config user.name t
  mkdir -p "$d/estado"

  # El molde para los demás casos. Se guarda ya montado y sin tocar: este primer
  # caso se queda con el original, y los siguientes reciben una copia idéntica.
  plantilla="$TMP/plantilla"
  cp -a "$d" "$plantilla"

  # Resuelta: en macOS /var es un enlace a /private/var, y los scripts imprimen
  # la ruta que da git, que ya viene resuelta. Comparar sin esto es comparar
  # dos formas de escribir el mismo sitio.
  ( cd "$d" && pwd -P | tr -d '\n' )
}

# Commit de mentira en la rama, para que haya algo que fusionar.
trabajar() { # trabajar <ruta-del-worktree> <texto>
  # ⚠️ La ruta se comprueba antes de tocar nada. `abrir` imprime la ruta del
  # worktree, y cuando falla imprime NADA: entonces `$1` llega vacío y
  # `git -C ""` —que git documenta como «deja el directorio actual sin
  # cambiar»— hace el `add -A` y el `commit` sobre el repositorio DE VERDAD
  # desde el que se lanzó la matriz. El 14-08-2026 una pasada se llevó así el
  # trabajo sin guardar de esta misma rama dentro de un commit «feat: uno».
  # Una matriz que puede commitear el repositorio que está probando no es una
  # matriz, y el fallo no se ve: sale verde y el destrozo está en otro sitio.
  [ -n "${1:-}" ] && [ -d "$1" ] ||
    { mal "trabajar necesita un worktree y ha recibido '${1:-}'"; return 1; }
  printf '%s\n' "$2" > "$1/nuevo.txt"
  git -C "$1" add -A
  git -C "$1" commit -qm "feat: $2"
}

# Lo mismo, pero de solo documentación: es lo que `--solo-md` tiene que dejar
# pasar. Mismo freno de la ruta vacía, y por el mismo motivo.
documentar() { # documentar <ruta-del-worktree> <texto>
  [ -n "${1:-}" ] && [ -d "$1" ] ||
    { mal "documentar necesita un worktree y ha recibido '${1:-}'"; return 1; }
  printf '%s\n' "$2" >> "$1/LEEME.md"
  git -C "$1" add -A
  git -C "$1" commit -qm "docs: $2"
}

# Imprime la ruta del worktree, y cuando falla imprime una ruta IMPOSIBLE en vez
# de nada. Una ruta vacía es lo peligroso, y no por poco: `git -C ""` no falla
# —git lo documenta como «deja el directorio actual sin cambiar»—, así que un
# `git -C "$ruta" commit` con `$ruta` vacía commitea el repositorio que la matriz
# está probando. El 14-08-2026 lo hizo, y salió verde: el destrozo no estaba en
# ninguna aserción, estaba en otro repositorio.
#
# El freno va AQUÍ y no en cada consumidor porque los consumidores son ocho y el
# noveno lo escribirá alguien que no habrá leído esto. Con una ruta imposible,
# cualquier `git -C` que la reciba falla en el sitio y a la vista.
#
# El código de salida se conserva: hay casos que llaman a `abrir` esperando que
# falle —`negar "se niega a llamarse main" abrir …`— y juzgan por él.
abrir() {            # abrir <dir-del-caso> <rama>
  local ruta codigo=0
  ruta=$( cd "$1/repo" && ESTADO="$1/estado" ESPEJO="$1/espejo" "$bin/abrir-rama.sh" "$2" ) ||
    codigo=$?
  printf '%s' "${ruta:-/worktree-que-no-se-pudo-abrir}"
  return "$codigo"
}

# cerrar <escenario> <dir> [args…]. El escenario va de argumento y no de
# `ESCENARIO=x cerrar …` por dos motivos que ya costaron cuatro falsos verdes:
# `env VAR=x cerrar` no encuentra la función —busca un binario— y una asignación
# delante de una función de bash se queda puesta DESPUÉS de la llamada, así que
# se derramaría al caso siguiente.
cerrar() {
  local esc=$1 d=$2; shift 2
  # ESPERA_CHECKS=0: sin esto, el caso de «hay workflows pero no aparecen checks»
  # se comería el minuto de gracia de verdad en cada pasada.
  ( cd "$d/repo" &&
      ESTADO="$d/estado" ESPEJO="$d/espejo" ESCENARIO="$esc" ESPERA_CHECKS=0 \
      DESPLIEGUE_FALLA="${DESPLIEGUE_FALLA:-0}" VOLUMENES="${VOLUMENES:-}" \
      VOLUMEN_ATASCADO="${VOLUMEN_ATASCADO:-0}" PILAS="${PILAS:-}" \
      "$bin/cerrar-rama.sh" "$@" )
}

# Un CI de mentira, para separar «aquí no hay CI» de «aquí hay CI y esta PR no
# dispara nada», que es lo que hace el `paths-ignore` de welzy con las PRs de
# solo documentación.
#
# La forma del `on:` es un argumento porque YAML admite cuatro y hasta el
# 13-08-2026 solo se reconocía la de mapa. Escribir el workflow siempre igual es
# lo que dejó pasar el fallo: `prespuestos-obras` usa la de lista y su repositorio
# entero se leía como «sin CI».
escribir_workflow() {   # escribir_workflow <fichero> [forma]
  case "${2:-mapa}" in
    mapa)      printf 'name: CI\non:\n  pull_request:\njobs:\n  x:\n    runs-on: ubuntu-latest\n' ;;
    lista)     printf 'name: CI\non: [push, pull_request]\njobs:\n  x:\n    runs-on: ubuntu-latest\n' ;;
    escalar)   printf 'name: CI\non: pull_request\njobs:\n  x:\n    runs-on: ubuntu-latest\n' ;;
    secuencia) printf 'name: CI\non:\n  - push\n  - pull_request\njobs:\n  x:\n    runs-on: ubuntu-latest\n' ;;
    solo-push) printf 'name: CI\non:\n  push:\n    branches: [main]\njobs:\n  x:\n    runs-on: ubuntu-latest\n' ;;
  esac > "$1"
}

con_workflow() { # con_workflow <dir> [forma]
  mkdir -p "$1/repo/.github/workflows"
  escribir_workflow "$1/repo/.github/workflows/ci.yml" "${2:-mapa}"
  git -C "$1/repo" add -A
  git -C "$1/repo" commit -qm "ci: workflow de mentira"
  git -C "$1/repo" push -q origin main
}

probar_rama() {  # probar_rama <escenario> <dir> [args…]
  local esc=$1 d=$2; shift 2
  ( cd "$d/repo" &&
      ESTADO="$d/estado" ESPEJO="$d/espejo" ESCENARIO="$esc" ESPERA_CHECKS=0 ESPERA_PILA=1 \
      VOLUMENES="${VOLUMENES:-}" RESPONDE="${RESPONDE:-0}" \
      PUERTOS_PILLADOS="${PUERTOS_PILLADOS:-0}" \
      LIMITE_TRIVIAL="${LIMITE_TRIVIAL:-30}" LIMITE_GRANDE="${LIMITE_GRANDE:-600}" \
      RONDAS_MAXIMAS="${RONDAS_MAXIMAS:-3}" \
      "$bin/probar-rama.sh" "$@" )
}

# El puerto que le toca a una rama, calculado igual que puerto_de_rama pero
# aquí fuera: si se leyera del propio guión, la prueba diría que sí a cualquier
# cosa que hiciera.
puerto_esperado() { # puerto_esperado <rama>
  printf '%s' "$(( 8100 + $(printf '%s' "$1" | cksum | awk '{print $1}') % 400 ))"
}

# Un repositorio que se despliega: el contrato de cmdlo son estas dos cosas.
con_contrato_de_despliegue() {  # con_contrato_de_despliegue <dir>
  mkdir -p "$1/repo/ops/deploy" "$1/repo/.github/workflows"
  printf '#!/bin/sh\n' > "$1/repo/ops/deploy/deploy.sh"
  printf 'name: Release\non:\n  push:\n    branches: [main]\n' > "$1/repo/.github/workflows/release.yml"
  git -C "$1/repo" add -A
  git -C "$1/repo" commit -qm "ops: contrato de despliegue de mentira"
  git -C "$1/repo" push -q origin main
}

con_compose() {  # con_compose <dir>
  printf 'services:\n  frontend:\n    image: nginx\n' > "$1/repo/docker-compose.yml"
  git -C "$1/repo" add -A
  git -C "$1/repo" commit -qm "compose de mentira"
  git -C "$1/repo" push -q origin main
}

# El verificar.sh de la rama: formato, lint y unitarios en el repo de verdad;
# aquí, un `exit` que se elige. Va a main ANTES de abrir la rama, que es como
# llega a los worktrees.
#
# Apunta su directorio de trabajo, porque de dónde se lanza no es un detalle: el
# de la RAMA es el que la rama ha podido cambiar, y un `verificar.sh` que se
# lanzara desde la raíz estaría comprobando otro árbol.
con_verificar() {  # con_verificar <dir> <código-de-salida>
  printf '#!/bin/sh\npwd > "$ESTADO/verificar.cwd"\necho "verificar.sh de mentira"\nexit %s\n' "$2" > "$1/repo/verificar.sh"
  chmod +x "$1/repo/verificar.sh"
  git -C "$1/repo" add -A
  git -C "$1/repo" commit -qm "verificar.sh de mentira (sale $2)"
  git -C "$1/repo" push -q origin main
}

# Lo que deja la skill `probar` después de pasar el revisor por el diff. El
# nivel por defecto es `max` —el más alto— a propósito: estos casos no van del
# nivel, y con el más alto ninguno se cae por el freno del tramo. Los que SÍ van
# del nivel lo escriben.
revisar() { ( cd "$1/repo" && "$bin/marcar-revisado.sh" "$2" --nivel "${3:-max}" ); }

# El tramo de riesgo de una rama. Los dos umbrales viajan por el entorno para
# poder probar el tramo de «esto es enorme» sin escribir seiscientas líneas.
clasificar() { # clasificar <dir> <rama> [args…]
  local d=$1; shift
  ( cd "$d/repo" &&
      LIMITE_TRIVIAL="${LIMITE_TRIVIAL:-30}" LIMITE_GRANDE="${LIMITE_GRANDE:-600}" \
      "$bin/clasificar-diff.sh" "$@" )
}

# Un cambio que NO añade ficheros: toca el que ya existe. Es la diferencia entre
# el tramo trivial y el normal, y `trabajar` no sirve para probarlo porque crea
# uno nuevo cada vez.
retocar() { # retocar <ruta-del-worktree> <texto>
  [ -n "${1:-}" ] && [ -d "$1" ] ||
    { mal "retocar necesita un worktree y ha recibido '${1:-}'"; return 1; }
  printf '%s\n' "$2" >> "$1/f"
  git -C "$1" add -A
  git -C "$1" commit -qm "fix: $2"
}

# Un cambio en una ruta de las delicadas: casa con `*hooks/*` de la lista de
# serie, así que su tramo es `sensible` por mucho que sean dos líneas.
tocar_delicado() { # tocar_delicado <ruta-del-worktree>
  [ -n "${1:-}" ] && [ -d "$1" ] ||
    { mal "tocar_delicado necesita un worktree y ha recibido '${1:-}'"; return 1; }
  mkdir -p "$1/hooks"
  printf '#!/bin/sh\nexit 0\n' > "$1/hooks/freno.sh"
  git -C "$1" add -A
  git -C "$1" commit -qm "hooks: un freno"
}

registro() { cat "$1/estado/$2" 2>/dev/null || true; }

contiene()    { printf '%s' "$2" | grep -qF -- "$1"; }
no_contiene() { ! printf '%s' "$2" | grep -qF -- "$1"; }

hay_worktree() { [ -d "$1/repo/.claude/worktrees/wt$2" ]; }
hay_rama()     { git -C "$1/repo" show-ref --quiet --verify "refs/heads/$2"; }
hay_remota()   { git -C "$1/repo" ls-remote --exit-code --heads origin "$2" >/dev/null 2>&1; }

# ════════════════════════════════════════════════════════════════════════════
caso "la matriz no puede commitear el repositorio que está probando"
# El 14-08-2026 lo hizo: `abrir` falló, `trabajar` recibió la ruta vacía y
# `git -C ""` —documentado como «deja el directorio actual sin cambiar»— hizo el
# `add -A` y el `commit` sobre el repositorio desde el que se lanzó la matriz.
# Se llevó dentro el trabajo sin guardar de la rama, y salió verde igual: el
# destrozo no estaba en ninguna aserción, estaba en otro sitio.
#
# En un subshell a propósito: `trabajar` avisa con `mal`, y aquí el fallo es lo
# que se espera, así que no puede contar como fallo de la matriz.
antes=$(git rev-parse HEAD 2>/dev/null || printf 'sin-repo')
( trabajar "" uno ) >/dev/null 2>&1 && guardado=0 || guardado=1
afirmar "trabajar sin worktree se niega"    test "$guardado" = 1
afirmar "y no commitea nada donde está"     test "$antes" = "$(git rev-parse HEAD 2>/dev/null || printf 'sin-repo')"

# Y el freno de verdad está un piso más arriba, en `abrir`: los ocho sitios que
# usan `$ruta` no pasan todos por `trabajar` —dos hacen su propio `git -C
# "$ruta" commit`—, así que lo que no puede existir es la ruta vacía.
d=$(montar)
ruta=$(abrir "$d" main 2>/dev/null) && fallo=0 || fallo=1
afirmar "abrir se niega con un nombre inválido"  test "$fallo" = 1
negar   "y NO devuelve una ruta vacía"           test -z "$ruta"
negar   "ni una que git -C pueda confundir con «aquí»" test -d "$ruta"

caso "abrir-rama.sh: lo que tiene que salir bien"
d=$(montar)
ruta=$(abrir "$d" la-rama 2>/dev/null)
afirmar "crea el worktree en .claude/worktrees/wtla-rama" hay_worktree "$d" la-rama
afirmar "la rama existe"                                  hay_rama "$d" la-rama
afirmar "imprime su ruta en la salida estándar" test "$ruta" = "$d/repo/.claude/worktrees/wtla-rama"

caso "abrir-rama.sh: la rama sale de origin/main, no del HEAD local"
d=$(montar)
printf 'basura local\n' > "$d/repo/sin-empujar.txt"
git -C "$d/repo" add -A >/dev/null
git -C "$d/repo" commit -qm "commit local que nadie ha visto"
abrir "$d" limpia >/dev/null 2>&1
negar "el commit local sin empujar NO se cuela en la rama nueva" \
  test -f "$d/repo/.claude/worktrees/wtlimpia/sin-empujar.txt"

caso "abrir-rama.sh: lo que tiene que negarse"
d=$(montar)
negar "se niega a llamarse main"                 abrir "$d" main
negar "se niega a llamarse master"               abrir "$d" master
negar "se niega al nombre del harness"           abrir "$d" sleepy-pare-10a9f6
negar "se niega a un nombre inválido para git"   abrir "$d" "con espacio"
abrir "$d" ya-existe >/dev/null 2>&1
negar "se niega si la rama ya existe"            abrir "$d" ya-existe

# ════════════════════════════════════════════════════════════════════════════
caso "cerrar-rama.sh: el freno"
d=$(montar); ruta=$(abrir "$d" sucia 2>/dev/null); trabajar "$ruta" uno
printf 'a medias\n' > "$ruta/a-medias.txt"
negar    "para con el árbol sucio"                      cerrar verde "$d" sucia
afirmar  "y NO ha borrado el worktree"                  hay_worktree "$d" sucia
afirmar  "y NO ha borrado la rama"                      hay_rama "$d" sucia
afirmar  "--forzar sí cierra"                           cerrar verde "$d" sucia --forzar
negar    "ahora el worktree no está"                    hay_worktree "$d" sucia

caso "cerrar-rama.sh: se niega desde dentro del worktree"
d=$(montar); ruta=$(abrir "$d" desde-dentro 2>/dev/null); trabajar "$ruta" uno
if ( cd "$ruta" && ESTADO="$d/estado" ESPEJO="$d/espejo" ESCENARIO=verde "$bin/cerrar-rama.sh" desde-dentro ) >/dev/null 2>&1
then mal "se niega a borrar el directorio en el que está"
else ok  "se niega a borrar el directorio en el que está"; fi
afirmar "el worktree sigue" hay_worktree "$d" desde-dentro

caso "cerrar-rama.sh: el CI manda"
d=$(montar); ruta=$(abrir "$d" en-rojo 2>/dev/null); trabajar "$ruta" uno
negar   "CI en rojo: no fusiona"        cerrar rojo "$d" en-rojo
afirmar "y no ha borrado el worktree"   hay_worktree "$d" en-rojo
afirmar "y no ha borrado la rama"       hay_rama "$d" en-rojo

d=$(montar); ruta=$(abrir "$d" sin-ci 2>/dev/null); trabajar "$ruta" uno
afirmar "sin checks: sale bien, pero…"  cerrar sin-checks "$d" sin-ci
afirmar "…deja el worktree en pie"      hay_worktree "$d" sin-ci
afirmar "…y la rama sin fusionar"       hay_rama "$d" sin-ci

caso "cerrar-rama.sh: vigilar el CI no puede costar su veredicto"
# `gh` rechaza `--watch` junto a `--json`. Pedirlos a la vez dejaba la salida
# VACÍA, o sea un verde de verdad leído como «no ha disparado ningún check»: con
# eso, `cerrar-rama.sh` no fusionaba nada en ningún repositorio. Se prueba con
# workflows configurados, que es donde se vigila de verdad y donde la salida
# vacía además se explicaba sola con lo del `paths-ignore`.
d=$(montar); con_workflow "$d"; ruta=$(abrir "$d" verde-vigilado 2>/dev/null); trabajar "$ruta" uno
msg=$(cerrar verde "$d" verde-vigilado 2>&1) && cerrado=0 || cerrado=1
afirmar "en verde y con CI configurado, fusiona"  test "$cerrado" = 0
negar   "no lo confunde con «sin checks»"         contiene "paths-ignore" "$msg"
negar   "no queda worktree"                       hay_worktree "$d" verde-vigilado
negar   "no queda rama local"                     hay_rama "$d" verde-vigilado

# Y un check que todavía corre tampoco es un aprobado: se llega aquí si el
# `--watch` se cae a mitad, y dar eso por verde es fusionar sin examen.
d=$(montar); con_workflow "$d"; ruta=$(abrir "$d" en-curso 2>/dev/null); trabajar "$ruta" uno
negar   "pendiente: no fusiona"          cerrar corriendo "$d" en-curso
afirmar "y no ha borrado el worktree"    hay_worktree "$d" en-curso
afirmar "y no ha borrado la rama"        hay_rama "$d" en-curso

caso "cerrar-rama.sh: «sin checks» no es lo mismo que «sin CI»"
d=$(montar); ruta=$(abrir "$d" sin-ninguno 2>/dev/null); trabajar "$ruta" uno
msg=$(cerrar sin-checks "$d" sin-ninguno 2>&1)
afirmar "sin workflows, dice que el repo no tiene CI" \
        contiene "este repositorio no tiene CI" "$msg"

# Con CI configurado, «no hay checks» ya no puede explicarse como «no hay CI»:
# es lo que pasó de verdad en welzy con la PR #107, que solo tocaba markdown.
d=$(montar); con_workflow "$d"; ruta=$(abrir "$d" con-ci-sin-checks 2>/dev/null); trabajar "$ruta" uno
msg=$(cerrar sin-checks "$d" con-ci-sin-checks 2>&1)
afirmar "con workflows, NO dice que el repo no tenga CI" \
        no_contiene "este repositorio no tiene CI" "$msg"
afirmar "y nombra el paths-ignore como causa probable" contiene "paths-ignore" "$msg"
afirmar "tampoco fusiona"                              hay_rama "$d" con-ci-sin-checks
afirmar "ni borra el worktree"                         hay_worktree "$d" con-ci-sin-checks

caso "cerrar-rama.sh: las cuatro formas de escribir 'on:' son CI igual"
# YAML admite las cuatro y hasta el 13-08-2026 solo se veía la de mapa. La de
# lista es la de `prespuestos-obras`, que además no tiene otro workflow: su
# repositorio entero se leía como «sin CI» teniéndolo.
for forma in mapa lista escalar secuencia; do
  d=$(montar); con_workflow "$d" "$forma"
  ruta=$(abrir "$d" "forma-$forma" 2>/dev/null); trabajar "$ruta" uno
  msg=$(cerrar sin-checks "$d" "forma-$forma" 2>&1)
  afirmar "on: en forma de $forma se reconoce como CI" \
          no_contiene "este repositorio no tiene CI" "$msg"
done

# Y lo contrario: un workflow que NO se dispara con PRs no es CI de PR.
d=$(montar); con_workflow "$d" solo-push
ruta=$(abrir "$d" solo-con-push 2>/dev/null); trabajar "$ruta" uno
msg=$(cerrar sin-checks "$d" solo-con-push 2>&1)
afirmar "un workflow de solo push no cuenta como CI de PR" \
        contiene "este repositorio no tiene CI" "$msg"

caso "cerrar-rama.sh: el CI que mira es el de LA RAMA"
# Una rama que AÑADE el CI es justo el caso en que la raíz todavía no lo tiene.
# Mirando la raíz, esa rama se juzgaba como «aquí no hay CI» — y el repositorio
# donde eso pasa es precisamente el que acaba de ganar sus pruebas.
d=$(montar)
ruta=$(abrir "$d" trae-el-ci 2>/dev/null)
mkdir -p "$ruta/.github/workflows"
escribir_workflow "$ruta/.github/workflows/ci.yml" mapa
git -C "$ruta" add -A
git -C "$ruta" commit -qm "ci: lo trae la rama"
msg=$(cerrar sin-checks "$d" trae-el-ci 2>&1)
afirmar "el workflow que solo está en la rama cuenta" \
        no_contiene "este repositorio no tiene CI" "$msg"

caso "cerrar-rama.sh: verde de punta a punta"
d=$(montar); ruta=$(abrir "$d" verde 2>/dev/null); trabajar "$ruta" uno
afirmar "cierra sin error"              cerrar verde "$d" verde
negar   "no queda worktree"             hay_worktree "$d" verde
negar   "no queda rama local"           hay_rama "$d" verde
negar   "no queda rama remota"          hay_remota "$d" verde
afirmar "la raíz sigue en main"         test "$(git -C "$d/repo" rev-parse --abbrev-ref HEAD)" = main
afirmar "y main está adelantado con lo de la rama" test -f "$d/repo/nuevo.txt"

caso "cerrar-rama.sh: si GitHub ya borró la rama remota, no falla"
d=$(montar); ruta=$(abrir "$d" ya-borrada 2>/dev/null); trabajar "$ruta" uno
afirmar "cierra igual"                  cerrar verde-borra "$d" ya-borrada
negar   "no queda rama local"           hay_rama "$d" ya-borrada

caso "cerrar-rama.sh: la raíz no siempre está en main"
d=$(montar); ruta=$(abrir "$d" con-raiz-fuera 2>/dev/null); trabajar "$ruta" uno
git -C "$d/repo" checkout -q -b otra-cosa
afirmar "cierra igual, avisando"        cerrar verde "$d" con-raiz-fuera
negar   "no queda worktree"             hay_worktree "$d" con-raiz-fuera
afirmar "y NO ha movido la raíz"        test "$(git -C "$d/repo" rev-parse --abbrev-ref HEAD)" = otra-cosa

d=$(montar); ruta=$(abrir "$d" con-raiz-sucia 2>/dev/null); trabajar "$ruta" uno
printf 'a medias en la raíz\n' > "$d/repo/raiz-a-medias.txt"
afirmar "con la raíz sucia cierra igual" cerrar verde "$d" con-raiz-sucia
afirmar "y no se lleva por delante lo que había" test -f "$d/repo/raiz-a-medias.txt"

caso "cerrar-rama.sh: --solo-limpiar"
d=$(montar); ruta=$(abrir "$d" limpiar-despues 2>/dev/null); trabajar "$ruta" uno
cerrar verde "$d" limpiar-despues >/dev/null 2>&1   # fusionada de verdad
d2=$(montar); ruta2=$(abrir "$d2" sin-fusionar 2>/dev/null); trabajar "$ruta2" uno
negar   "se niega a limpiar una rama que no está en origin/main" \
        cerrar verde "$d2" sin-fusionar --solo-limpiar
afirmar "y no ha borrado nada"          hay_rama "$d2" sin-fusionar

# Y el camino feliz, que es para lo que existe la opción: la PR se fusionó por
# otro lado —a mano en GitHub, o porque el repositorio no tenía CI— y aquí solo
# queda recoger.
d=$(montar); ruta=$(abrir "$d" fusionada-fuera 2>/dev/null); trabajar "$ruta" uno
git -C "$d/repo" push -q -u origin fusionada-fuera
git -C "$d/espejo" fetch -q origin
git -C "$d/espejo" merge -q --no-ff origin/fusionada-fuera -m "fusionada por otro camino"
git -C "$d/espejo" push -q origin main
afirmar "--solo-limpiar recoge una rama ya fusionada" \
        cerrar verde "$d" fusionada-fuera --solo-limpiar
negar   "no queda worktree"             hay_worktree "$d" fusionada-fuera
negar   "no queda rama local"           hay_rama "$d" fusionada-fuera
negar   "no queda rama remota"          hay_remota "$d" fusionada-fuera

caso "cerrar-rama.sh: lo que no tiene sentido"
d=$(montar)
negar "se niega sobre main"             cerrar verde "$d" main
negar "se niega sobre master"           cerrar verde "$d" master
negar "se niega con una rama que no existe" cerrar verde "$d" no-existe
abrir "$d" sin-commits >/dev/null 2>&1
negar "se niega si la rama no tiene ningún commit" cerrar verde "$d" sin-commits
afirmar "y la deja donde estaba"        hay_rama "$d" sin-commits

# ════════════════════════════════════════════════════════════════════════════
caso "probar-rama.sh: no fusiona NUNCA, que es toda su razón de ser"
d=$(montar); con_workflow "$d"; ruta=$(abrir "$d" en-pruebas 2>/dev/null); trabajar "$ruta" uno
revisar "$d" en-pruebas >/dev/null 2>&1
afirmar "con el CI verde, sale bien"        probar_rama verde "$d" en-pruebas
afirmar "y la rama sigue SIN fusionar"      hay_rama "$d" en-pruebas
afirmar "y su worktree sigue en pie"        hay_worktree "$d" en-pruebas
afirmar "y la rama remota sigue viva"       hay_remota "$d" en-pruebas

caso "probar-rama.sh: la pila NO se levanta sola"
# Levantar una pila construye imágenes, clona el volumen de datos y ocupa un
# puerto. Hasta el 14-08-2026 pasaba solo, en cada verde, mirase el usuario la
# rama o no. Ahora se pide, y el defecto es no tocar nada.
d=$(montar); con_workflow "$d"; con_compose "$d"
ruta=$(abrir "$d" sin-pedirla 2>/dev/null); trabajar "$ruta" uno
revisar "$d" sin-pedirla >/dev/null 2>&1
msg=$(probar_rama verde "$d" sin-pedirla 2>&1) && salio=0 || salio=1
afirmar "sin banderas sale bien"            test "$salio" = 0
afirmar "y no levanta absolutamente nada"   test -z "$(registro "$d" docker.log)"
# «espero al CI de la PR #N» es contrato desde el 14-08-2026: es la línea que la
# skill `probar` vigila para preguntar por la pila mientras el CI corre. Si el
# texto cambia, la skill no la ve y la pregunta llega doce minutos tarde.
afirmar "anuncia el CI con la línea que la skill vigila" contiene "espero al CI de la PR #1" "$msg"
afirmar "da la URL de la PR"                contiene "PR:      https://example.test/pr/1" "$msg"
afirmar "y dice cómo levantarla luego"      contiene "probar-rama.sh sin-pedirla --solo-pila" "$msg"
afirmar "la rama sigue sin fusionar"        hay_rama "$d" sin-pedirla
# El aviso del sistema era el final de la pila, y la pila ha dejado de ser el
# final. Sin esto, el camino que la skill manda lanzar con `run_in_background`
# —y que en welzy tarda doce minutos— termina sin que suene nada.
afirmar "y avisa por el sistema al acabar"  contiene "Lista para mirar la PR" "$(registro "$d" avisos.log)"

caso "probar-rama.sh: el veredicto del CI manda también sin pila"
# Los dos casos de abajo llevaban `--con-pila` desde que se partió la bandera, y
# con eso el camino POR DEFECTO —el que se usa siempre— dejó de probar que un CI
# en rojo sale con error. Un rojo que saliera con 0 diría «la PR está esperando»
# de una rama rota, y de ahí se va derecho a cerrar-rama.sh.
d=$(montar); con_workflow "$d"; con_compose "$d"
ruta=$(abrir "$d" rojo-por-defecto 2>/dev/null); trabajar "$ruta" uno
revisar "$d" rojo-por-defecto >/dev/null 2>&1
msg=$(probar_rama rojo "$d" rojo-por-defecto 2>&1) && rojo=0 || rojo=1
afirmar "CI en rojo y sin banderas: sale con error" test "$rojo" = 1
afirmar "y aun así da la URL de la PR"      contiene "PR:      https://example.test/pr/1" "$msg"
afirmar "y avisa por el sistema"            contiene "El CI no está verde" "$(registro "$d" avisos.log)"

d=$(montar); con_workflow "$d"; con_compose "$d"
ruta=$(abrir "$d" sin-checks-por-defecto 2>/dev/null); trabajar "$ruta" uno
revisar "$d" sin-checks-por-defecto >/dev/null 2>&1
msg=$(probar_rama sin-checks "$d" sin-checks-por-defecto 2>&1) && sc=0 || sc=1
afirmar "sin checks y sin banderas: sale bien"  test "$sc" = 0
afirmar "y también da la URL de la PR"      contiene "PR:      https://example.test/pr/1" "$msg"

caso "probar-rama.sh: sin verde no levanta nada, aunque se pida"
d=$(montar); con_workflow "$d"; con_compose "$d"
ruta=$(abrir "$d" rojo-no-levanta 2>/dev/null); trabajar "$ruta" uno
revisar "$d" rojo-no-levanta >/dev/null 2>&1
negar   "CI en rojo: sale con error"        probar_rama rojo "$d" rojo-no-levanta --con-pila
afirmar "y no ha levantado ninguna pila"    no_contiene "up -d --build" "$(registro "$d" docker.log)"

d=$(montar); con_workflow "$d"; con_compose "$d"
ruta=$(abrir "$d" sin-checks-no-levanta 2>/dev/null); trabajar "$ruta" uno
revisar "$d" sin-checks-no-levanta >/dev/null 2>&1
afirmar "sin checks: sale bien…"            probar_rama sin-checks "$d" sin-checks-no-levanta --con-pila
afirmar "…pero tampoco levanta nada"        no_contiene "up -d --build" "$(registro "$d" docker.log)"

caso "probar-rama.sh: donde no hay pila, no se ofrece levantarla"
# Es el caso de dotfiles, que no tiene docker-compose.yml — o sea el repositorio
# donde este guión más corre. Ofrecía `--solo-pila` en cada pasada, y ese comando
# solo sabe contestar que aquí no hay nada que levantar.
d=$(montar); con_workflow "$d"
ruta=$(abrir "$d" sin-compose 2>/dev/null); trabajar "$ruta" uno
revisar "$d" sin-compose >/dev/null 2>&1
msg=$(probar_rama verde "$d" sin-compose 2>&1) && sinc=0 || sinc=1
afirmar "sale bien"                         test "$sinc" = 0
negar   "NO ofrece --solo-pila"             contiene "--solo-pila" "$msg"
afirmar "y dice por qué no hay pila"        contiene "no hay docker-compose.yml" "$msg"
afirmar "pero sí da la URL de la PR"        contiene "PR:      https://example.test/pr/1" "$msg"

# Y si se pide la pila donde no la hay, se dice y se sale bien: no es un fallo.
d=$(montar); con_workflow "$d"
ruta=$(abrir "$d" pedida-sin-compose 2>/dev/null); trabajar "$ruta" uno
revisar "$d" pedida-sin-compose >/dev/null 2>&1
msg=$(probar_rama verde "$d" pedida-sin-compose --con-pila 2>&1) && psc=0 || psc=1
afirmar "--con-pila sin compose sale bien"  test "$psc" = 0
afirmar "y lo explica"                      contiene "no hay pila que levantar" "$msg"
afirmar "sin intentar levantar nada"        test -z "$(registro "$d" docker.log)"

caso "probar-rama.sh: con --con-pila y en verde, levanta la de LA RAMA"
d=$(montar); con_workflow "$d"; con_compose "$d"
ruta=$(abrir "$d" pila-pedida 2>/dev/null); trabajar "$ruta" uno
revisar "$d" pila-pedida >/dev/null 2>&1
negar   "sin nadie escuchando, acaba diciéndolo" probar_rama verde "$d" pila-pedida --con-pila
log=$(registro "$d" docker.log)
afirmar "levantó un proyecto propio, no el de siempre" contiene "compose -p repo-pila-pedida up -d --build" "$log"
afirmar "y la rama sigue sin fusionar"      hay_rama "$d" pila-pedida

caso "probar-rama.sh: --solo-pila levanta y no toca nada más"
# El camino de «dije que no y he cambiado de idea». Lo caro de ese camino sería
# volver a empujar, reabrir la PR y esperar un CI que ya pasó hace diez minutos.
d=$(montar); con_workflow "$d"; con_compose "$d"
ruta=$(abrir "$d" me-lo-he-pensado 2>/dev/null); trabajar "$ruta" uno
RESPONDE=1
msg=$(probar_rama rojo "$d" me-lo-he-pensado --solo-pila 2>&1) && solo=0 || solo=1
RESPONDE=0
afirmar "sale bien aunque el CI esté en rojo"  test "$solo" = 0
afirmar "levanta la pila"                      contiene "compose -p repo-me-lo-he-pensado up -d --build" "$(registro "$d" docker.log)"
afirmar "y da la URL de la pila"               contiene "Lista para probar:  http://127.0.0.1:" "$msg"
negar   "no empuja la rama"                    hay_remota "$d" me-lo-he-pensado
# Sin haber empujado no hay PR, y ahí el hueco se dice con palabras en vez de
# dejar un «PR:» pelado al final de un mensaje que por lo demás sale bien.
afirmar "y dice que todavía no hay PR"         contiene "PR:      todavía no hay ninguna" "$msg"

# El árbol sucio para una PR, no una pila. Y en el flujo nuevo llega sucio casi
# siempre: entre el «no» y el «bueno, va» ha corrido el revisor, y `--fix` deja
# sus arreglos en el árbol de trabajo. Frenar aquí era negarle al usuario lo
# único que acababa de pedir, y ofrecerle un `--forzar` que dice tirar cambios
# que este guión no tira.
d=$(montar); con_workflow "$d"; con_compose "$d"
ruta=$(abrir "$d" sucia-pero-solo-pila 2>/dev/null); trabajar "$ruta" uno
printf 'lo que acaba de dejar el revisor\n' > "$ruta/a-medias.txt"
RESPONDE=1
afirmar "--solo-pila levanta con el árbol sucio" \
        probar_rama verde "$d" sucia-pero-solo-pila --solo-pila
RESPONDE=0
afirmar "y la levanta de verdad"               contiene "up -d --build" "$(registro "$d" docker.log)"
afirmar "sin tocar lo que había sin guardar"   test -f "$ruta/a-medias.txt"

# ════════════════════════════════════════════════════════════════════════════
caso "probar-rama.sh: verificar.sh manda, y manda antes que el CI"
# Descubrir en el CI lo que se ve en local es pagar doce minutos por un lint.
d=$(montar); con_workflow "$d"; con_verificar "$d" 1
ruta=$(abrir "$d" verificar-rojo 2>/dev/null); trabajar "$ruta" uno
revisar "$d" verificar-rojo >/dev/null 2>&1
negar   "con verificar.sh en rojo, no sigue"     probar_rama verde "$d" verificar-rojo
negar   "y no ha abierto ninguna PR"             test -f "$d/estado/pr-verificar-rojo"
negar   "ni ha empujado la rama"                 hay_remota "$d" verificar-rojo

d=$(montar); con_workflow "$d"; con_verificar "$d" 0
ruta=$(abrir "$d" verificar-verde 2>/dev/null); trabajar "$ruta" uno
revisar "$d" verificar-verde >/dev/null 2>&1
afirmar "con verificar.sh en verde, sigue"       probar_rama verde "$d" verificar-verde
afirmar "y la PR queda abierta"                  test -f "$d/estado/pr-verificar-verde"
afirmar "lo lanzó desde el worktree de la rama, no desde la raíz" \
        test "$(registro "$d" verificar.cwd)" = "$ruta"

d=$(montar); con_workflow "$d"; con_verificar "$d" 1
ruta=$(abrir "$d" saltarse-verificar 2>/dev/null); trabajar "$ruta" uno
revisar "$d" saltarse-verificar >/dev/null 2>&1
afirmar "--sin-verificar pasa por encima"        probar_rama verde "$d" saltarse-verificar --sin-verificar

# Un verificar.sh sin permiso de ejecución parece una red y no lo es: se para y
# se dice, en vez de seguir como si el repositorio no tuviera ninguno.
d=$(montar); con_workflow "$d"; con_verificar "$d" 0
ruta=$(abrir "$d" sin-permiso 2>/dev/null); trabajar "$ruta" uno
chmod -x "$ruta/verificar.sh"
git -C "$ruta" update-index --chmod=-x verificar.sh
git -C "$ruta" commit -qm "verificar.sh sin permiso de ejecución"
revisar "$d" sin-permiso >/dev/null 2>&1
negar   "un verificar.sh no ejecutable para la cosa"  probar_rama verde "$d" sin-permiso
negar   "y tampoco abre PR"                           test -f "$d/estado/pr-sin-permiso"

# Y un repositorio sin verificar.sh sigue funcionando: la mitad de los repos no
# tienen uno todavía, y un freno que rompe lo que ya iba no se instala.
d=$(montar); con_workflow "$d"
ruta=$(abrir "$d" sin-verificar-ninguno 2>/dev/null); trabajar "$ruta" uno
revisar "$d" sin-verificar-ninguno >/dev/null 2>&1
msg=$(probar_rama verde "$d" sin-verificar-ninguno 2>&1) && ok_pr=0 || ok_pr=1
afirmar "sin verificar.sh, sigue adelante"       test "$ok_pr" = 0
afirmar "pero lo dice"                           contiene "no hay verificar.sh" "$msg"

# Una rama sin un solo commit no llega a gastar el verificar.sh: se le dice antes
# de empezar. Con el verificar.sh en rojo a propósito, para que el mensaje que
# salga no pueda ser el suyo.
d=$(montar); con_workflow "$d"; con_verificar "$d" 1
abrir "$d" nada-que-empujar >/dev/null 2>&1
msg=$(probar_rama verde "$d" nada-que-empujar 2>&1) || true
afirmar "una rama vacía se para por vacía…"      contiene "ningún commit" "$msg"
negar   "…y no llega a lanzar el verificar.sh"   test -f "$d/estado/verificar.cwd"

# Y sin pila que levantar, el mensaje final no puede cantar un verde que nadie ha
# mirado. Pasó de verdad el 14-08-2026: `--sin-ci` sobre una PR con el CI en rojo
# despidiéndose con «La PR está verde y esperando».
caso "probar-rama.sh: --sin-ci no puede decir «verde»"
d=$(montar); con_workflow "$d"; ruta=$(abrir "$d" verde-sin-mirar 2>/dev/null); trabajar "$ruta" uno
revisar "$d" verde-sin-mirar >/dev/null 2>&1
msg=$(probar_rama rojo "$d" verde-sin-mirar --sin-ci 2>&1)
negar   "con --sin-ci no dice que esté verde"    contiene "está verde" "$msg"
afirmar "y dice que el CI está sin mirar"        contiene "sin mirar" "$msg"

d=$(montar); con_workflow "$d"; ruta=$(abrir "$d" verde-mirado 2>/dev/null); trabajar "$ruta" uno
revisar "$d" verde-mirado >/dev/null 2>&1
msg=$(probar_rama verde "$d" verde-mirado 2>&1)
afirmar "habiendo esperado al CI, sí lo dice"    contiene "está verde" "$msg"

caso "probar-rama.sh: sin revisar no hay PR"
# La PR tiene que nacer con lo que el revisor haya dicho ya dentro.
d=$(montar); con_workflow "$d"; ruta=$(abrir "$d" sin-revisar 2>/dev/null); trabajar "$ruta" uno
msg=$(probar_rama verde "$d" sin-revisar 2>&1) && paso_sin_marca=0 || paso_sin_marca=1
afirmar "sin marca de revisión, se para"         test "$paso_sin_marca" = 1
afirmar "y dice cómo salir de ahí"               contiene "marcar-revisado.sh" "$msg"
negar   "no ha abierto ninguna PR"               test -f "$d/estado/pr-sin-revisar"
negar   "ni ha empujado la rama"                 hay_remota "$d" sin-revisar
afirmar "--sin-revisar pasa por encima"          probar_rama verde "$d" sin-revisar --sin-revisar
afirmar "y entonces sí hay PR"                   test -f "$d/estado/pr-sin-revisar"

# El caso que hace que la marca valga algo: se revisa, y después se commitea una
# cosa más. Esa cosa más no la ha visto nadie.
caso "probar-rama.sh: la marca caduca con el commit siguiente"
d=$(montar); con_workflow "$d"; ruta=$(abrir "$d" marca-caducada 2>/dev/null); trabajar "$ruta" uno
revisar "$d" marca-caducada >/dev/null 2>&1
trabajar "$ruta" dos
negar   "un commit posterior a la revisión vuelve a frenar" \
        probar_rama verde "$d" marca-caducada
negar   "y sigue sin haber PR"                   test -f "$d/estado/pr-marca-caducada"
revisar "$d" marca-caducada >/dev/null 2>&1
afirmar "al volver a revisar, pasa"              probar_rama verde "$d" marca-caducada

caso "marcar-revisado.sh: qué escribe y qué se niega a escribir"
d=$(montar)
negar "se niega sobre main"                      revisar "$d" main
negar "se niega con una rama que no existe"      revisar "$d" no-existe
ruta=$(abrir "$d" marcable 2>/dev/null); trabajar "$ruta" uno
afirmar "sobre una rama con worktree, marca"     revisar "$d" marcable
# La marca lleva dos cosas desde el 17-08-2026: el SHA, que la hace caducar con
# el commit siguiente, y el nivel con el que se revisó, que es lo que
# `probar-rama.sh` compara con el tramo del diff.
afirmar "y lo que escribe es el HEAD de la rama y el nivel" \
        test "$(cat "$d/repo/.git/worktrees/wtmarcable/revisado" 2>/dev/null)" \
           = "$(git -C "$ruta" rev-parse HEAD) max"
negar   "la marca no se cuela en el repositorio" \
        test -n "$(git -C "$ruta" status --porcelain)"

caso "probar-rama.sh: los datos de la rama son una COPIA de los tuyos"
# Lo único de todo esto que puede destruir datos. Hasta el 13-08-2026 el docker
# falso decía que no existía ningún volumen, así que este camino —el que copia—
# no lo recorría ni la matriz.
d=$(montar); con_workflow "$d"; con_compose "$d"
ruta=$(abrir "$d" clona-el-volumen 2>/dev/null); trabajar "$ruta" uno
revisar "$d" clona-el-volumen >/dev/null 2>&1
VOLUMENES="repo_postgres-data"; RESPONDE=1
msg=$(probar_rama verde "$d" clona-el-volumen --con-pila 2>&1) && clon=0 || clon=1
afirmar "con la pila arriba, sale bien"     test "$clon" = 0
log=$(registro "$d" docker.log)
afirmar "crea el volumen de LA RAMA" \
        contiene "volume create repo-clona-el-volumen_postgres-data" "$log"
# El mensaje contaba SIEMPRE que los datos eran «copia de <volumen>», también
# cuando no había copiado ninguno. Aquí sí ha copiado, y es donde toca decirlo.
afirmar "y lo cuenta: los datos son una copia" \
        contiene "datos:   copia de repo_postgres-data; tu pila de siempre no se ha tocado" "$msg"
afirmar "y copia dentro los datos de tu volumen de siempre" \
        contiene "run --rm -v repo_postgres-data:/de -v repo-clona-el-volumen_postgres-data:/a" "$log"
afirmar "tu volumen nunca se escribe: solo se lee" \
        no_contiene "volume create repo_postgres-data" "$log"
VOLUMENES=""; RESPONDE=0

d=$(montar); con_workflow "$d"; con_compose "$d"
ruta=$(abrir "$d" ya-tenia-datos 2>/dev/null); trabajar "$ruta" uno
revisar "$d" ya-tenia-datos >/dev/null 2>&1
VOLUMENES="repo_postgres-data,repo-ya-tenia-datos_postgres-data"; RESPONDE=1
afirmar "si la rama ya tenía datos, sale bien"  probar_rama verde "$d" ya-tenia-datos --con-pila
log=$(registro "$d" docker.log)
afirmar "…y no los pisa: ni crea"           no_contiene "volume create" "$log"
afirmar "…ni vuelve a copiar"               no_contiene "run --rm" "$log"
VOLUMENES=""; RESPONDE=0

caso "probar-rama.sh: cuando la pila responde, avisa y da la URL"
# El único caso que se podía escribir sin falsear curl era el de que NO
# respondiera, así que el final feliz —la URL, el aviso del sistema, el mensaje
# con las instrucciones— no lo comprobaba nadie.
d=$(montar); con_workflow "$d"; con_compose "$d"
ruta=$(abrir "$d" pila-viva 2>/dev/null); trabajar "$ruta" uno
revisar "$d" pila-viva >/dev/null 2>&1
RESPONDE=1
msg=$(probar_rama verde "$d" pila-viva --con-pila 2>&1) && vivo=0 || vivo=1
afirmar "sale bien"                          test "$vivo" = 0
afirmar "dice dónde probarlo"                contiene "Lista para probar:  http://127.0.0.1:" "$msg"
# Aquí no hay ningún volumen que clonar, y el mensaje lo dice en vez de prometer
# una copia que no existe: la frase «copia de <volumen>» salía igual con la base
# vacía, que es justo cuando importa saberlo antes de mirar la app y no después.
afirmar "y no promete una copia que no hizo" contiene "datos:   vacíos" "$msg"
afirmar "y remite a cerrar-rama.sh, no cierra él" contiene "cerrar-rama.sh pila-viva" "$msg"
avisos=$(registro "$d" avisos.log)
afirmar "avisa por el sistema con la URL"    contiene "Lista para probar en http://127.0.0.1:" "$avisos"
afirmar "y el aviso nombra repo y rama"      contiene "repo · pila-viva" "$avisos"
afirmar "la rama sigue sin fusionar"         hay_rama "$d" pila-viva
RESPONDE=0

caso "probar-rama.sh: el .env de la raíz se enlaza, no se copia"
# No está versionado —y no debe estarlo—, así que un worktree recién abierto no
# lo tiene y la pila arrancaría sin ninguna clave. Una copia se queda vieja el
# día que cambie el de la raíz.
d=$(montar); con_workflow "$d"; con_compose "$d"
printf 'CLAVE=secreta\n' > "$d/repo/.env"
ruta=$(abrir "$d" con-env 2>/dev/null); trabajar "$ruta" uno
revisar "$d" con-env >/dev/null 2>&1
RESPONDE=1
probar_rama verde "$d" con-env --con-pila >/dev/null 2>&1
afirmar "el worktree acaba teniendo su .env"  test -L "$ruta/.env"
afirmar "y es un enlace al de la raíz"        test "$(readlink "$ruta/.env")" = "$d/repo/.env"
RESPONDE=0

caso "probar-rama.sh: el puerto sale del nombre de la rama"
d=$(montar); con_workflow "$d"; con_compose "$d"
ruta=$(abrir "$d" puerto-propio 2>/dev/null); trabajar "$ruta" uno
revisar "$d" puerto-propio >/dev/null 2>&1
RESPONDE=1
probar_rama verde "$d" puerto-propio --con-pila >/dev/null 2>&1
afirmar "usa el puerto que le toca a esta rama" \
        contiene "WEB_BIND_PORT=$(puerto_esperado puerto-propio) " "$(registro "$d" docker.log)"
RESPONDE=0

d=$(montar); con_workflow "$d"; con_compose "$d"
ruta=$(abrir "$d" puerto-pillado 2>/dev/null); trabajar "$ruta" uno
revisar "$d" puerto-pillado >/dev/null 2>&1
RESPONDE=1; PUERTOS_PILLADOS=3
probar_rama verde "$d" puerto-pillado --con-pila >/dev/null 2>&1
afirmar "si está ocupado, se corre al siguiente libre" \
        contiene "WEB_BIND_PORT=$(( $(puerto_esperado puerto-pillado) + 3 )) " "$(registro "$d" docker.log)"
RESPONDE=0; PUERTOS_PILLADOS=0

caso "probar-rama.sh: --sin-ci y el árbol sucio"
d=$(montar); con_workflow "$d"; con_compose "$d"
ruta=$(abrir "$d" sin-esperar 2>/dev/null); trabajar "$ruta" uno
revisar "$d" sin-esperar >/dev/null 2>&1
RESPONDE=1
afirmar "--sin-ci --con-pila levanta con el CI en rojo" \
        probar_rama rojo "$d" sin-esperar --sin-ci --con-pila
afirmar "…y la levanta de verdad"           contiene "up -d --build" "$(registro "$d" docker.log)"
RESPONDE=0

# Sin pila, `--sin-ci` sigue siendo lo que dice: empuja, abre la PR y no espera.
d=$(montar); con_workflow "$d"; con_compose "$d"
ruta=$(abrir "$d" sin-esperar-ni-pila 2>/dev/null); trabajar "$ruta" uno
revisar "$d" sin-esperar-ni-pila >/dev/null 2>&1
msg=$(probar_rama rojo "$d" sin-esperar-ni-pila --sin-ci 2>&1) && snp=0 || snp=1
afirmar "--sin-ci a secas abre la PR y para" test "$snp" = 0
afirmar "y no levanta nada"                  test -z "$(registro "$d" docker.log)"
afirmar "pero sí ha empujado"                hay_remota "$d" sin-esperar-ni-pila
# «Verde» solo si alguien ha mirado: con --sin-ci nadie ha preguntado por un
# solo check, y este mensaje llegó a decirlo de verdad sobre una PR en rojo.
negar   "con --sin-ci no dice que esté verde" contiene "está verde" "$msg"
afirmar "y dice que el CI está sin mirar"     contiene "sin mirar" "$msg"

caso "probar-rama.sh: lo que se contradice se rechaza, y se explica"
# Todo esto muere en el bucle de argumentos, antes de mirar el repositorio, así
# que comparten el montaje del caso de arriba: montar uno nuevo son veinticinco
# procesos de git para probar un `case` de bash.
#
# Y se comprueba el MENSAJE, no solo que salga con error: mientras solo se
# miraba el código de salida, quitar entero el `-*) morir "Opción desconocida"`
# dejaba la matriz en verde —el argumento caía en «Sobra un argumento»—, o sea
# que el caso pasaba sin que el guión dijera nada de lo que dice el commit.
msg=$(probar_rama verde "$d" bandera-vieja --sin-pila 2>&1) && vieja=0 || vieja=1
afirmar "--sin-pila ya no existe"           test "$vieja" = 1
afirmar "y dice que no la conoce"           contiene "Opción desconocida: --sin-pila" "$msg"

msg=$(probar_rama verde "$d" combo --con-pila --solo-pila 2>&1) && combo=0 || combo=1
afirmar "--con-pila con --solo-pila se rechaza"  test "$combo" = 1
afirmar "y explica en qué se diferencian"        contiene "piden cosas distintas" "$msg"

msg=$(probar_rama verde "$d" combo2 --solo-pila --sin-ci 2>&1) && combo2=0 || combo2=1
afirmar "--solo-pila con --sin-ci se rechaza"    test "$combo2" = 1
afirmar "y dice que sobra"                       contiene "sobra: --sin-ci" "$msg"

# Y lo mismo con los frenos de antes del push, que `--solo-pila` tampoco toca.
msg=$(probar_rama verde "$d" combo3 --solo-pila --sin-revisar 2>&1) && combo3=0 || combo3=1
afirmar "--solo-pila con --sin-revisar se rechaza" test "$combo3" = 1
afirmar "y dice cuál sobra"                        contiene "sobra: --sin-revisar" "$msg"

d=$(montar); con_workflow "$d"
ruta=$(abrir "$d" sucia-al-probar 2>/dev/null); trabajar "$ruta" uno
revisar "$d" sucia-al-probar >/dev/null 2>&1
printf 'a medias\n' > "$ruta/a-medias.txt"
negar   "para con cambios sin guardar"      probar_rama verde "$d" sucia-al-probar
afirmar "--forzar sigue adelante"           probar_rama verde "$d" sucia-al-probar --forzar

caso "cerrar-rama.sh: producción"
d=$(montar); con_workflow "$d"; con_contrato_de_despliegue "$d"
ruta=$(abrir "$d" con-despliegue 2>/dev/null); trabajar "$ruta" uno
afirmar "cierra"                            cerrar verde "$d" con-despliegue
afirmar "y despliega, nombrando el repo"    contiene "repo" "$(registro "$d" despliegues.log)"

d=$(montar); con_workflow "$d"; con_contrato_de_despliegue "$d"
ruta=$(abrir "$d" sin-desplegar 2>/dev/null); trabajar "$ruta" uno
afirmar "con --sin-desplegar cierra igual"  cerrar verde "$d" sin-desplegar --sin-desplegar
afirmar "y NO toca producción"              test -z "$(registro "$d" despliegues.log)"

d=$(montar); con_workflow "$d"; ruta=$(abrir "$d" sin-contrato 2>/dev/null); trabajar "$ruta" uno
afirmar "sin contrato de despliegue, cierra" cerrar verde "$d" sin-contrato
afirmar "y no intenta desplegar"             test -z "$(registro "$d" despliegues.log)"

# Un despliegue roto no puede pasar desapercibido: la PR YA está fusionada y
# producción se ha quedado con lo de antes. Es el único estado a medias de todo
# esto, y hasta el 13-08-2026 el desplegar.sh falso siempre salía bien.
d=$(montar); con_workflow "$d"; con_contrato_de_despliegue "$d"
ruta=$(abrir "$d" despliegue-roto 2>/dev/null); trabajar "$ruta" uno
DESPLIEGUE_FALLA=1
msg=$(cerrar verde "$d" despliegue-roto 2>&1) && cerrado=0 || cerrado=1
DESPLIEGUE_FALLA=0
afirmar "con el despliegue roto, cierra igual"  test "$cerrado" = 0
afirmar "pero lo dice con todas las letras"     contiene "el despliegue ha fallado" "$msg"
afirmar "y avisa de que la PR sí está fusionada" contiene "La PR SÍ está fusionada" "$msg"
negar   "y limpia igual, que la fusión sí ocurrió" hay_worktree "$d" despliegue-roto

caso "cerrar-rama.sh: un verde viejo no vale"
# El CI prueba la FUSIÓN con main, no la rama. Si main se movió después, ese
# verde probó otra cosa — y GitHub la sigue marcando en verde igual.
d=$(montar); con_workflow "$d"; ruta=$(abrir "$d" verde-caducado 2>/dev/null); trabajar "$ruta" uno
afirmar "cierra"                        cerrar verde-viejo "$d" verde-caducado
afirmar "pero antes metió main en la rama y volvió a esperar" \
        contiene "update-branch" "$(registro "$d" gh.log)"

afirmar "y solo una vez, no en bucle" \
        test "$(grep -c update-branch "$d/estado/gh.log" 2>/dev/null || echo 0)" = 1

d=$(montar); con_workflow "$d"; ruta=$(abrir "$d" verde-al-dia 2>/dev/null); trabajar "$ruta" uno
afirmar "con el verde al día, cierra igual" cerrar verde "$d" verde-al-dia
afirmar "y NO toca la rama sin necesidad"   no_contiene "update-branch" "$(registro "$d" gh.log)"

# Y si main no para quieto, se pregunta otra vez en vez de fusionar a ciegas —
# pero no para siempre: con un tope, y diciéndolo. Hasta el 13-08-2026 esto era
# un solo tiro y la segunda espera se fusionaba sin volver a comprobar nada.
d=$(montar); con_workflow "$d"; ruta=$(abrir "$d" main-que-no-para 2>/dev/null); trabajar "$ruta" uno
msg=$(cerrar verde-terco "$d" main-que-no-para 2>&1) && terco=0 || terco=1
afirmar "si main no para quieto, NO fusiona"   test "$terco" = 1
afirmar "y dice por qué"                       contiene "se ha movido" "$msg"
afirmar "lo intentó más de una vez"            test "$(grep -c update-branch "$d/estado/gh.log")" -gt 1
afirmar "sin borrar el worktree"               hay_worktree "$d" main-que-no-para
afirmar "ni la rama"                           hay_rama "$d" main-que-no-para

caso "cerrar-rama.sh: se lleva la pila de la rama, con sus volúmenes"
d=$(montar); con_workflow "$d"; con_compose "$d"
ruta=$(abrir "$d" con-pila-que-cerrar 2>/dev/null); trabajar "$ruta" uno
PILAS="repo-con-pila-que-cerrar"
VOLUMENES="repo_postgres-data,repo-con-pila-que-cerrar_postgres-data"
msg=$(cerrar verde "$d" con-pila-que-cerrar 2>&1) && cerro=0 || cerro=1
PILAS=""
afirmar "cierra"                            test "$cerro" = 0
log=$(registro "$d" docker.log)
afirmar "tumbó la pila de la rama con --volumes" \
        contiene "compose -p repo-con-pila-que-cerrar down --volumes" "$log"
# Y el volumen tiene que DESAPARECER, no basta con haber llamado al `down`:
# `--volumes` solo se lleva lo que creó Compose, y este lo creó probar-rama.sh.
afirmar "y borra a mano el volumen de la copia, que el down no se lleva" \
        contiene "volume rm repo-con-pila-que-cerrar_postgres-data" "$log"
afirmar "TU volumen de siempre no se toca" \
        no_contiene "volume rm repo_postgres-data" "$log"
afirmar "y lo dice"                         contiene "sin pila" "$msg"
VOLUMENES=""

# El riesgo que introduce barrer por prefijo: dos ramas cuyo nombre empieza igual.
# El `_` del final del patrón es lo único que separa a una de la otra.
d=$(montar); con_workflow "$d"; con_compose "$d"
ruta=$(abrir "$d" cartera 2>/dev/null); trabajar "$ruta" uno
VOLUMENES="repo-cartera_postgres-data,repo-cartera-en-pestanas_postgres-data"
afirmar "cierra"                            cerrar verde "$d" cartera
log=$(registro "$d" docker.log)
afirmar "borra el suyo"                     contiene "volume rm repo-cartera_postgres-data" "$log"
afirmar "y NO el de la rama que empieza igual" \
        no_contiene "volume rm repo-cartera-en-pestanas_postgres-data" "$log"
VOLUMENES=""

# Y si el volumen no se deja borrar, se dice. Dar el borrado por hecho es el
# mismo fallo que este barrido arregla, un piso más abajo.
d=$(montar); con_workflow "$d"; con_compose "$d"
ruta=$(abrir "$d" volumen-atascado 2>/dev/null); trabajar "$ruta" uno
VOLUMENES="repo-volumen-atascado_postgres-data"; VOLUMEN_ATASCADO=1
msg=$(cerrar verde "$d" volumen-atascado 2>&1)
negar   "cierra igual: la fusión ya ocurrió"  hay_rama "$d" volumen-atascado
afirmar "pero avisa de que el volumen sigue ahí" \
        contiene "no he podido borrar el volumen repo-volumen-atascado_postgres-data" "$msg"
VOLUMENES=""; VOLUMEN_ATASCADO=0

# Y donde nunca hubo pila —lo normal desde que levantarla se pide— no se presume
# una limpieza que no ha ocurrido: `ps -aq` no ve contenedores, el barrido no ve
# volúmenes, y el mensaje final tiene que decirlo en vez de cantar «sin pila».
d=$(montar); con_workflow "$d"
ruta=$(abrir "$d" nunca-hubo-pila 2>/dev/null); trabajar "$ruta" uno
revisar "$d" nunca-hubo-pila >/dev/null 2>&1
msg=$(cerrar verde "$d" nunca-hubo-pila 2>&1) && nhp=0 || nhp=1
afirmar "sin pila que tumbar, cierra igual"  test "$nhp" = 0
afirmar "y no presume de haberla tumbado"    contiene "no había pila" "$msg"

# ════════════════════════════════════════════════════════════════════════════
caso "--solo-md: el atajo se salta los frenos, pero no se cree quien lo pide"
# Un cambio de solo markdown no ejecuta nada, así que ni verificar.sh ni revisión.
# Con el verificar.sh en ROJO y sin marca de revisión a propósito: si el atajo no
# funcionara, cualquiera de los dos pararía esto.
d=$(montar); con_workflow "$d"; con_verificar "$d" 1
ruta=$(abrir "$d" solo-docs 2>/dev/null); documentar "$ruta" uno
msg=$(probar_rama verde "$d" solo-docs --solo-md 2>&1) && atajo=0 || atajo=1
afirmar "con solo .md, ni verifica ni exige revisión"  test "$atajo" = 0
afirmar "y abre la PR"                                 test -f "$d/estado/pr-solo-docs"
negar   "sin llegar a lanzar el verificar.sh"          test -f "$d/estado/verificar.cwd"
afirmar "y lo dice"                                    contiene "solo markdown" "$msg"
# La línea que se copia al terminar tiene que llevar la bandera puesta: sin ella,
# el segundo tiempo vuelve a exigir justo lo que este atajo acaba de perdonar.
afirmar "la despedida ofrece el cierre con --solo-md" \
        contiene "cerrar-rama.sh solo-docs --solo-md" "$msg"

# Y el freno de verdad: un fichero que no sea .md y no hay atajo. Se comprueba
# ANTES de empujar, porque después ya da igual.
d=$(montar); con_workflow "$d"
ruta=$(abrir "$d" docs-con-codigo 2>/dev/null); documentar "$ruta" uno; trabajar "$ruta" dos
msg=$(probar_rama verde "$d" docs-con-codigo --solo-md 2>&1) && colado=0 || colado=1
afirmar "con un fichero que no es .md, se niega"  test "$colado" = 1
afirmar "y dice cuál es"                          contiene "nuevo.txt" "$msg"
negar   "no ha abierto ninguna PR"                test -f "$d/estado/pr-docs-con-codigo"
negar   "ni ha empujado la rama"                  hay_remota "$d" docs-con-codigo

# El renombrado es el agujero que `--no-renames` tapa: con detección de
# renombrados, `git diff --name-only` imprime SOLO el destino, así que
# `guion.sh → guion.md` se leería como markdown puro cuando lo que ha pasado es
# que ha desaparecido un guión.
d=$(montar); con_workflow "$d"
ruta=$(abrir "$d" renombra-un-guion 2>/dev/null)
printf '#!/bin/sh\necho hola\n' > "$ruta/guion.sh"
git -C "$ruta" add -A; git -C "$ruta" commit -qm "un guión"
git -C "$ruta" push -q origin "renombra-un-guion:main"
git -C "$ruta" mv guion.sh guion.md
git -C "$ruta" commit -qm "docs: lo convierto en markdown"
msg=$(probar_rama verde "$d" renombra-un-guion --solo-md 2>&1) && renombrado=0 || renombrado=1
afirmar "un .sh renombrado a .md no cuela como markdown" test "$renombrado" = 1
afirmar "y nombra el guión que ha desaparecido"          contiene "guion.sh" "$msg"

# Un acento en el nombre del fichero no lo saca de ser markdown. De serie git
# escapa y entrecomilla las rutas no ASCII —`"dise\303\261o.md"`—, y eso no acaba
# en `.md`: el atajo se caía diciendo que `diseño.md` no era documentación.
d=$(montar); con_workflow "$d"
ruta=$(abrir "$d" docs-con-acento 2>/dev/null)
printf 'con acentos\n' > "$ruta/diseño.md"
git -C "$ruta" add -A; git -C "$ruta" commit -qm "docs: con acento"
msg=$(probar_rama verde "$d" docs-con-acento --solo-md 2>&1) && acento=0 || acento=1
afirmar "un .md con acento en el nombre sigue siendo markdown" test "$acento" = 0
negar   "y no se le acusa de no serlo"  contiene "no son markdown" "$msg"

caso "--solo-md: «sin checks» deja de frenar, el rojo no"
# Es lo que provoca el paths-ignore de welzy con una PR de solo documentación:
# CI configurado que esa PR no dispara. Fuera del atajo eso para la cadena.
d=$(montar); con_workflow "$d"
ruta=$(abrir "$d" docs-sin-checks 2>/dev/null); documentar "$ruta" uno
msg=$(probar_rama sin-checks "$d" docs-sin-checks --solo-md 2>&1) && sin_checks=0 || sin_checks=1
afirmar "sin checks y con --solo-md, sigue"       test "$sin_checks" = 0
negar   "y no se despide como si esperara un verde" contiene "Sin un verde" "$msg"
negar   "ni canta un verde que nadie ha visto"      contiene "está verde" "$msg"

# Sin la bandera, la misma PR se para: el atajo tiene que ser lo que cambia.
d=$(montar); con_workflow "$d"
ruta=$(abrir "$d" docs-sin-atajo 2>/dev/null); documentar "$ruta" uno
revisar "$d" docs-sin-atajo >/dev/null 2>&1
msg=$(probar_rama sin-checks "$d" docs-sin-atajo 2>&1)
afirmar "sin --solo-md, «sin checks» sigue parando" contiene "Sin un verde" "$msg"

# El rojo frena igual: el atajo dice que la prosa no necesita examen propio, no
# que se pueda pasar por encima de uno ya suspendido. En dotfiles el CI de una
# PR de markdown corre entero, así que este caso es el de todos los días.
d=$(montar); con_workflow "$d"
ruta=$(abrir "$d" docs-en-rojo 2>/dev/null); documentar "$ruta" uno
negar "con el CI en rojo, --solo-md no perdona nada" \
      probar_rama rojo "$d" docs-en-rojo --solo-md

caso "--solo-md: lo que se contradice se rechaza también aquí"
d=$(montar)
msg=$(probar_rama verde "$d" md1 --solo-md --sin-verificar 2>&1) && md1=0 || md1=1
afirmar "--solo-md con --sin-verificar se rechaza"  test "$md1" = 1
afirmar "y dice cuál sobra"                         contiene "sobra: --sin-verificar" "$msg"

msg=$(probar_rama verde "$d" md2 --solo-md --sin-revisar 2>&1) && md2=0 || md2=1
afirmar "--solo-md con --sin-revisar se rechaza"    test "$md2" = 1
afirmar "y dice cuál sobra"                         contiene "sobra: --sin-revisar" "$msg"

msg=$(probar_rama verde "$d" md3 --solo-pila --solo-md 2>&1) && md3=0 || md3=1
afirmar "--solo-pila con --solo-md se rechaza"      test "$md3" = 1
afirmar "y dice cuál sobra"                         contiene "sobra: --solo-md" "$msg"

msg=$(cerrar verde "$d" md4 --solo-md --sin-desplegar 2>&1) && md4=0 || md4=1
afirmar "al cerrar, --solo-md con --sin-desplegar se rechaza" test "$md4" = 1
afirmar "y dice que ya no despliega"  contiene "ya no despliega" "$msg"

caso "cerrar-rama.sh --solo-md: fusiona sin checks y no despliega"
# Los dos motivos por los que una PR de documentación se quedaba abierta para
# siempre: el «sin checks» de welzy, y un despliegue que no cambiaría nada allí.
d=$(montar); con_workflow "$d"; con_contrato_de_despliegue "$d"
ruta=$(abrir "$d" cerrar-docs 2>/dev/null); documentar "$ruta" uno
msg=$(cerrar sin-checks "$d" cerrar-docs --solo-md 2>&1) && cerro_md=0 || cerro_md=1
afirmar "sin checks, sale bien"              test "$cerro_md" = 0
# Y «sale bien» no basta: el camino de rendirse ante un «sin checks» TAMBIÉN sale
# con 0 —«mírala tú y vuelve con --solo-limpiar»—, así que juzgar por el código
# de salida daba por fusionada una rama que seguía abierta.
negar   "y no se rinde ante la falta de checks" contiene "No la fusiono" "$msg"
afirmar "lo dice con todas las letras"       contiene "solo markdown" "$msg"
# Y no puede cantar un verde que no existe: aquí no ha habido un solo check.
negar   "sin llamar «verde» a lo que no lo es" contiene "verde: fusiono" "$msg"
negar   "no queda worktree"                  hay_worktree "$d" cerrar-docs
negar   "no queda rama local"                hay_rama "$d" cerrar-docs
afirmar "y main se ha quedado con el .md"    test -f "$d/repo/LEEME.md"
afirmar "sin tocar producción"               test -z "$(registro "$d" despliegues.log)"

# El mismo freno que al probar, ahora del lado del borrado: si el diff no es solo
# markdown, no fusiona ni limpia nada.
d=$(montar); con_workflow "$d"
ruta=$(abrir "$d" cerrar-con-codigo 2>/dev/null); documentar "$ruta" uno; trabajar "$ruta" dos
negar   "con código dentro, se niega a cerrar"  cerrar sin-checks "$d" cerrar-con-codigo --solo-md
afirmar "y no ha borrado el worktree"           hay_worktree "$d" cerrar-con-codigo
afirmar "ni la rama"                            hay_rama "$d" cerrar-con-codigo

# Y el rojo sigue mandando también al cerrar.
d=$(montar); con_workflow "$d"
ruta=$(abrir "$d" cerrar-docs-rojo 2>/dev/null); documentar "$ruta" uno
negar   "con el CI en rojo, no fusiona"   cerrar rojo "$d" cerrar-docs-rojo --solo-md
afirmar "y no ha borrado la rama"         hay_rama "$d" cerrar-docs-rojo

caso "clasificar-diff.sh: los cuatro tramos"
# La escalera entera, cada tramo con el cambio que lo provoca. Si esto se rompe,
# la cadena revisa de menos —o revisa a `max` lo que no lo necesita, que es de
# donde venía todo esto.
d=$(montar)
ruta=$(abrir "$d" tramo-md 2>/dev/null); documentar "$ruta" uno
afirmar "solo .md no pide revisión"  contiene "solo-md ninguno" "$(clasificar "$d" tramo-md 2>/dev/null)"

d=$(montar)
ruta=$(abrir "$d" tramo-trivial 2>/dev/null); retocar "$ruta" dos
afirmar "un retoque de una línea es trivial"  contiene "trivial low" "$(clasificar "$d" tramo-trivial 2>/dev/null)"

# Un fichero NUEVO saca del tramo trivial aunque sean tres líneas: lo que no ha
# leído nadie no es un retoque, es código nuevo.
d=$(montar)
ruta=$(abrir "$d" tramo-normal 2>/dev/null); trabajar "$ruta" uno
afirmar "un fichero nuevo ya no es trivial"  contiene "normal high" "$(clasificar "$d" tramo-normal 2>/dev/null)"

d=$(montar)
ruta=$(abrir "$d" tramo-delicado 2>/dev/null); tocar_delicado "$ruta"
salida=$(clasificar "$d" tramo-delicado 2>&1)
afirmar "una ruta delicada pide max"   contiene "sensible max" "$salida"
afirmar "y dice cuál y por qué patrón" contiene "hooks/freno.sh" "$salida"

# Lo que decide qué se expone y dónde también es delicado *(18-08-2026)*. Dos
# líneas de un compose cambian el puerto publicado, y eso —en Welzy— es el
# reparto de confianza 8080/8081 entero: por tamaño saldría `trivial low`, que
# es el tramo al que no lo lee nadie.
d=$(montar)
ruta=$(abrir "$d" tramo-compose 2>/dev/null)
printf 'services:\n  web:\n    ports: ["8080:8080"]\n' > "$ruta/docker-compose.yml"
git -C "$ruta" add -A; git -C "$ruta" commit -qm "feat: publica el puerto"
salida=$(clasificar "$d" tramo-compose 2>&1)
afirmar "un compose pide max aunque sean tres líneas" contiene "sensible max" "$salida"
afirmar "y dice qué fichero lo ha subido"             contiene "docker-compose.yml" "$salida"

# El tamaño, con el umbral bajado para no escribir seiscientas líneas de mentira.
d=$(montar)
ruta=$(abrir "$d" tramo-enorme 2>/dev/null)
i=0; while [ "$i" -lt 12 ]; do printf 'linea %s\n' "$i" >> "$ruta/f"; i=$((i + 1)); done
git -C "$ruta" add -A; git -C "$ruta" commit -qm "feat: un montón"
afirmar "pasado el umbral de tamaño, max" \
        contiene "sensible max" "$(LIMITE_GRANDE=5 clasificar "$d" tramo-enorme 2>/dev/null)"
# Y el mismo diff, con el umbral en su sitio, NO es sensible: si lo fuera, la
# aserción de arriba no probaría el umbral, probaría que todo sale max.
negar   "con el umbral normal, ese mismo diff no es sensible" \
        contiene "sensible" "$(clasificar "$d" tramo-enorme 2>/dev/null)"

# `.claude/rutas-sensibles` manda sobre la lista de serie, y se lee la de la
# RAÍZ: una rama no puede rebajarse el listón borrando de la lista lo que va a
# tocar. Aquí la raíz declara `f` como delicado, y tocar `f` pasa a pedir max.
d=$(montar)
mkdir -p "$d/repo/.claude"
printf '# lo nuestro\nf\n' > "$d/repo/.claude/rutas-sensibles"
git -C "$d/repo" add -A; git -C "$d/repo" commit -qm "rutas sensibles"
git -C "$d/repo" push -q origin main
ruta=$(abrir "$d" tramo-configurado 2>/dev/null); retocar "$ruta" dos
afirmar "la lista del repositorio manda" \
        contiene "sensible max" "$(clasificar "$d" tramo-configurado 2>/dev/null)"

caso "la marca de revisión tiene que llegar al nivel que pide el diff"
# El freno que convierte la escalera en algo más que una sugerencia. Sin él, el
# tramo barato se elegiría siempre: quien pide el atajo es quien acaba de
# decidir, él solo, que lo suyo es sencillo.
d=$(montar); con_workflow "$d"
ruta=$(abrir "$d" nivel-corto 2>/dev/null); tocar_delicado "$ruta"
revisar "$d" nivel-corto low >/dev/null 2>&1
msg=$(probar_rama verde "$d" nivel-corto 2>&1) && paso_corto=0 || paso_corto=1
afirmar "revisada a low, una rama que pide max no pasa"  test "$paso_corto" = 1
afirmar "y dice qué nivel pide"                          contiene "pide una revisión a 'max'" "$msg"
afirmar "y con qué orden se arregla"                     contiene "/code-review nivel-corto max --fix" "$msg"
negar   "no ha empujado nada"                            hay_remota "$d" nivel-corto

# Y con el nivel que toca, pasa.
revisar "$d" nivel-corto max >/dev/null 2>&1
afirmar "revisada a max, la misma rama pasa"  probar_rama verde "$d" nivel-corto

# Sobrarse por arriba no es un fallo: revisar de más nunca frena.
d=$(montar); con_workflow "$d"
ruta=$(abrir "$d" nivel-largo 2>/dev/null); retocar "$ruta" dos
revisar "$d" nivel-largo high >/dev/null 2>&1
afirmar "un nivel más alto del que pide, pasa"  probar_rama verde "$d" nivel-largo

# Una marca de las de antes —solo el SHA, sin nivel— no vale como revisión: lo
# que nadie escribió no se da por bueno.
d=$(montar); con_workflow "$d"
ruta=$(abrir "$d" marca-vieja 2>/dev/null); retocar "$ruta" dos
printf '%s' "$(git -C "$ruta" rev-parse HEAD)" > "$(git -C "$ruta" rev-parse --absolute-git-dir)/revisado"
msg=$(probar_rama verde "$d" marca-vieja 2>&1) && paso_vieja=0 || paso_vieja=1
afirmar "una marca sin nivel no pasa"  test "$paso_vieja" = 1
afirmar "y se explica por qué"         contiene "sin nivel" "$msg"

caso "marcar-revisado.sh: el nivel se escribe, no se supone"
d=$(montar)
ruta=$(abrir "$d" sin-nivel 2>/dev/null); retocar "$ruta" dos
msg=$( ( cd "$d/repo" && "$bin/marcar-revisado.sh" sin-nivel ) 2>&1 ) && marco=0 || marco=1
afirmar "sin --nivel no marca nada"        test "$marco" = 1
afirmar "y manda mirar el tramo"           contiene "clasificar-diff.sh" "$msg"
msg=$( ( cd "$d/repo" && "$bin/marcar-revisado.sh" sin-nivel --nivel altísimo ) 2>&1 ) && inventado=0 || inventado=1
afirmar "un nivel inventado tampoco"       test "$inventado" = 1

caso "probar-rama.sh: la cadena partida en dos"
# El primer tiempo empuja y abre la PR sin esperar al CI; el segundo solo espera.
# Partirla es lo que permite preguntar por la pila con el push recién hecho, en
# vez de sondear doce minutos la salida de un guión.
d=$(montar); con_workflow "$d"
ruta=$(abrir "$d" cadena-partida 2>/dev/null); retocar "$ruta" dos
revisar "$d" cadena-partida low >/dev/null 2>&1
msg=$(probar_rama verde "$d" cadena-partida --sin-ci 2>&1)
afirmar "el primer tiempo empuja y abre la PR"  test -f "$d/estado/pr-cadena-partida"
afirmar "sin decir que hay verde"               contiene "sin mirar" "$msg"
afirmar "y ofrece el segundo tiempo"            contiene "--esperar-ci" "$msg"

msg=$(probar_rama verde "$d" cadena-partida --esperar-ci 2>&1)
afirmar "el segundo tiempo mira el CI"          contiene "espero al CI" "$msg"
afirmar "y da su veredicto"                     contiene "Su CI está verde" "$msg"
negar   "sin volver a lanzar verificar.sh"      test -f "$d/estado/verificar.cwd"

# Sin PR no hay nada que esperar, y se dice con el comando que la abre.
d=$(montar); con_workflow "$d"
ruta=$(abrir "$d" sin-pr-que-mirar 2>/dev/null); retocar "$ruta" dos
msg=$(probar_rama verde "$d" sin-pr-que-mirar --esperar-ci 2>&1) && esperado=0 || esperado=1
afirmar "sin PR, se niega"          test "$esperado" = 1
afirmar "y dice cómo abrirla"       contiene -- "--sin-ci" "$msg"

# Lo que se contradice se rechaza, igual que con --solo-pila.
d=$(montar); con_workflow "$d"
ruta=$(abrir "$d" esperar-contradictorio 2>/dev/null); retocar "$ruta" dos
negar "--esperar-ci con --con-pila se rechaza"  probar_rama verde "$d" esperar-contradictorio --esperar-ci --con-pila
negar "--esperar-ci con --sin-ci se rechaza"    probar_rama verde "$d" esperar-contradictorio --esperar-ci --sin-ci

caso "probar-rama.sh: el freno de las rondas contra un rojo que no se va"
# Vivía en la cabeza del modelo —«apunta los nombres de cada ronda y compáralos
# contra todas las anteriores»—, que es lo que un modelo hace mal y un fichero
# hace bien. Un check que ya falló y vuelve a fallar para la cadena: un bucle
# contra un flaky quema rondas de CI y revisiones de Opus sin mover nada.
d=$(montar); con_workflow "$d"
ruta=$(abrir "$d" rojo-terco 2>/dev/null); retocar "$ruta" dos
revisar "$d" rojo-terco low >/dev/null 2>&1
msg=$(probar_rama rojo "$d" rojo-terco 2>&1) && r1=0 || r1=$?
afirmar "el primer rojo se puede arreglar"   test "$r1" = 1
afirmar "y lo dice contando la ronda"        contiene "Ronda 1 en rojo" "$msg"

# Otro commit, y el MISMO check vuelve a fallar.
retocar "$ruta" tres
revisar "$d" rojo-terco low >/dev/null 2>&1
msg=$(probar_rama rojo "$d" rojo-terco 2>&1) && r2=0 || r2=$?
afirmar "el mismo check en rojo dos veces para la cadena"  test "$r2" = 3
afirmar "y dice cuál se repite"                            contiene "'CI' ya había fallado" "$msg"

# Con checks DISTINTOS no se para por repetición, sino por número de rondas: es
# el caso que `--fail-fast` provoca solo, rotando el nombre del que falla.
d=$(montar); con_workflow "$d"
ruta=$(abrir "$d" rojo-rotativo 2>/dev/null); retocar "$ruta" dos
revisar "$d" rojo-rotativo low >/dev/null 2>&1
probar_rama rojo "$d" rojo-rotativo >/dev/null 2>&1 || true
retocar "$ruta" tres
revisar "$d" rojo-rotativo low >/dev/null 2>&1
msg=$(RONDAS_MAXIMAS=2 probar_rama rojo-otro "$d" rojo-rotativo 2>&1) && rot=0 || rot=$?
afirmar "gastadas las rondas, para aunque el check sea otro"  test "$rot" = 2 -o "$rot" = 3
afirmar "y dice que se han acabado"                           contiene "arreglo automático" "$msg"

# Dos checks DISTINTOS que comparten una palabra no son el mismo check. Los
# nombres de GitHub llevan espacios —`build (ubuntu-latest)`— y mientras se
# guardaban pegados con espacios, el segundo rojo se leía como una repetición
# del primero: la cadena se plantaba en la primera ronda, que es justo lo
# contrario de lo que este freno tiene que hacer.
d=$(montar); con_workflow "$d"
ruta=$(abrir "$d" rojo-nombres-largos 2>/dev/null); retocar "$ruta" dos
revisar "$d" rojo-nombres-largos low >/dev/null 2>&1
probar_rama rojo-largo1 "$d" rojo-nombres-largos >/dev/null 2>&1 || true
retocar "$ruta" tres
revisar "$d" rojo-nombres-largos low >/dev/null 2>&1
msg=$(probar_rama rojo-largo2 "$d" rojo-nombres-largos 2>&1) && largos=0 || largos=$?
afirmar "dos checks que comparten palabra no son el mismo"  test "$largos" = 1
negar   "y no se acusa a ninguno de repetirse"              contiene "ya había fallado" "$msg"

# Un CI que solo sigue corriendo no es una ronda en rojo. `esperar_ci` devuelve
# el mismo 1 para las dos cosas, y contarlo gastaría el arreglo automático sin
# que hubiera fallado nada.
d=$(montar); con_workflow "$d"
ruta=$(abrir "$d" ci-a-medias 2>/dev/null); retocar "$ruta" dos
revisar "$d" ci-a-medias low >/dev/null 2>&1
msg=$(probar_rama corriendo "$d" ci-a-medias 2>&1) || true
negar "un CI a medias no gasta ronda" \
      test -f "$(git -C "$d/repo/.claude/worktrees/wtci-a-medias" rev-parse --absolute-git-dir)/rondas-ci"
# Y tampoco la cuenta en voz alta. Sin esta segunda aserción, la prueba de
# arriba pasa igual con el freno quitado —al no haber ningún check con nombre no
# se escribe ninguna línea de todas formas—, o sea que no probaba el freno.
negar "ni la anuncia"  contiene "Ronda" "$msg"

# Y el verde cierra la cuenta: las rondas de un rojo ya arreglado no pueden
# sumarse a las del próximo.
d=$(montar); con_workflow "$d"
ruta=$(abrir "$d" rojo-y-luego-verde 2>/dev/null); retocar "$ruta" dos
revisar "$d" rojo-y-luego-verde low >/dev/null 2>&1
probar_rama rojo "$d" rojo-y-luego-verde >/dev/null 2>&1 || true
probar_rama verde "$d" rojo-y-luego-verde >/dev/null 2>&1 || true
negar "el verde borra la cuenta de rondas" \
      test -f "$(git -C "$d/repo/.claude/worktrees/wtrojo-y-luego-verde" rev-parse --absolute-git-dir)/rondas-ci"

echo
if [ "$fallos" -eq 0 ]; then
  echo "TODO BIEN: 0 fallos"
else
  echo "$fallos FALLOS"
  exit 1
fi
