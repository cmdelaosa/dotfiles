#!/bin/bash
# Deja escrito que el diff de esta rama ya ha pasado por el revisor, que es lo
# que `probar-rama.sh` mira antes de dejar empujar.
#
# La marca es el SHA de HEAD, así que caduca sola: en cuanto haya un commit más,
# la rama ya no es la que se revisó y el freno vuelve a saltar. Vive en el
# directorio git del worktree —no se commitea, no viaja a nadie— y se va con el
# worktree cuando `cerrar-rama.sh` lo quita.
#
# Lo normal es no lanzarlo a mano: lo hace la skill `probar` después de aplicar
# lo que el revisor haya dicho. A mano vale para una revisión hecha fuera de
# aquí; decir que algo está revisado sin haberlo leído es mentirle al freno.
set -Eeuo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib-ramas.sh"

rama_arg=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help)
      morir "Uso: marcar-revisado.sh [<rama>]" \
        "" \
        "  <rama>  la revisada. Por defecto, la del directorio actual." ;;
    -*) morir "Opción desconocida: $1" ;;
    *)  [ -z "$rama_arg" ] || morir "Sobra un argumento: $1"; rama_arg="$1" ;;
  esac
  shift
done

resolver_repo "$rama_arg" marcar
[ -n "$ruta_wt" ] || morir "La rama '$rama' no tiene worktree." \
  "Ábrelo con: abrir-rama.sh $rama"

marca=$(ruta_marca_revision) || morir "No encuentro el directorio git de $ruta_wt."
cabeza=$(git -C "$ruta_wt" rev-parse HEAD)
printf '%s' "$cabeza" > "$marca"

aviso "Revisada: $rama en ${cabeza:0:7}." \
      "Vale hasta el próximo commit; después hay que volver a revisar."
