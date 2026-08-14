#!/bin/bash
# Deja una rama lista para que la pruebes: comprueba en local, exige que el diff
# esté revisado, empuja, abre la PR, espera al CI y, si está verde, levanta SU
# pila local con una copia de tus datos y te avisa.
#
# Los dos frenos van ANTES del push a propósito. `verificar.sh` porque descubrir
# un lint roto en el CI cuesta el viaje entero, y la revisión porque una PR que
# nace ya con lo que el revisor ha dicho se lee de una vez, en vez de crecer
# tres commits de «arreglo lo revisado» que también hay que leer.
#
# **No fusiona nada.** Esa es toda la idea: hasta el 13-08-2026 `cerrar-rama.sh`
# fusionaba sola en cuanto el CI se ponía verde, y eso deja fuera lo único que el
# CI no sabe hacer — mirarlo. Si al probarlo hay que cambiar algo, se cambia en la
# rama y se vuelve a lanzar esto; main recibe una fusión limpia en vez de tres
# commits de arreglar lo que se vio después.
#
# La pila es un proyecto de Compose propio, `<repo>-<rama>`, con su puerto y sus
# volúmenes. Dos cosas que eso compra: dos ramas levantadas a la vez no se pisan,
# y una migración de Flyway de la rama **no toca tu base de desarrollo** — se
# aplica sobre una copia. La copia se hace al levantar y se tira al cerrar.
#
# Cuando termines: `cerrar-rama.sh <rama>`, que fusiona y despliega.
set -Eeuo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib-ramas.sh"

rama_arg=""; forzar=0; sin_ci=0; sin_pila=0; sin_verificar=0; sin_revisar=0
while [ $# -gt 0 ]; do
  case "$1" in
    --forzar)        forzar=1 ;;
    --sin-ci)        sin_ci=1 ;;
    --sin-pila)      sin_pila=1 ;;
    --sin-verificar) sin_verificar=1 ;;
    --sin-revisar)   sin_revisar=1 ;;
    -h | --help)
      morir "Uso: probar-rama.sh [<rama>] [--forzar] [--sin-ci] [--sin-pila]" \
        "                        [--sin-verificar] [--sin-revisar]" \
        "" \
        "  <rama>            la que se prueba. Por defecto, la del directorio actual." \
        "  --forzar          sigue aunque haya cambios sin guardar." \
        "  --sin-ci          no espera al CI: levanta la pila y ya." \
        "  --sin-pila        solo empuja y abre la PR; no levanta nada." \
        "  --sin-verificar   no lanza el verificar.sh de la rama." \
        "  --sin-revisar     empuja aunque el diff no esté revisado." ;;
    -*) morir "Opción desconocida: $1" ;;
    *)  [ -z "$rama_arg" ] || morir "Sobra un argumento: $1"; rama_arg="$1" ;;
  esac
  shift
done

resolver_repo "$rama_arg" probar
exigir_arbol_limpio "$forzar"
[ -n "$ruta_wt" ] || morir "La rama '$rama' no tiene worktree." \
  "Ábrelo con: abrir-rama.sh $rama"

# Antes que nada, que haya algo que empujar: comprobar y revisar una rama vacía
# es gastar minutos para acabar diciendo que no había nada que hacer.
hay_algo_que_empujar

# Primero lo mecánico y luego lo que hay que leer: si `verificar.sh` está rojo,
# la revisión se habría gastado en código que ni siquiera pasa el lint.
exigir_verificacion "$sin_verificar"
exigir_revision "$sin_revisar"

empujar_y_abrir_pr

case "$estado" in
  CLOSED) morir "La PR #$numero está cerrada. Decide tú qué hacer con ella." ;;
  MERGED) paso "la PR #$numero ya está fusionada; ciérrala con cerrar-rama.sh" ;;
esac

if [ "$sin_ci" != 1 ]; then
  paso "espero al CI de la PR #$numero"
  ci=0; esperar_ci --vigilar || ci=$?
  case "$ci" in
    1) aviso "" "No levanto nada: arréglalo y vuelve a lanzarme."; exit 1 ;;
    2) aviso "" \
         "No levanto la pila: sin un verde no hay nada que valga la pena probar." \
         "Si quieres probarlo igual:  probar-rama.sh $rama --sin-ci"
       exit 0 ;;
  esac
  paso "CI en verde"
fi

[ "$sin_pila" != 1 ] || { aviso "" "Listo. La PR es $($GH pr view "$numero" --json url --jq .url)"; exit 0; }

# ── La pila de la rama ──────────────────────────────────────────────────────
# «Verde» solo si alguien ha mirado. Con `--sin-ci` este mensaje decía «La PR
# está verde y esperando» sin haber preguntado por un solo check, y lo dijo de
# verdad el 14-08-2026 sobre una PR cuyo CI estaba en rojo. Afirmar un verde que
# no se ha comprobado es la única cosa que ninguno de estos guiones puede hacer.
[ -f "$ruta_wt/docker-compose.yml" ] || {
  if [ "$sin_ci" = 1 ]; then
    estado_ci="y su CI sin mirar, porque me lo has pedido con --sin-ci"
  else
    estado_ci="verde"
  fi
  aviso "" 'Aquí no hay docker-compose.yml: no hay pila que levantar.' \
           "La PR está $estado_ci: $($GH pr view "$numero" --json url --jq .url)"
  exit 0
}

# El .env no está versionado —y no debe estarlo—, así que un worktree recién
# abierto no lo tiene y la pila arrancaría sin ninguna de tus claves. Se enlaza,
# no se copia: una copia se queda vieja el día que cambies la de la raíz.
if [ -f "$raiz/.env" ] && [ ! -e "$ruta_wt/.env" ]; then
  paso "enlazo el .env de la raíz"
  ln -s "$raiz/.env" "$ruta_wt/.env"
fi

proyecto=$(proyecto_de_rama)
puerto=$(puerto_de_rama)
volumen_origen="$(basename "$raiz")_postgres-data"
volumen_rama="${proyecto}_postgres-data"

# Los datos: una copia del volumen de tu pila de siempre. Sin esto la rama
# arranca con la base vacía, y una cartera vacía no prueba nada de una cartera.
if $DOCKER volume inspect "$volumen_rama" >/dev/null 2>&1; then
  paso "la pila de esta rama ya tenía datos; los dejo como están"
elif $DOCKER volume inspect "$volumen_origen" >/dev/null 2>&1; then
  paso "clono $volumen_origen → $volumen_rama"
  $DOCKER volume create "$volumen_rama" >/dev/null
  $DOCKER run --rm \
    -v "$volumen_origen":/de -v "$volumen_rama":/a \
    alpine sh -c 'cd /de && cp -a . /a' >/dev/null
else
  paso "no hay $volumen_origen que clonar: la pila arranca vacía"
fi

paso "levanto $proyecto en el puerto $puerto"
( cd "$ruta_wt" && WEB_BIND_PORT="$puerto" $DOCKER compose -p "$proyecto" up -d --build ) >&2

url="http://127.0.0.1:$puerto"
paso "espero a que $url responda"
intentos=0
until $CURL -fsS -o /dev/null "$url" 2>/dev/null; do
  intentos=$((intentos + 1))
  if [ "$intentos" -ge "${ESPERA_PILA:-60}" ]; then
    aviso "" "La pila no responde en $url después de $intentos intentos." \
             "Mira qué pasa:  docker compose -p $proyecto logs"
    exit 1
  fi
  sleep 2
done

command -v "$AVISADOR" >/dev/null 2>&1 &&
  "$AVISADOR" -title "$(basename "$raiz") · $rama" \
              -message "Lista para probar en $url" -open "$url" >/dev/null 2>&1 || true

aviso "" \
  "Lista para probar:  $url" \
  "  PR:      $($GH pr view "$numero" --json url --jq .url)" \
  "  logs:    docker compose -p $proyecto logs -f" \
  "  datos:   copia de $volumen_origen; tu pila de siempre no se ha tocado" \
  "" \
  "Si hay que cambiar algo: commitea en el worktree y vuelve a lanzarme." \
  "Cuando te convenza:     cerrar-rama.sh $rama"
