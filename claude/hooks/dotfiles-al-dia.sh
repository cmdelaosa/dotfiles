#!/bin/bash
# SessionStart — dice si ~/.claude ha dejado de venir del repositorio de dotfiles.
# Calla cuando todo está en orden, que es casi siempre.
#
# Existe porque el modo de fallo de esto es mudo: la app reescribe `settings.json`
# cuando cambias de modelo o de estilo, y una escritura que borra y crea el fichero
# se lleva el enlace. Desde ese momento el repositorio tiene una copia vieja y nadie
# se entera hasta que alguien busca un diff que no existe.
#
# Nunca bloquea nada: sale 0 pase lo que pase.
set -uo pipefail
cat >/dev/null

comprobar="${DOTFILES_REPO:-$HOME/Projects/dotfiles}/comprobar.sh"
[ -x "$comprobar" ] || exit 0

salida="$("$comprobar" 2>/dev/null)" || {
  echo "Los dotfiles y la máquina no coinciden:"
  printf '%s\n' "$salida" | sed 's/^/  /'
  echo "  (arreglo: ${DOTFILES_REPO:-$HOME/Projects/dotfiles}/instalar.sh, o commitea lo que haya cambiado)"
}
exit 0
