#!/bin/bash
# Dice de qué tramo es el diff de una rama y, por tanto, qué revisión pide.
#
# Existe porque hasta el 17-08-2026 la cadena revisaba a `max` todas las ramas,
# tocaran veinte líneas o dos mil, y eso es lo que la hacía lenta y cara. La
# escalera la elige este guión leyendo el diff —no el agente, que es quien acaba
# de decidir que lo suyo es sencillo—, igual que `--solo-md` no se cree a quien
# lo escribe:
#
#   solo-md    ni un fichero fuera de .md         → ninguna revisión
#   trivial    ≤30 líneas, sin ficheros nuevos    → low
#   normal     lo demás                           → high
#   sensible   ruta delicada, o >600 líneas       → max
#
# Qué es «delicado» lo dice cada repositorio en `.claude/rutas-sensibles`, una
# glob por línea, y se lee la copia de la raíz —o sea la de `main`—: leerla de
# la rama dejaría que una rama se rebajara el listón borrando de la lista lo que
# va a tocar.
#
# Lo llaman la skill `probar`, para saber con qué nivel lanzar `/code-review`, y
# `probar-rama.sh`, para negarse a empujar un diff revisado por debajo.
set -Eeuo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib-ramas.sh"

rama_arg=""; solo_nivel=0
while [ $# -gt 0 ]; do
  case "$1" in
    --nivel) solo_nivel=1 ;;
    -h | --help)
      morir "Uso: clasificar-diff.sh [<rama>] [--nivel]" \
        "" \
        "  <rama>    la que se clasifica. Por defecto, la del directorio actual." \
        "  --nivel   imprime solo el nivel, para meterlo en otra orden." \
        "" \
        "Sin --nivel imprime «<tramo> <nivel>» y explica por qué." ;;
    -*) morir "Opción desconocida: $1" ;;
    *)  [ -z "$rama_arg" ] || morir "Sobra un argumento: $1"; rama_arg="$1" ;;
  esac
  shift
done

resolver_repo "$rama_arg" clasificar

clasificar_diff ||
  morir "No he podido comparar '$rama' con su base, así que no sé de qué tramo es." \
        "Un freno que no sabe responder tiene que decir que no."

if [ "$solo_nivel" = 1 ]; then
  printf '%s\n' "$nivel"
  exit 0
fi

printf '%s %s\n' "$tramo" "$nivel"

# El porqué va por stderr, no por stdout: quien llame a esto dentro de `$( )`
# quiere el veredicto a secas, y quien lo lance a mano quiere la explicación.
case "$nivel" in
  ninguno) aviso "  $motivo" "  No hay revisión que hacer." ;;
  *)       aviso "  $motivo" \
                 "  Revisa:  /code-review $rama $nivel --fix" \
                 "  Marca:   marcar-revisado.sh $rama --nivel $nivel" ;;
esac
