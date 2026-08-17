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

rama_arg=""; nivel_dicho=""
while [ $# -gt 0 ]; do
  case "$1" in
    --nivel)
      shift
      [ $# -gt 0 ] || morir "--nivel se escribe con el nivel detrás."
      nivel_dicho="$1" ;;
    -h | --help)
      morir "Uso: marcar-revisado.sh [<rama>] --nivel <low|medium|high|max>" \
        "" \
        "  <rama>    la revisada. Por defecto, la del directorio actual." \
        "  --nivel   con qué nivel se ha revisado el diff." \
        "" \
        "El nivel se escribe, no se supone: probar-rama.sh compara el que pone" \
        "aquí con el que pide el diff, y se niega a empujar si es menor." \
        "Qué pide esta rama:  clasificar-diff.sh <rama>" ;;
    -*) morir "Opción desconocida: $1" ;;
    *)  [ -z "$rama_arg" ] || morir "Sobra un argumento: $1"; rama_arg="$1" ;;
  esac
  shift
done

resolver_repo "$rama_arg" marcar
[ -n "$ruta_wt" ] || morir "La rama '$rama' no tiene worktree." \
  "Ábrelo con: abrir-rama.sh $rama"

# El nivel es obligatorio *(17-08-2026)*. Podría ponerse solo —preguntándole al
# clasificador qué pedía— y sería justo lo contrario de un freno: la marca
# diría siempre que sí, porque se estaría escribiendo a sí misma. Que haya que
# teclearlo es lo que convierte la marca en una afirmación de alguien.
[ -n "$nivel_dicho" ] ||
  morir "Falta --nivel: con qué nivel se ha revisado esto." \
        "" \
        "  Qué pide esta rama:  clasificar-diff.sh $rama" \
        "  Y luego:             marcar-revisado.sh $rama --nivel <el que salga>"
orden_de_nivel "$nivel_dicho" >/dev/null ||
  morir "'$nivel_dicho' no es un nivel. Los que hay: $NIVELES_ORDEN."

marca=$(ruta_marca_revision) || morir "No encuentro el directorio git de $ruta_wt."
cabeza=$(git -C "$ruta_wt" rev-parse HEAD)
printf '%s %s' "$cabeza" "$nivel_dicho" > "$marca"

aviso "Revisada a '$nivel_dicho': $rama en ${cabeza:0:7}." \
      "Vale hasta el próximo commit; después hay que volver a revisar."
