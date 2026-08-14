#!/bin/bash
# Deja una rama lista para que la pruebes: empuja, abre la PR y espera al CI.
#
# **La pila local ya no se levanta sola** *(14-08-2026)*. Hasta ese día esto
# terminaba en un `docker compose up --build` en cuanto había verde, y levantar
# una pila no es gratis: construye imágenes, clona tu volumen de datos y ocupa un
# puerto, para una rama que muchas veces se juzga entera mirando la PR. Se pide:
# `--con-pila` al lanzarlo, o `--solo-pila` más tarde, cuando te apetezca verla.
#
# Quien pregunta es la skill `probar`, y pregunta **lo primero**: lanza esto de
# fondo y te consulta mientras el CI corre, para que la respuesta no cueste
# esperar. Aquí abajo solo hay banderas; el guión no pregunta nada por su cuenta,
# porque casi siempre corre en segundo plano y una pregunta ahí no la lee nadie.
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

rama_arg=""; forzar=0; sin_ci=0; con_pila=0; solo_pila=0
while [ $# -gt 0 ]; do
  case "$1" in
    --forzar)    forzar=1 ;;
    --sin-ci)    sin_ci=1 ;;
    --con-pila)  con_pila=1 ;;
    # Levantar y ya: ni empuja, ni abre PR, ni pregunta al CI. Es el camino de
    # «dije que no y he cambiado de idea», y lo caro de ese camino sería volver
    # a pasar por todo lo que ya pasó hace diez minutos.
    --solo-pila) solo_pila=1; con_pila=1 ;;
    -h | --help)
      morir "Uso: probar-rama.sh [<rama>] [--forzar] [--sin-ci]" \
        "                        [--con-pila | --solo-pila]" \
        "" \
        "  <rama>        la que se prueba. Por defecto, la del directorio actual." \
        "  --forzar      sigue aunque haya cambios sin guardar." \
        "  --sin-ci      no espera al CI." \
        "  --con-pila    además, levanta la pila local de la rama al terminar." \
        "  --solo-pila   solo la pila: ni empuja, ni abre PR, ni mira el CI." \
        "" \
        "Sin --con-pila no se levanta nada: empuja, abre la PR, espera al CI y" \
        "te dice dónde está. La pila es lo caro, y se pide." ;;
    -*) morir "Opción desconocida: $1" ;;
    *)  [ -z "$rama_arg" ] || morir "Sobra un argumento: $1"; rama_arg="$1" ;;
  esac
  shift
done

resolver_repo "$rama_arg" probar
exigir_arbol_limpio "$forzar"
[ -n "$ruta_wt" ] || morir "La rama '$rama' no tiene worktree." \
  "Ábrelo con: abrir-rama.sh $rama"

# La URL de la PR si la hay, vacío si no. Con --solo-pila puede no haberla
# todavía, y eso no es motivo para no levantar una pila local.
url_pr() { $GH pr view "$rama" --json url --jq .url 2>/dev/null || true; }

if [ "$solo_pila" != 1 ]; then
  empujar_y_abrir_pr

  case "$estado" in
    CLOSED) morir "La PR #$numero está cerrada. Decide tú qué hacer con ella." ;;
    MERGED) paso "la PR #$numero ya está fusionada; ciérrala con cerrar-rama.sh" ;;
  esac

  if [ "$sin_ci" != 1 ]; then
    paso "espero al CI de la PR #$numero"
    ci=0; esperar_ci --vigilar || ci=$?
    case "$ci" in
      1) aviso "" "Arréglalo en la rama y vuelve a lanzarme."; exit 1 ;;
      2) aviso "" \
           "Sin un verde no hay nada que valga la pena probar." \
           "Si quieres levantarlo igual:  probar-rama.sh $rama --solo-pila"
         exit 0 ;;
    esac
    paso "CI en verde"
  fi
fi

# ── La pila, solo si se ha pedido ───────────────────────────────────────────
if [ "$con_pila" != 1 ]; then
  aviso "" \
    "La PR está esperando:  $(url_pr)" \
    "" \
    "No he levantado nada: la pila local se pide." \
    "Para verla corriendo:  probar-rama.sh $rama --solo-pila" \
    "Cuando te convenza:    cerrar-rama.sh $rama"
  exit 0
fi

[ -f "$ruta_wt/docker-compose.yml" ] || {
  aviso "" 'Aquí no hay docker-compose.yml: no hay pila que levantar.' \
           "La PR está esperando: $(url_pr)"
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
  "  PR:      $(url_pr)" \
  "  logs:    docker compose -p $proyecto logs -f" \
  "  datos:   copia de $volumen_origen; tu pila de siempre no se ha tocado" \
  "" \
  "Si hay que cambiar algo: commitea en el worktree y vuelve a lanzarme." \
  "Cuando te convenza:     cerrar-rama.sh $rama"
