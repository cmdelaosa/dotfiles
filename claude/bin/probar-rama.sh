#!/bin/bash
# Deja una rama lista para que la pruebes: comprueba en local, exige que el diff
# esté revisado, empuja, abre la PR y espera al CI.
#
# Los dos frenos van ANTES del push a propósito. `verificar.sh` porque descubrir
# un lint roto en el CI cuesta el viaje entero, y la revisión porque una PR que
# nace ya con lo que el revisor ha dicho se lee de una vez, en vez de crecer
# tres commits de «arreglo lo revisado» que también hay que leer.
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
# Por lo mismo, **todas las salidas avisan por el sistema**: si el final normal
# ya no es una pila levantada, tampoco puede serlo el único momento en que suena
# algo, o volver a mirar el terminal pasa a ser cosa de acordarse.
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

rama_arg=""; forzar=0; sin_ci=0; sin_verificar=0; sin_revisar=0
pidio_con=0; pidio_solo=0
while [ $# -gt 0 ]; do
  case "$1" in
    --forzar)        forzar=1 ;;
    --sin-ci)        sin_ci=1 ;;
    --sin-verificar) sin_verificar=1 ;;
    --sin-revisar)   sin_revisar=1 ;;
    --con-pila)      pidio_con=1 ;;
    # Levantar y ya: ni comprueba, ni revisa, ni empuja, ni abre PR, ni pregunta
    # al CI. Es el camino de «dije que no y he cambiado de idea», y lo caro de
    # ese camino sería volver a pasar por todo lo que ya pasó hace diez minutos.
    --solo-pila)     pidio_solo=1 ;;
    -h | --help)
      morir "Uso: probar-rama.sh [<rama>] [--forzar] [--sin-ci]" \
        "                        [--sin-verificar] [--sin-revisar]" \
        "                        [--con-pila | --solo-pila]" \
        "" \
        "  <rama>            la que se prueba. Por defecto, la del directorio actual." \
        "  --forzar          sigue aunque haya cambios sin guardar." \
        "  --sin-ci          no espera al CI." \
        "  --sin-verificar   no lanza el verificar.sh de la rama." \
        "  --sin-revisar     empuja aunque el diff no esté revisado." \
        "  --con-pila        además, levanta la pila local de la rama al terminar." \
        "  --solo-pila       solo la pila: ni comprueba, ni empuja, ni mira el CI." \
        "" \
        "Sin --con-pila no se levanta nada: comprueba, empuja, abre la PR, espera" \
        "al CI y te dice dónde está. La pila es lo caro, y se pide." ;;
    -*) morir "Opción desconocida: $1" ;;
    *)  [ -z "$rama_arg" ] || morir "Sobra un argumento: $1"; rama_arg="$1" ;;
  esac
  shift
done

# Una combinación que se contradice se rechaza en vez de resolverse a favor de
# una de las dos. La ayuda las escribe como excluyentes, y aceptar las dos
# callando —quedándose con `--solo-pila`, que además NO empuja— daría por hecho
# un empujón que no ocurre. Igual con lo que `--solo-pila` ya se salta: no hay
# CI que no esperar, ni verificación ni revisión que perdonar, y una bandera que
# no hace nada engaña sobre lo que se puede pedir. Es el mismo motivo por el que
# `--sin-pila` murió gritando en vez de quedarse de adorno.
[ "$pidio_con$pidio_solo" != 11 ] ||
  morir "--con-pila y --solo-pila piden cosas distintas; elige una:" \
        "  --con-pila    comprueba, empuja, espera al CI y además levanta la pila." \
        "  --solo-pila   solo levanta la pila, sin tocar nada más."
if [ "$pidio_solo" = 1 ]; then
  sobra=""
  [ "$sin_ci"        != 1 ] || sobra="$sobra --sin-ci"
  [ "$sin_verificar" != 1 ] || sobra="$sobra --sin-verificar"
  [ "$sin_revisar"   != 1 ] || sobra="$sobra --sin-revisar"
  [ -z "$sobra" ] ||
    morir "--solo-pila ya se salta todo eso; sobra:$sobra" \
          "Solo levanta la pila: no comprueba, no revisa, no empuja y no mira el CI."
fi

hacer_pila=0; hacer_pr=1
[ "$pidio_con"  != 1 ] || hacer_pila=1
[ "$pidio_solo" != 1 ] || { hacer_pila=1; hacer_pr=0; }

resolver_repo "$rama_arg" probar
[ -n "$ruta_wt" ] || morir "La rama '$rama' no tiene worktree." \
  "Ábrelo con: abrir-rama.sh $rama"

# Si hay pila que levantar lo decide el guión, que mira el worktree de verdad,
# y no quien lo llama por su cuenta: la skill `probar` juzgaba lo mismo por su
# lado y podía responderse distinto sin que se notara.
hay_pila() { [ -f "$ruta_wt/docker-compose.yml" ]; }

# Puesta desde ya: bajo `set -u` una salida temprana que la mencione sin que
# `recordar_url_pr` haya llegado a correr mataría el guión en el mensaje.
url_pr=""

avisar() {                              # avisar <mensaje> [url-que-abrir]
  command -v "$AVISADOR" >/dev/null 2>&1 || return 0
  if [ -n "${2:-}" ]; then
    "$AVISADOR" -title "$(basename "$raiz") · $rama" -message "$1" -open "$2" \
      >/dev/null 2>&1 || true
  else
    "$AVISADOR" -title "$(basename "$raiz") · $rama" -message "$1" \
      >/dev/null 2>&1 || true
  fi
}

# Todas las salidas terminan igual: qué ha pasado, dónde está la PR y qué puedes
# hacer ahora. Estaba escrito tres veces y ya había empezado a separarse —dos
# espacios en una copia y uno en otra, y una de las tres sin decir qué sigue—,
# que es exactamente como una copia se queda callada sin que nadie lo note.
#
# Dos cosas que este mensaje no puede hacer. Una, ofrecer `--solo-pila` donde no
# hay pila: en dotfiles se ofrecía en cada pasada, y allí ese comando solo sabe
# contestar que no hay docker-compose.yml. Y dos, dejar creer que el CI está
# verde cuando nadie lo ha mirado, que es lo que pide `--sin-ci`.
despedida() {                           # despedida <primera-línea…>
  local siguiente
  if hay_pila; then
    siguiente="  local:   probar-rama.sh $rama --solo-pila"
  else
    siguiente="  local:   aquí no hay docker-compose.yml; no hay pila que levantar"
  fi
  aviso "" "$@"
  [ -z "$nota_ci" ] || aviso "" "$nota_ci"
  aviso "" \
    "  PR:      ${url_pr:-todavía no hay ninguna}" \
    "$siguiente" \
    "  cerrar:  cerrar-rama.sh $rama"
}

# Lo que se puede decir del CI, y solo si se ha preguntado. Un «verde» que nadie
# ha comprobado es lo único que ninguno de estos guiones puede permitirse decir,
# y con `--sin-ci` llegó a decirlo de verdad sobre una PR en rojo.
nota_ci=""

if [ "$hacer_pr" = 1 ]; then
  # El árbol sucio solo estropea una PR, que es lo que sale incompleto; una pila
  # local se construye del disco tal cual y verlo sucio es justo lo que quieres.
  # Y con el flujo nuevo el árbol está sucio a menudo cuando llega `--solo-pila`:
  # el revisor acaba de dejar sus arreglos ahí mientras el CI corría.
  exigir_arbol_limpio "$forzar"

  # Antes que nada, que haya algo que empujar: comprobar y revisar una rama vacía
  # es gastar minutos para acabar diciendo que no había nada que hacer.
  hay_algo_que_empujar

  # Primero lo mecánico y luego lo que hay que leer: si `verificar.sh` está rojo,
  # la revisión se habría gastado en código que ni siquiera pasa el lint.
  exigir_verificacion "$sin_verificar"
  exigir_revision "$sin_revisar"

  empujar_y_abrir_pr
  recordar_url_pr

  case "$estado" in
    CLOSED) morir "La PR #$numero está cerrada. Decide tú qué hacer con ella." \
              "Si lo que querías era la pila local:  probar-rama.sh $rama --solo-pila" ;;
    MERGED) paso "la PR #$numero ya está fusionada; ciérrala con cerrar-rama.sh" ;;
  esac

  if [ "$sin_ci" != 1 ]; then
    paso "espero al CI de la PR #$numero"
    ci=0; esperar_ci --vigilar || ci=$?
    case "$ci" in
      1) despedida "El CI no está verde. Arréglalo en la rama y vuelve a lanzarme."
         avisar "El CI no está verde" "$url_pr"
         exit 1 ;;
      2) despedida "Sin un verde no hay nada que valga la pena probar."
         avisar "Sin checks: la PR espera" "$url_pr"
         exit 0 ;;
    esac
    paso "CI en verde"
    nota_ci="Su CI está verde."
  else
    nota_ci="Su CI está sin mirar, que es lo que pide --sin-ci."
  fi
else
  recordar_url_pr
fi

# ── La pila, solo si se ha pedido ───────────────────────────────────────────
if [ "$hacer_pila" != 1 ]; then
  despedida "No he levantado nada: la pila local se pide."
  avisar "Lista para mirar la PR" "$url_pr"
  exit 0
fi

hay_pila || {
  despedida 'Aquí no hay docker-compose.yml: no hay pila que levantar.'
  avisar "Aquí no hay pila que levantar" "$url_pr"
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
# Qué pasó de verdad se guarda, porque el mensaje final lo contaba siempre igual
# —«copia de <volumen>»— también cuando no había copiado nada.
if $DOCKER volume inspect "$volumen_rama" >/dev/null 2>&1; then
  paso "la pila de esta rama ya tenía datos; los dejo como están"
  datos="los que ya tenía esta rama; tu pila de siempre no se ha tocado"
elif $DOCKER volume inspect "$volumen_origen" >/dev/null 2>&1; then
  paso "clono $volumen_origen → $volumen_rama"
  $DOCKER volume create "$volumen_rama" >/dev/null
  $DOCKER run --rm \
    -v "$volumen_origen":/de -v "$volumen_rama":/a \
    alpine sh -c 'cd /de && cp -a . /a' >/dev/null
  datos="copia de $volumen_origen; tu pila de siempre no se ha tocado"
else
  paso "no hay $volumen_origen que clonar: la pila arranca vacía"
  datos="vacíos: aquí no había ningún $volumen_origen que clonar"
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
    avisar "La pila no responde en $url"
    exit 1
  fi
  sleep 2
done

avisar "Lista para probar en $url" "$url"

aviso "" \
  "Lista para probar:  $url" \
  "  PR:      ${url_pr:-todavía no hay ninguna}" \
  "  logs:    docker compose -p $proyecto logs -f" \
  "  datos:   $datos" \
  "" \
  "Si hay que cambiar algo: commitea en el worktree y vuelve a lanzarme." \
  "Cuando te convenza:     cerrar-rama.sh $rama"
