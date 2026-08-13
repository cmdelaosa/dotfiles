#!/usr/bin/env bash
# Deja ~/.claude apuntando a este repositorio. Idempotente: se puede lanzar mil
# veces. Lo que ya esté bien enlazado no se toca; lo que sea un fichero de verdad
# se aparta con fecha antes de enlazar, nunca se pisa.
set -Eeuo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
destino="${CLAUDE_DIR:-$HOME/.claude}"
sello="$(date +%Y%m%d-%H%M%S)"

[[ -d "$destino" ]] || { echo "No existe ${destino}. ¿Está Claude Code instalado?" >&2; exit 1; }

hubo_copia=0
for x in "$repo"/claude/*; do
  nombre="$(basename "$x")"
  enlace="${destino}/${nombre}"

  if [[ -L "$enlace" ]]; then
    if [[ "$(readlink "$enlace")" == "$x" ]]; then
      echo "  ya enlazado   ${nombre}"
      continue
    fi
    echo "  reenlazo      ${nombre}  (apuntaba a $(readlink "$enlace"))"
    rm "$enlace"
  elif [[ -e "$enlace" ]]; then
    # Aquí es donde se pierde configuración si uno se confía: lo que hay en la
    # máquina puede ser más nuevo que lo del repositorio.
    mv "$enlace" "${enlace}.antes-de-dotfiles-${sello}"
    echo "  aparto        ${nombre}  → ${nombre}.antes-de-dotfiles-${sello}"
    hubo_copia=1
  fi

  ln -s "$x" "$enlace"
  [[ -L "$enlace" ]] && echo "  enlazado      ${nombre}"
done

if (( hubo_copia )); then
  cat <<AVISO

Se apartó algo. Compara antes de borrarlo, que puede ser más nuevo que el repo:

    diff -ru ${destino}/<algo>.antes-de-dotfiles-${sello} ${destino}/<algo>
AVISO
fi

echo
echo "Listo. Comprueba con: ${repo}/comprobar.sh"
