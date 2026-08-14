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
    case " $* " in
      *" --jq .url "*) echo "https://example.test/pr/1"; exit 0 ;;
    esac ;;
esac

case $accion in
  view)
    rama=$1
    printf '%s' "$rama" > "$ESTADO/rama"
    [ -f "$ESTADO/pr-$rama" ] || exit 1
    case " $* " in
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
esac
case "$*" in
  *"ps -aq") echo "contenedor-de-mentira" ;;  # para que el `down` llegue a correr
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
montar() {
  local d
  d=$(mktemp -d "$TMP/caso.XXXXXX")
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
  # Resuelta: en macOS /var es un enlace a /private/var, y los scripts imprimen
  # la ruta que da git, que ya viene resuelta. Comparar sin esto es comparar
  # dos formas de escribir el mismo sitio.
  ( cd "$d" && pwd -P | tr -d '\n' )
}

# Commit de mentira en la rama, para que haya algo que fusionar.
trabajar() { # trabajar <ruta-del-worktree> <texto>
  printf '%s\n' "$2" > "$1/nuevo.txt"
  git -C "$1" add -A
  git -C "$1" commit -qm "feat: $2"
}

abrir() { ( cd "$1/repo" && ESTADO="$1/estado" ESPEJO="$1/espejo" "$bin/abrir-rama.sh" "$2" ); }

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

# Lo que deja la skill `probar` después de pasar el revisor por el diff.
revisar() { ( cd "$1/repo" && "$bin/marcar-revisado.sh" "$2" ); }

registro() { cat "$1/estado/$2" 2>/dev/null || true; }

contiene()    { printf '%s' "$2" | grep -qF -- "$1"; }
no_contiene() { ! printf '%s' "$2" | grep -qF -- "$1"; }

hay_worktree() { [ -d "$1/repo/.claude/worktrees/wt$2" ]; }
hay_rama()     { git -C "$1/repo" show-ref --quiet --verify "refs/heads/$2"; }
hay_remota()   { git -C "$1/repo" ls-remote --exit-code --heads origin "$2" >/dev/null 2>&1; }

# ════════════════════════════════════════════════════════════════════════════
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

caso "probar-rama.sh: sin verde no levanta nada"
d=$(montar); con_workflow "$d"; con_compose "$d"
ruta=$(abrir "$d" rojo-no-levanta 2>/dev/null); trabajar "$ruta" uno
revisar "$d" rojo-no-levanta >/dev/null 2>&1
negar   "CI en rojo: sale con error"        probar_rama rojo "$d" rojo-no-levanta
afirmar "y no ha levantado ninguna pila"    no_contiene "up -d --build" "$(registro "$d" docker.log)"

d=$(montar); con_workflow "$d"; con_compose "$d"
ruta=$(abrir "$d" sin-checks-no-levanta 2>/dev/null); trabajar "$ruta" uno
revisar "$d" sin-checks-no-levanta >/dev/null 2>&1
afirmar "sin checks: sale bien…"            probar_rama sin-checks "$d" sin-checks-no-levanta
afirmar "…pero tampoco levanta nada"        no_contiene "up -d --build" "$(registro "$d" docker.log)"

caso "probar-rama.sh: en verde, levanta la pila de LA RAMA"
d=$(montar); con_workflow "$d"; con_compose "$d"
ruta=$(abrir "$d" con-pila 2>/dev/null); trabajar "$ruta" uno
revisar "$d" con-pila >/dev/null 2>&1
negar   "sin nadie escuchando, acaba diciéndolo" probar_rama verde "$d" con-pila
log=$(registro "$d" docker.log)
afirmar "levantó un proyecto propio, no el de siempre" contiene "compose -p repo-con-pila up -d --build" "$log"
afirmar "y la rama sigue sin fusionar"      hay_rama "$d" con-pila

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
afirmar "y lo que escribe es el HEAD de la rama" \
        test "$(cat "$d/repo/.git/worktrees/wtmarcable/revisado" 2>/dev/null)" \
           = "$(git -C "$ruta" rev-parse HEAD)"
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
afirmar "con la pila arriba, sale bien"     probar_rama verde "$d" clona-el-volumen
log=$(registro "$d" docker.log)
afirmar "crea el volumen de LA RAMA" \
        contiene "volume create repo-clona-el-volumen_postgres-data" "$log"
afirmar "y copia dentro los datos de tu volumen de siempre" \
        contiene "run --rm -v repo_postgres-data:/de -v repo-clona-el-volumen_postgres-data:/a" "$log"
afirmar "tu volumen nunca se escribe: solo se lee" \
        no_contiene "volume create repo_postgres-data" "$log"
VOLUMENES=""; RESPONDE=0

d=$(montar); con_workflow "$d"; con_compose "$d"
ruta=$(abrir "$d" ya-tenia-datos 2>/dev/null); trabajar "$ruta" uno
revisar "$d" ya-tenia-datos >/dev/null 2>&1
VOLUMENES="repo_postgres-data,repo-ya-tenia-datos_postgres-data"; RESPONDE=1
afirmar "si la rama ya tenía datos, sale bien"  probar_rama verde "$d" ya-tenia-datos
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
msg=$(probar_rama verde "$d" pila-viva 2>&1) && vivo=0 || vivo=1
afirmar "sale bien"                          test "$vivo" = 0
afirmar "dice dónde probarlo"                contiene "Lista para probar:  http://127.0.0.1:" "$msg"
afirmar "recuerda que los datos son una copia" contiene "tu pila de siempre no se ha tocado" "$msg"
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
probar_rama verde "$d" con-env >/dev/null 2>&1
afirmar "el worktree acaba teniendo su .env"  test -L "$ruta/.env"
afirmar "y es un enlace al de la raíz"        test "$(readlink "$ruta/.env")" = "$d/repo/.env"
RESPONDE=0

caso "probar-rama.sh: el puerto sale del nombre de la rama"
d=$(montar); con_workflow "$d"; con_compose "$d"
ruta=$(abrir "$d" puerto-propio 2>/dev/null); trabajar "$ruta" uno
revisar "$d" puerto-propio >/dev/null 2>&1
RESPONDE=1
probar_rama verde "$d" puerto-propio >/dev/null 2>&1
afirmar "usa el puerto que le toca a esta rama" \
        contiene "WEB_BIND_PORT=$(puerto_esperado puerto-propio) " "$(registro "$d" docker.log)"
RESPONDE=0

d=$(montar); con_workflow "$d"; con_compose "$d"
ruta=$(abrir "$d" puerto-pillado 2>/dev/null); trabajar "$ruta" uno
revisar "$d" puerto-pillado >/dev/null 2>&1
RESPONDE=1; PUERTOS_PILLADOS=3
probar_rama verde "$d" puerto-pillado >/dev/null 2>&1
afirmar "si está ocupado, se corre al siguiente libre" \
        contiene "WEB_BIND_PORT=$(( $(puerto_esperado puerto-pillado) + 3 )) " "$(registro "$d" docker.log)"
RESPONDE=0; PUERTOS_PILLADOS=0

caso "probar-rama.sh: --sin-ci, --sin-pila y el árbol sucio"
d=$(montar); con_workflow "$d"; con_compose "$d"
ruta=$(abrir "$d" sin-esperar 2>/dev/null); trabajar "$ruta" uno
revisar "$d" sin-esperar >/dev/null 2>&1
RESPONDE=1
afirmar "--sin-ci levanta la pila con el CI en rojo" probar_rama rojo "$d" sin-esperar --sin-ci
afirmar "…y la levanta de verdad"           contiene "up -d --build" "$(registro "$d" docker.log)"
RESPONDE=0

d=$(montar); con_workflow "$d"; con_compose "$d"
ruta=$(abrir "$d" solo-la-pr 2>/dev/null); trabajar "$ruta" uno
revisar "$d" solo-la-pr >/dev/null 2>&1
afirmar "--sin-pila abre la PR y para"      probar_rama verde "$d" solo-la-pr --sin-pila
afirmar "y no levanta nada"                 test -z "$(registro "$d" docker.log)"

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
VOLUMENES="repo_postgres-data,repo-con-pila-que-cerrar_postgres-data"
afirmar "cierra"                            cerrar verde "$d" con-pila-que-cerrar
log=$(registro "$d" docker.log)
afirmar "tumbó la pila de la rama con --volumes" \
        contiene "compose -p repo-con-pila-que-cerrar down --volumes" "$log"
# Y el volumen tiene que DESAPARECER, no basta con haber llamado al `down`:
# `--volumes` solo se lleva lo que creó Compose, y este lo creó probar-rama.sh.
afirmar "y borra a mano el volumen de la copia, que el down no se lleva" \
        contiene "volume rm repo-con-pila-que-cerrar_postgres-data" "$log"
afirmar "TU volumen de siempre no se toca" \
        no_contiene "volume rm repo_postgres-data" "$log"
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

echo
if [ "$fallos" -eq 0 ]; then
  echo "TODO BIEN: 0 fallos"
else
  echo "$fallos FALLOS"
  exit 1
fi
