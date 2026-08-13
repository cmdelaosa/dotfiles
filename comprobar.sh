#!/usr/bin/env bash
# ¿Sigue mandando este repositorio sobre ~/.claude? Sale 0 si sí, 1 si hay algo que
# mirar, y en ese caso lo dice en una línea por problema.
#
# No es paranoia: `settings.json` lo reescribe la propia app (el modelo, el estilo de
# salida, los plugins), y una escritura que borra y crea el fichero **se lleva el
# enlace por delante**. A partir de ahí la máquina y el repositorio son dos cosas
# distintas y nada lo anuncia — que es exactamente el problema por el que existe
# este repositorio.
set -uo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
destino="${CLAUDE_DIR:-$HOME/.claude}"
problemas=0

for x in "$repo"/claude/*; do
  nombre="$(basename "$x")"
  enlace="${destino}/${nombre}"
  if [[ ! -L "$enlace" ]]; then
    if [[ -e "$enlace" ]]; then
      echo "~/.claude/${nombre} ya no es un enlace: alguien (o la app) lo reescribió, y el repositorio no manda sobre él."
    else
      echo "~/.claude/${nombre} no existe. Lanza ${repo}/instalar.sh"
    fi
    problemas=$((problemas + 1))
  elif [[ "$(readlink "$enlace")" != "$x" ]]; then
    echo "~/.claude/${nombre} apunta a $(readlink "$enlace"), no a este repositorio."
    problemas=$((problemas + 1))
  fi
done

sucio="$(git -C "$repo" status --porcelain 2>/dev/null)"
if [[ -n "$sucio" ]]; then
  echo "El repositorio tiene cambios sin commitear ($(printf '%s\n' "$sucio" | wc -l | tr -d ' ') ficheros): la máquina va por delante de su historia."
  problemas=$((problemas + 1))
fi

sin_subir="$(git -C "$repo" log --oneline @{u}..HEAD 2>/dev/null | wc -l | tr -d ' ')"
if [[ "${sin_subir:-0}" -gt 0 ]]; then
  echo "Hay ${sin_subir} commit(s) sin subir en $(basename "$repo")."
  problemas=$((problemas + 1))
fi

(( problemas == 0 )) && echo "Todo en orden: ~/.claude lo manda ${repo}."
exit $(( problemas > 0 ))
