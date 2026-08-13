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
    # Cuándo acabaron los checks. El `--jq` de gh imprime un escalar en crudo,
    # sin comillas, igual que `jq -r`.
    case " $* " in
      *" --json completedAt "*)
        case "${ESCENARIO:-verde}" in
          *-viejo) echo "2020-01-01T00:00:00Z" ;;   # main se movió DESPUÉS del verde
          *)       echo "2999-01-01T00:00:00Z" ;;   # el verde es más nuevo que main
        esac
        exit 0 ;;
    esac
    case "${ESCENARIO:-verde}" in
      verde*) echo '[{"bucket":"pass","name":"CI","link":"https://example.test/1"}]' ;;
      rojo)   echo '[{"bucket":"fail","name":"CI","link":"https://example.test/1"}]'; exit 1 ;;
      *)      exit 1 ;;   # sin checks: gh no imprime JSON ninguno
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
cat > "$TMP/bin/docker" <<'FALSO'
#!/bin/bash
set -u
printf '%s\n' "$*" >> "$ESTADO/docker.log"
case "$1 ${2:-}" in
  "volume inspect") exit 1 ;;                 # ningún volumen existe todavía
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

cat > "$TMP/bin/desplegar.sh" <<'FALSO'
#!/bin/bash
printf '%s\n' "$*" >> "$ESTADO/despliegues.log"
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
      "$bin/cerrar-rama.sh" "$@" )
}

# Un CI de mentira, para separar «aquí no hay CI» de «aquí hay CI y esta PR no
# dispara nada», que es lo que hace el `paths-ignore` de welzy con las PRs de
# solo documentación.
con_workflow() { # con_workflow <dir>
  mkdir -p "$1/repo/.github/workflows"
  printf 'name: CI\non:\n  pull_request:\njobs:\n  x:\n    runs-on: ubuntu-latest\n' \
    > "$1/repo/.github/workflows/ci.yml"
  git -C "$1/repo" add -A
  git -C "$1/repo" commit -qm "ci: workflow de mentira"
  git -C "$1/repo" push -q origin main
}

probar_rama() {  # probar_rama <escenario> <dir> [args…]
  local esc=$1 d=$2; shift 2
  ( cd "$d/repo" &&
      ESTADO="$d/estado" ESPEJO="$d/espejo" ESCENARIO="$esc" ESPERA_CHECKS=0 ESPERA_PILA=1 \
      "$bin/probar-rama.sh" "$@" )
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
afirmar "con el CI verde, sale bien"        probar_rama verde "$d" en-pruebas
afirmar "y la rama sigue SIN fusionar"      hay_rama "$d" en-pruebas
afirmar "y su worktree sigue en pie"        hay_worktree "$d" en-pruebas
afirmar "y la rama remota sigue viva"       hay_remota "$d" en-pruebas

caso "probar-rama.sh: sin verde no levanta nada"
d=$(montar); con_workflow "$d"; con_compose "$d"
ruta=$(abrir "$d" rojo-no-levanta 2>/dev/null); trabajar "$ruta" uno
negar   "CI en rojo: sale con error"        probar_rama rojo "$d" rojo-no-levanta
afirmar "y no ha levantado ninguna pila"    no_contiene "up -d --build" "$(registro "$d" docker.log)"

d=$(montar); con_workflow "$d"; con_compose "$d"
ruta=$(abrir "$d" sin-checks-no-levanta 2>/dev/null); trabajar "$ruta" uno
afirmar "sin checks: sale bien…"            probar_rama sin-checks "$d" sin-checks-no-levanta
afirmar "…pero tampoco levanta nada"        no_contiene "up -d --build" "$(registro "$d" docker.log)"

caso "probar-rama.sh: en verde, levanta la pila de LA RAMA"
d=$(montar); con_workflow "$d"; con_compose "$d"
ruta=$(abrir "$d" con-pila 2>/dev/null); trabajar "$ruta" uno
negar   "sin nadie escuchando, acaba diciéndolo" probar_rama verde "$d" con-pila
log=$(registro "$d" docker.log)
afirmar "levantó un proyecto propio, no el de siempre" contiene "compose -p repo-con-pila up -d --build" "$log"
afirmar "y la rama sigue sin fusionar"      hay_rama "$d" con-pila

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

caso "cerrar-rama.sh: un verde viejo no vale"
# El CI prueba la FUSIÓN con main, no la rama. Si main se movió después, ese
# verde probó otra cosa — y GitHub la sigue marcando en verde igual.
d=$(montar); con_workflow "$d"; ruta=$(abrir "$d" verde-caducado 2>/dev/null); trabajar "$ruta" uno
afirmar "cierra"                        cerrar verde-viejo "$d" verde-caducado
afirmar "pero antes metió main en la rama y volvió a esperar" \
        contiene "update-branch" "$(registro "$d" gh.log)"

d=$(montar); con_workflow "$d"; ruta=$(abrir "$d" verde-al-dia 2>/dev/null); trabajar "$ruta" uno
afirmar "con el verde al día, cierra igual" cerrar verde "$d" verde-al-dia
afirmar "y NO toca la rama sin necesidad"   no_contiene "update-branch" "$(registro "$d" gh.log)"

caso "cerrar-rama.sh: se lleva la pila de la rama, con sus volúmenes"
d=$(montar); con_workflow "$d"; con_compose "$d"
ruta=$(abrir "$d" con-pila-que-cerrar 2>/dev/null); trabajar "$ruta" uno
afirmar "cierra"                            cerrar verde "$d" con-pila-que-cerrar
afirmar "tumbó la pila de la rama con --volumes" \
        contiene "compose -p repo-con-pila-que-cerrar down --volumes" "$(registro "$d" docker.log)"

echo
if [ "$fallos" -eq 0 ]; then
  echo "TODO BIEN: 0 fallos"
else
  echo "$fallos FALLOS"
  exit 1
fi
