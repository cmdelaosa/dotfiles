#!/bin/bash
# Qué le queda por revisar a esta rama: todo, o solo lo nuevo desde la marca.
#
# Existe porque hasta hoy la marca de revisión solo sabía decir sí o no, y
# cualquier commit posterior la tiraba entera: se volvía a leer la rama
# COMPLETA, palabra por palabra, para juzgar veinte líneas nuevas. Medido en
# erp entre el 10 y el 19 de agosto de 2026: de las 24 ramas con más de una
# ronda de CI, 19 pasaron dos o más veces por el revisor, y el 53 % de las
# líneas que leyó la segunda vez no habían cambiado desde la primera. Solo 4 de
# esas ramas venían de un CI en rojo — o sea que esto no va de arreglar el CI,
# va de que **seguir trabajando en una rama revisada no debería costar releerla
# entera**.
#
# Lo que imprime, en una línea de dos campos, para meterlo en otra orden:
#
#   nada  <nivel>   la marca es de este mismo HEAD: no hay nada que revisar
#   todo  <nivel>   hay que leer la rama entera contra el principal
#   <sha> <nivel>   basta con leer <sha>..HEAD, que es lo único sin revisar
#
# **El nivel NO se rebaja nunca**: es el que pide el diff de la rama entera,
# aunque lo nuevo sean tres líneas. Clasificar el delta aparte se pensó y se
# descartó — la marca pasaría a decir «lo viejo a max y lo nuevo a low», que es
# una afirmación compuesta y el tipo de marca que acaba mintiendo.
#
# Se cae a `todo` en cuanto hay una sola duda, y son cuatro:
#
#   - No hay marca. Nadie ha leído nada.
#   - La marca no lleva nivel (formato de antes del 17-08-2026): no se sabe con
#     qué rigor se leyó, así que no se hereda nada.
#   - La marca **no es antepasada de HEAD**: hubo rebase, `amend` o `reset`, y
#     el código revisado ya no es el que hay. Un rango contra un commit que se
#     salió de la historia no significa nada.
#   - El diff pide ahora **más nivel** del que dice la marca. Pasa solo con
#     crecer: una rama de 300 líneas revisada a `high` que llega a 700 es
#     `sensible`, y lo viejo nunca se leyó con ese rigor.
#
# Lo llama la skill `probar`. `probar-rama.sh` no lo usa: su freno sigue siendo
# el de siempre —marca puesta, de ESTE HEAD y con nivel suficiente—, y este
# guión no lo relaja, solo dice por dónde empezar para llegar a él.
set -Eeuo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib-ramas.sh"

rama_arg=""; solo_ambito=0
while [ $# -gt 0 ]; do
  case "$1" in
    --ambito) solo_ambito=1 ;;
    -h | --help)
      morir "Uso: revision-pendiente.sh [<rama>] [--ambito]" \
        "" \
        "  <rama>     la que se mira. Por defecto, la del directorio actual." \
        "  --ambito   imprime solo el primer campo, para meterlo en otra orden." \
        "" \
        "Imprime «<ámbito> <nivel>» y explica por qué:" \
        "  nada <nivel>    la marca es de este HEAD; no hay nada que revisar" \
        "  todo <nivel>    hay que leer la rama entera" \
        "  <sha> <nivel>   basta con leer <sha>..HEAD" ;;
    -*) morir "Opción desconocida: $1" ;;
    *)  [ -z "$rama_arg" ] || morir "Sobra un argumento: $1"; rama_arg="$1" ;;
  esac
  shift
done

resolver_repo "$rama_arg" mirar
[ -n "$ruta_wt" ] || morir "La rama '$rama' no tiene worktree." \
  "Ábrelo con: abrir-rama.sh $rama"

# El nivel lo pide siempre el diff entero, esté como esté la marca.
clasificar_diff ||
  morir "No he podido clasificar el diff de '$rama'," \
        "así que no sé qué revisión pide. No me invento el ámbito."

# El tramo de solo prosa no pasa por el revisor, y decir «todo» aquí mandaría a
# leer markdown a esfuerzo máximo.
if [ "$nivel" = ninguno ]; then
  ambito=nada
  motivo_ambito="$motivo — no hay revisión que hacer"
else
  marca=$(ruta_marca_revision) ||
    morir "No encuentro el directorio git de $ruta_wt."
  cabeza=$(git -C "$ruta_wt" rev-parse HEAD)
  guardado=$(cat "$marca" 2>/dev/null || true)
  sha_revisado=${guardado%% *}
  nivel_revisado=${guardado#* }
  [ "$nivel_revisado" != "$guardado" ] || nivel_revisado=""

  # Los dos órdenes, antes de la escalera de casos. `|| tiene=-1` y no a pelo:
  # un nivel que no está en la escalera —una marca escrita a mano, un fichero a
  # medio escribir— vale menos que el más bajo, y así el caso cae a `todo` en
  # vez de reventar el guión con `set -e`.
  tiene=$(orden_de_nivel "$nivel_revisado") || tiene=-1
  pide=$(orden_de_nivel "$nivel")

  if [ -z "$sha_revisado" ]; then
    ambito=todo
    motivo_ambito="no hay marca: no ha leído esto nadie"
  elif [ -z "$nivel_revisado" ]; then
    ambito=todo
    motivo_ambito="la marca no dice con qué nivel se revisó (formato viejo)"
  elif [ "$sha_revisado" = "$cabeza" ]; then
    ambito=nada
    motivo_ambito="la marca ya es de ${cabeza:0:7}, revisada a '$nivel_revisado'"
  elif ! git -C "$ruta_wt" merge-base --is-ancestor "$sha_revisado" "$cabeza" 2>/dev/null; then
    ambito=todo
    motivo_ambito="la marca (${sha_revisado:0:7}) no es antepasada de ${cabeza:0:7}: rebase, amend o reset"
  elif [ "$tiene" -lt "$pide" ]; then
    ambito=todo
    motivo_ambito="lo revisado se leyó a '$nivel_revisado' y ahora el diff pide '$nivel': $tramo"
  else
    ambito="$sha_revisado"
    motivo_ambito="revisada a '$nivel_revisado' hasta ${sha_revisado:0:7}; falta de ahí a ${cabeza:0:7}"
  fi
fi

if [ "$solo_ambito" = 1 ]; then
  printf '%s\n' "$ambito"
  exit 0
fi

printf '%s %s\n' "$ambito" "$nivel"

# El porqué por stderr, como en clasificar-diff.sh: quien lo mete en un `$( )`
# quiere el veredicto a secas, y quien lo lanza a mano quiere la explicación.
case "$ambito" in
  nada) aviso "  $motivo_ambito" ;;
  todo) aviso "  $motivo_ambito" \
              "  Revisa la rama entera:  /code-review $rama $nivel --fix" \
              "  Marca:                  marcar-revisado.sh $rama --nivel $nivel" ;;
  *)    aviso "  $motivo_ambito" \
              "  Revisa solo lo nuevo:   /code-review $ambito..HEAD $nivel --fix" \
              "  Marca:                  marcar-revisado.sh $rama --nivel $nivel" ;;
esac
