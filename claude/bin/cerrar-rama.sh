#!/bin/bash
# Cierra una rama que ya has probado: comprueba que sigue verde, fusiona la PR,
# despliega a producción, y limpia la pila local, el worktree y las dos ramas.
# Se lanza DESDE LA RAÍZ, nunca desde dentro del worktree que va a borrar.
#
# Este es el segundo tiempo. El primero es `probar-rama.sh`, que levanta la rama
# en local y para. Hasta el 13-08-2026 esto era un solo comando que fusionaba en
# cuanto el CI se ponía verde, y el visto bueno humano no cabía en ninguna parte.
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
# tampoco fusiona: «sin checks» no es un aprobado.
set -Eeuo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib-ramas.sh"

DESPLEGAR="${DESPLEGAR:-$HOME/Projects/cmdlo-infra/desplegar.sh}"

rama_arg=""; forzar=0; solo_limpiar=0; sin_desplegar=0
while [ $# -gt 0 ]; do
  case "$1" in
    --forzar)        forzar=1 ;;
    --solo-limpiar)  solo_limpiar=1 ;;
    --sin-desplegar) sin_desplegar=1 ;;
    -h | --help)
      morir "Uso: cerrar-rama.sh [<rama>] [--forzar] [--solo-limpiar] [--sin-desplegar]" \
        "" \
        "  <rama>            la que se cierra. Por defecto, la del directorio actual." \
        "  --forzar          cierra aunque haya cambios sin guardar. Los tira." \
        "  --solo-limpiar    no fusiona ni despliega: da por hecho que la PR ya" \
        "                    está fusionada y solo quita pila, worktree y ramas." \
        "  --sin-desplegar   fusiona y limpia, pero no toca producción." ;;
    -*) morir "Opción desconocida: $1" ;;
    *)  [ -z "$rama_arg" ] || morir "Sobra un argumento: $1"; rama_arg="$1" ;;
  esac
  shift
done

resolver_repo "$rama_arg" cerrar
exigir_estar_fuera
exigir_arbol_limpio "$forzar"

# ── Fusionar ────────────────────────────────────────────────────────────────
fusionada_ahora=0
if [ "$solo_limpiar" != 1 ]; then
  empujar_y_abrir_pr

  case "$estado" in
    CLOSED) morir "La PR #$numero está cerrada sin fusionar. Decide tú qué hacer con ella." ;;
    MERGED) paso "la PR #$numero ya estaba fusionada" ;;
    *)
      paso "compruebo el CI de la PR #$numero"
      ci=0; esperar_ci --vigilar || ci=$?
      case "$ci" in
        1) aviso "" "No fusiono nada."; exit 1 ;;
        2) aviso "" \
             "No la fusiono." \
             "" \
             "Mírala tú y, cuando la fusiones, vuelve con:" \
             "    cerrar-rama.sh $rama --solo-limpiar"
           exit 0 ;;
      esac

      paso "verde: fusiono la PR #$numero"
      $GH pr merge "$numero" --merge >&2 ||
        morir "" "GitHub no ha podido fusionar la PR #$numero. No he borrado nada."
      fusionada_ahora=1 ;;
  esac
fi

# ── Producción ──────────────────────────────────────────────────────────────
# Solo si el repositorio sigue el contrato de cmdlo: publica imágenes con
# `release.yml` y trae su `ops/deploy/deploy.sh`. Los demás no tienen a dónde ir.
if [ "$fusionada_ahora" = 1 ] && [ "$sin_desplegar" != 1 ]; then
  if [ -x "$DESPLEGAR" ] && [ -f "$raiz/ops/deploy/deploy.sh" ] &&
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
if $DOCKER compose -p "$proyecto" ps -q >/dev/null 2>&1 &&
   [ -n "$($DOCKER compose -p "$proyecto" ps -aq 2>/dev/null)" ]; then
  paso "tumbo la pila $proyecto y sus volúmenes de copia"
  $DOCKER compose -p "$proyecto" down --volumes >&2 || true
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

aviso "" "Cerrada '$rama': sin pila, sin worktree, sin rama local y sin rama remota."
