#!/bin/bash
# Cierra una rama: espera al CI, fusiona su PR si está verde, y limpia worktree,
# rama local y rama remota. Se lanza DESDE LA RAÍZ, nunca desde dentro del
# worktree que va a borrar.
#
# Por qué existe, y por qué el orden no es cosmético. `gh pr merge
# --delete-branch` parece hacer todo esto solo, y no: fusiona en GitHub y luego
# falla en local, con la rama ya sin PR y todavía viva. Los dos fallos, medidos:
#
#     error: cannot delete branch 'la-rama' used by worktree at '…/wtla-rama'
#     fatal: 'main' is already used by worktree at '…/wtmain'
#
# El segundo ni siquiera avisa de que quedó a medias. Por eso aquí el borrado va
# a mano y en el único orden que funciona: worktree fuera, rama local fuera, rama
# remota fuera. Y por eso cada orden de git va suelta: encadenarlas con `&&`
# tampoco es lo que quiere el hook `git-no-main.sh`, que mira la línea entera.
#
# Lo irreversible tiene freno. Con el árbol sucio no fusiona ni borra: enseña qué
# ficheros son y para. `--forzar` lo salta, y hay que escribirlo a propósito.
#
# En un repositorio sin CI (hoy, dotfiles) NO fusiona: abre la PR, dice que ahí
# no hay checks y para. «Sin checks» no es un aprobado.
set -Eeuo pipefail

# Para poder falsear GitHub en la matriz de pruebas.
GH="${GH:-gh}"

morir() { printf '%s\n' "$@" >&2; exit 1; }
aviso() { printf '%s\n' "$@" >&2; }
paso()  { printf '  %s\n' "$*" >&2; }

rama=""; forzar=0; solo_limpiar=0
while [ $# -gt 0 ]; do
  case "$1" in
    --forzar)       forzar=1 ;;
    --solo-limpiar) solo_limpiar=1 ;;
    -h | --help)
      morir "Uso: cerrar-rama.sh [<rama>] [--forzar] [--solo-limpiar]" \
        "" \
        "  <rama>           la que se cierra. Por defecto, la del directorio actual." \
        "  --forzar         cierra aunque haya cambios sin guardar. Los tira." \
        "  --solo-limpiar   no fusiona: da por hecho que la PR ya está fusionada" \
        "                   y solo quita worktree, rama local y rama remota." ;;
    -*) morir "Opción desconocida: $1" ;;
    *)  [ -z "$rama" ] || morir "Sobra un argumento: $1"; rama="$1" ;;
  esac
  shift
done

git rev-parse --git-dir >/dev/null 2>&1 || morir "Aquí no hay ningún repositorio git."
raiz=$(git worktree list --porcelain | awk '$1 == "worktree" { print substr($0, 10); exit }')
[ -n "$raiz" ] || morir "No consigo averiguar la raíz del repositorio."

[ -n "$rama" ] || rama=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
[ -n "$rama" ] && [ "$rama" != HEAD ] || morir "No sé qué rama cerrar. Pásala como argumento."

case "$rama" in
  main | master)
    morir "'$rama' es la rama principal, y no se cierra." ;;
esac

git -C "$raiz" show-ref --quiet --verify "refs/heads/$rama" ||
  morir "Aquí no hay ninguna rama '$rama'."

principal=$(git -C "$raiz" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
principal=${principal#origin/}
[ -n "$principal" ] || principal=main

# El worktree que tiene puesta esa rama, si es que hay alguno.
ruta_wt=$(git -C "$raiz" worktree list --porcelain | awk -v r="refs/heads/$rama" '
  $1 == "worktree" { w = substr($0, 10) }
  $1 == "branch" && $2 == r { print w; exit }')

# Borrar el directorio desde el que se está ejecutando deja el shell en un sitio
# que ya no existe y el worktree a medio quitar.
if [ -n "$ruta_wt" ]; then
  actual=$(pwd -P)
  wt_real=$(cd "$ruta_wt" 2>/dev/null && pwd -P || printf '%s' "$ruta_wt")
  case "$actual" in
    "$wt_real" | "$wt_real"/*)
      morir "Estás dentro del worktree que hay que borrar ($wt_real)." \
        "" \
        "Sal primero:  cd $raiz" \
        "(en Claude Code: ExitWorktree con action \"keep\")" ;;
  esac
fi

# ── El freno ────────────────────────────────────────────────────────────────
# Lo único de todo esto que destruye trabajo es el borrado. Se mira ANTES de
# fusionar, porque una PR abierta con el árbol sucio ya sale incompleta.
if [ -n "$ruta_wt" ]; then
  sucio=$(git -C "$ruta_wt" status --porcelain)
  if [ -n "$sucio" ]; then
    if [ "$forzar" != 1 ]; then
      aviso "El worktree tiene cambios sin guardar:" ""
      printf '%s\n' "$sucio" | sed 's/^/    /' >&2
      morir "" \
        "No fusiono ni borro nada. Commitéalos, o repítelo con --forzar si sobran."
    fi
    aviso "OJO: --forzar; se tiran estos cambios sin guardar:"
    printf '%s\n' "$sucio" | sed 's/^/    /' >&2
  fi
fi

hubo_remoto=0
git -C "$raiz" remote get-url origin >/dev/null 2>&1 && hubo_remoto=1

# ── Empujar, PR, CI y fusión ────────────────────────────────────────────────
if [ "$solo_limpiar" != 1 ]; then
  [ "$hubo_remoto" = 1 ] || morir "Este repositorio no tiene remoto: no hay PR que fusionar." \
    "Usa --solo-limpiar si lo que quieres es quitar la rama y su worktree."

  git -C "$raiz" fetch origin --quiet --prune

  pendientes=$(git -C "$raiz" rev-list --count "origin/$principal..$rama")
  [ "$pendientes" -gt 0 ] ||
    morir "La rama '$rama' no tiene ningún commit que origin/$principal no tenga." \
      "No hay nada que fusionar. Con --solo-limpiar la quito y ya."

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

  case "$estado" in
    CLOSED) morir "La PR #$numero está cerrada sin fusionar. Decide tú qué hacer con ella." ;;
    MERGED) paso "la PR #$numero ya estaba fusionada" ;;
    *)
      paso "espero al CI de la PR #$numero"
      codigo=0
      salida=$($GH pr checks "$rama" --watch --fail-fast --json bucket,name,link 2>/dev/null) || codigo=$?

      # «No hay checks» tiene dos causas MUY distintas y hasta el 13-08-2026 las
      # dos daban el mismo mensaje —«este repositorio no tiene CI»—, que en welzy
      # es sencillamente falso: tiene `ci.yml`, y lo que pasa es que su
      # `paths-ignore` deja fuera las PRs de solo markdown a propósito. Un mensaje
      # que miente sobre por qué no fusiona es peor que no fusionar.
      if grep -qE '^[[:space:]]*pull_request(_target)?[[:space:]]*:' "$raiz"/.github/workflows/*.y*ml 2>/dev/null; then
        hay_workflows=1
      else
        hay_workflows=0
      fi

      # Y si los hay, pueden tardar unos segundos en registrarse: `gh pr checks`
      # sale en cuanto ve que no hay ninguno, sin esperar a que aparezcan, así
      # que una PR recién abierta puede parecer sin CI durante un instante.
      if [ "$hay_workflows" = 1 ]; then
        espera=0
        while ! printf '%s' "$salida" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; do
          [ "$espera" -ge "${ESPERA_CHECKS:-60}" ] && break
          sleep 5
          espera=$((espera + 5))
          codigo=0
          salida=$($GH pr checks "$rama" --watch --fail-fast --json bucket,name,link 2>/dev/null) || codigo=$?
        done
      fi

      if ! printf '%s' "$salida" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then
        if [ "$hay_workflows" = 1 ]; then
          aviso "" \
            "La PR #$numero está abierta. Este repositorio SÍ tiene CI, pero esta PR" \
            "no ha disparado ningún check: lo normal es un \`paths-ignore\` que la deja" \
            "fuera a propósito —welzy hace eso con las PRs de solo documentación—, y" \
            "lo que no es normal es que \`ci.yml\` esté roto y no cree ejecuciones." \
            "" \
            "Sea lo que sea, «sin checks» no es un aprobado: no la fusiono."
        else
          aviso "" \
            "La PR #$numero está abierta, pero este repositorio no tiene CI." \
            "«Sin checks» no es un aprobado: no la fusiono."
        fi
        aviso "" \
          "Mírala tú y, cuando la fusiones, vuelve con:" \
          "    cerrar-rama.sh $rama --solo-limpiar"
        exit 0
      fi

      malos=$(printf '%s' "$salida" |
        jq -r '.[] | select(.bucket == "fail" or .bucket == "cancel") | "    \(.name)  \(.link)"')
      if [ -n "$malos" ]; then
        aviso "" "El CI no está verde. No fusiono nada:" ""
        printf '%s\n' "$malos" >&2
        exit 1
      fi
      [ "$codigo" -eq 0 ] || morir "" "El CI terminó con código $codigo. No fusiono nada."

      paso "verde: fusiono la PR #$numero"
      $GH pr merge "$numero" --merge >&2 ||
        morir "" "GitHub no ha podido fusionar la PR #$numero. No he borrado nada." ;;
  esac
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
# tiene a medias, se avisa y no se toca — mover HEAD por debajo de alguien es
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

aviso "" "Cerrada '$rama': sin worktree, sin rama local y sin rama remota."
