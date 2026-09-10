#!/bin/bash
# Cierra una rama que ya has probado: comprueba que sigue verde, fusiona la PR,
# despliega a producción, y limpia la pila local, el worktree y las dos ramas.
# Se lanza DESDE LA RAÍZ, nunca desde dentro del worktree que va a borrar.
#
# Este es el segundo tiempo. El primero es `probar-rama.sh`, que deja la PR
# verde y para —y levanta la pila local solo si se la pidieron—. Hasta el
# 13-08-2026 esto era un solo comando que fusionaba en cuanto el CI se ponía
# verde, y el visto bueno humano no cabía en ninguna parte.
#
# Por qué el borrado va a mano y en un orden fijo: `gh pr merge --delete-branch`
# parece hacerlo solo, y lo que hace es fusionar en GitHub y luego fallar en
# local, con la rama ya sin PR y todavía viva. Los dos fallos, medidos:
#
#     error: cannot delete branch 'la-rama' used by worktree at '…/wtla-rama'
#     fatal: 'main' is already used by worktree at '…/wtmain'
#
# El segundo ni siquiera avisa de que quedó a medias. De ahí el orden: worktree
# fuera, rama local fuera, rama remota fuera. Y cada orden de git suelta, porque
# el hook `git-no-main.sh` mira la línea entera y encadenar tira su excepción.
#
# Lo irreversible tiene freno. Con el árbol sucio no fusiona ni borra: enseña los
# ficheros y para. `--forzar` lo salta y hay que escribirlo a propósito. Sin CI
# tampoco fusiona: «sin checks» no es un aprobado, y desde el 24-08-2026 tampoco
# lo es «los checks que había han salido verdes» —si el CI que el repositorio
# exige no ha corrido sobre la cabeza de la PR, esto para, y `--solo-md` no lo
# salta—.
set -Eeuo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib-ramas.sh"

DESPLEGAR="${DESPLEGAR:-$HOME/Projects/cmdlo-infra/desplegar.sh}"

rama_arg=""; forzar=0; solo_limpiar=0; sin_desplegar=0; solo_md=0
while [ $# -gt 0 ]; do
  case "$1" in
    --forzar)        forzar=1 ;;
    --solo-limpiar)  solo_limpiar=1 ;;
    --sin-desplegar) sin_desplegar=1 ;;
    --solo-md)       solo_md=1 ;;
    -h | --help)
      morir "Uso: cerrar-rama.sh [<rama>] [--forzar] [--solo-limpiar]" \
        "                        [--sin-desplegar] [--solo-md]" \
        "" \
        "  <rama>            la que se cierra. Por defecto, la del directorio actual." \
        "  --forzar          cierra aunque haya cambios sin guardar. Los tira." \
        "  --solo-limpiar    no fusiona ni despliega: da por hecho que la PR ya" \
        "                    está fusionada y solo quita pila, worktree y ramas." \
        "  --sin-desplegar   fusiona y limpia, pero no toca producción." \
        "  --solo-md         rama de solo markdown: no despliega, y un «sin" \
        "                    checks» no le impide fusionar —pero un check que" \
        "                    FALTA sí—. Se niega si el diff toca algo que no" \
        "                    acabe en .md." ;;
    -*) morir "Opción desconocida: $1" ;;
    *)  [ -z "$rama_arg" ] || morir "Sobra un argumento: $1"; rama_arg="$1" ;;
  esac
  shift
done

# `--solo-md` ya implica no desplegar. Escribir los dos hace pensar que el
# despliegue seguiría vivo sin el segundo, que es exactamente lo contrario.
[ "$solo_md$sin_desplegar" != 11 ] ||
  morir "--solo-md ya no despliega nada; sobra --sin-desplegar."

resolver_repo "$rama_arg" cerrar
exigir_estar_fuera
exigir_arbol_limpio "$forzar"

# Antes de fusionar nada, y también con `--solo-limpiar`: la bandera se comprueba
# siempre contra el diff, porque su valor entero está en que no se la pueda
# conceder quien la escribe. Con la rama ya fusionada el diff sale vacío y esto
# pasa solo, que es lo correcto — no hay nada que no sea markdown.
[ "$solo_md" != 1 ] || exigir_solo_md "sin despliegue, y sin exigir checks"

# ── Fusionar ────────────────────────────────────────────────────────────────
fusionada_ahora=0
if [ "$solo_limpiar" != 1 ]; then
  empujar_y_abrir_pr

  case "$estado" in
    CLOSED) morir "La PR #$numero está cerrada sin fusionar. Decide tú qué hacer con ella." ;;
    MERGED) paso "la PR #$numero ya estaba fusionada" ;;
    *)
      paso "compruebo el CI de la PR #$numero"
      juzgar_ci() {
        ci=0; esperar_ci --vigilar || ci=$?
        case "$ci" in
          # El rojo frena también con `--solo-md`: el atajo dice que la prosa no
          # necesita examen propio, no que se fusione por encima de uno suspendido.
          1) aviso "" "No fusiono nada."; exit 1 ;;
          # Y falta lo que tenía que correr. Frena igual que el rojo, y también
          # con `--solo-md`: fusionar aquí es exactamente lo que pasó con la PR
          # #35 de reel el 24-08-2026 —el único check era el de Cloudflare—.
          4) aviso "" "No fusiono nada."; exit 1 ;;
          2) if [ "$solo_md" = 1 ]; then
               # Es justo lo que provoca el `paths-ignore` de welzy con una PR de
               # solo documentación, y hasta hoy dejaba la rama abierta esperando
               # una fusión a mano que nadie recordaba hacer.
               aviso "" "Sin checks, pero la rama es solo markdown: la fusiono igual."
             else
               aviso "" \
                 "No la fusiono." \
                 "" \
                 "Mírala tú y, cuando la fusiones, vuelve con:" \
                 "    cerrar-rama.sh $rama --solo-limpiar"
               exit 0
             fi ;;
        esac
      }
      juzgar_ci

      # Un verde viejo no vale: si main se ha movido, ese CI probó otra fusión.
      # Se mete main en la rama, se vuelve a juzgar el CI, y se vuelve a
      # PREGUNTAR — porque main puede haberse movido otra vez mientras se
      # esperaba, y con varias ramas en vuelo eso deja de ser hipotético: es el
      # escenario para el que se montó todo esto. Hasta el 13-08-2026 era un
      # solo tiro, y la segunda espera se fusionaba a ciegas.
      #
      # Cada vuelta es un main DISTINTO: `asegurar_ci_fresco` compara el SHA de
      # origin/main con el que metió la vuelta anterior, y si es el mismo no
      # devuelve 10 sino 11 —GitHub enseñando todavía el run viejo, que es la
      # carrera del 10-09-2026 en erp: cuatro vueltas en segundos con main
      # quieto, y un «main se ha movido 4 veces» que era mentira—. Con 11 no
      # hay nada que reintentar aquí: se dice y se para. Y el tope de vueltas
      # de verdad sigue existiendo: un `main` que no para quieto es una
      # decisión de Carlos, no del guión.
      vueltas=0
      while :; do
        fresco=0; asegurar_ci_fresco || fresco=$?
        case "$fresco" in
          0)  break ;;
          10) vueltas=$((vueltas + 1))
              if [ "$vueltas" -gt "${VUELTAS_CI:-3}" ]; then
                morir "" \
                  "$principal se ha movido $vueltas veces mientras esperaba a su CI." \
                  "No fusiono con un verde que probó otra fusión. No he borrado nada:" \
                  "vuelve a lanzarme cuando $principal se esté quieto."
              fi
              juzgar_ci ;;
          *)  morir "" \
                "No fusiono con un verde que no sé de qué cabeza es. No he borrado nada:" \
                "vuelve a lanzarme dentro de unos minutos, cuando GitHub se haya" \
                "enterado de su propio merge." ;;
        esac
      done

      # «Verde» solo si alguien ha visto uno. Con `--solo-md` aquí se llega
      # también por el camino de «sin checks», y cantar un verde que no existe es
      # la misma mentira que `--sin-ci` provocó el 14-08-2026 un guión más allá.
      if [ "$ci" = 2 ]; then
        paso "sin checks, pero es solo markdown: fusiono la PR #$numero"
      else
        paso "verde: fusiono la PR #$numero"
      fi
      $GH pr merge "$numero" --merge >&2 ||
        morir "" "GitHub no ha podido fusionar la PR #$numero. No he borrado nada."
      fusionada_ahora=1 ;;
  esac
fi

# ── Producción ──────────────────────────────────────────────────────────────
# Solo si el repositorio sigue el contrato de cmdlo: publica imágenes con
# `release.yml` y trae su `ops/deploy/deploy.sh`. Los demás no tienen a dónde ir.
if [ "$fusionada_ahora" = 1 ] && [ "$sin_desplegar" != 1 ]; then
  # Un cambio de solo markdown no cambia lo que corre en producción: la imagen
  # que se publicaría es la misma con otro README dentro. Desplegar por él es
  # gastar un despliegue —y su riesgo— en algo que nadie va a notar allí.
  if [ "$solo_md" = 1 ]; then
    paso "solo markdown: no despliego nada a producción"
  elif [ -x "$DESPLEGAR" ] && [ -f "$raiz/ops/deploy/deploy.sh" ] &&
     [ -f "$raiz/.github/workflows/release.yml" ]; then
    paso "despliego $(basename "$raiz") a producción"
    "$DESPLEGAR" "$(basename "$raiz")" >&2 ||
      aviso "" "OJO: el despliegue ha fallado. La PR SÍ está fusionada." \
               "Producción sigue con lo anterior; mira la salida de arriba antes de limpiar."
  else
    paso "este repositorio no se despliega con desplegar.sh; me lo salto"
  fi
fi

# ── La pila local de la rama ────────────────────────────────────────────────
# Con sus volúmenes: son una copia desechable que hizo probar-rama.sh. El
# volumen de tu pila de siempre nunca se toca — tiene otro nombre de proyecto.
proyecto=$(proyecto_de_rama)
hubo_pila=0
if $DOCKER compose -p "$proyecto" ps -q >/dev/null 2>&1 &&
   [ -n "$($DOCKER compose -p "$proyecto" ps -aq 2>/dev/null)" ]; then
  paso "tumbo la pila $proyecto y sus volúmenes de copia"
  $DOCKER compose -p "$proyecto" down --volumes >&2 || true
  hubo_pila=1
fi

# El barrido de abajo va aparte del `down` a propósito, y no solo porque Compose
# no se lleve lo que no creó: los contenedores se pueden haber ido sin el volumen
# —un `down` a secas, un `up --build` que se cayó construyendo— y entonces
# `ps -aq` no ve nada y el bloque de arriba ni corre. Desde que la pila se levanta
# con `--solo-pila`, sin CI de por medio, ese estado dejó de ser raro.
#
# Y **después del `down`, a mano**, porque `--volumes` no basta: solo se lleva
# los volúmenes que creó Compose, y el de datos no es suyo. Lo crea
# `probar-rama.sh` con `docker volume create` antes de levantar nada, que es la
# única forma de copiarle dentro tus datos antes de que arranque Postgres.
# Compose lo dice al levantar la pila —«already exists but was not created by
# Docker Compose»— y al bajarla lo deja donde está.
#
# Hasta el 14-08-2026 eso significaba que **cada rama probada dejaba una copia
# entera de tu base de datos en el disco, para siempre**, mientras este guión
# decía «tumbo la pila y sus volúmenes de copia». Se vio al cerrar la rama de
# `verificar.sh`: 208 MB en tres volúmenes de ramas ya cerradas, uno de ellos
# recién «limpiado». La matriz tampoco lo veía, porque comprobaba que se llamara
# al `down --volumes`, no que el volumen dejara de existir.
#
# Por prefijo y no por el nombre exacto: si la pila gana un segundo volumen
# mañana, este barrido ya se lo lleva. El `_` del final es lo que impide que
# `welzy-cartera` se lleve por delante los de `welzy-cartera-en-pestanas`, y el
# ancla `^` que un nombre de rama se cuele en medio de otro.
#
# Que el filtro de Docker entiende expresiones regulares y no solo subcadenas
# está comprobado contra el Docker de verdad, no solo contra el doble de la
# matriz —que es donde esto se habría quedado en verde diciendo mentiras—:
#
#     docker volume ls -q --filter name=^welzy-cartera_   → (vacío)
#     docker volume ls -q --filter name=^welzy_           → welzy_postgres-data
#
# El nombre del proyecto no puede traer metacaracteres: `proyecto_de_rama` lo
# pasa por un `tr -cd '[:alnum:]-'`.
sobrantes=$($DOCKER volume ls -q --filter "name=^${proyecto}_" 2>/dev/null || true)
if [ -n "$sobrantes" ]; then
  hubo_pila=1
  paso "borro los volúmenes de copia que el down no se lleva"
  # Y si alguno no se deja borrar se dice, en vez de dar el paso por hecho: un
  # `|| true` aquí sería otra vez el mismo fallo que este cambio arregla —
  # anunciar una limpieza que no ha ocurrido—, solo que un piso más abajo.
  printf '%s\n' "$sobrantes" | while IFS= read -r v; do
    [ -n "$v" ] || continue
    $DOCKER volume rm "$v" >&2 ||
      aviso "OJO: no he podido borrar el volumen $v, que sigue ocupando disco." \
            "    docker volume rm $v"
  done
fi

# ── La limpieza, en el único orden que funciona ─────────────────────────────
if [ "$hubo_remoto" = 1 ]; then
  git -C "$raiz" fetch origin --quiet --prune

  # Borrar una rama que no está en ningún sitio es la forma de perder trabajo.
  if ! git -C "$raiz" merge-base --is-ancestor "$rama" "origin/$principal"; then
    if [ "$forzar" != 1 ]; then
      morir "" \
        "'$rama' NO está dentro de origin/$principal: borrarla perdería sus commits." \
        "" \
        "    git -C $raiz log --oneline origin/$principal..$rama" \
        "" \
        "Si de verdad sobran, repítelo con --forzar."
    fi
    aviso "OJO: --forzar; '$rama' no está en origin/$principal y se borra igual."
  fi
fi

if [ -n "$ruta_wt" ]; then
  paso "quito el worktree $ruta_wt"
  if [ "$forzar" = 1 ]; then
    git -C "$raiz" worktree remove --force "$ruta_wt"
  else
    git -C "$raiz" worktree remove "$ruta_wt"
  fi
fi

paso "borro la rama local $rama"
git -C "$raiz" branch -D "$rama" >&2

if [ "$hubo_remoto" = 1 ]; then
  if git -C "$raiz" ls-remote --exit-code --heads origin "$rama" >/dev/null 2>&1; then
    paso "borro la rama remota origin/$rama"
    git -C "$raiz" push origin --delete "$rama" >&2
  else
    paso "la rama remota ya no estaba"
  fi
fi

# Y dejar la raíz donde tiene que estar: en principal, al día. Si otra sesión la
# tiene a medias se avisa y no se toca — mover HEAD por debajo de alguien es
# exactamente el fallo que todo esto viene a evitar.
rama_raiz=$(git -C "$raiz" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
if [ "$rama_raiz" != "$principal" ]; then
  aviso "OJO: la raíz está en '$rama_raiz', no en $principal. No la toco."
elif [ -n "$(git -C "$raiz" status --porcelain)" ]; then
  aviso "OJO: la raíz tiene cambios sin guardar. No adelanto $principal."
elif [ "$hubo_remoto" = 1 ]; then
  paso "adelanto $principal en la raíz"
  git -C "$raiz" pull --ff-only --quiet
fi

# Decir «sin pila» cuando nunca hubo pila es afirmar una limpieza que no ocurrió,
# y desde que levantar es opcional el caso normal es que no la hubiera.
if [ "$hubo_pila" = 1 ]; then
  aviso "" "Cerrada '$rama': sin pila, sin worktree, sin rama local y sin rama remota."
else
  aviso "" "Cerrada '$rama': sin worktree, sin rama local y sin rama remota (no había pila)."
fi
