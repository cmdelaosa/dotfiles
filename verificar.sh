#!/usr/bin/env bash
# Todo lo que se puede juzgar de un cambio de este repositorio sin salir de la
# máquina: la sintaxis de cada guión y las dos matrices de pruebas.
#
# Lo lanza `probar-rama.sh` antes de empujar, así que aquí va lo RÁPIDO. Si algo
# tarda minutos, su sitio es el CI: un freno que cuesta cinco minutos cada vez
# acaba con un `--sin-verificar` en cada llamada, y entonces no frena nada.
#
# `comprobar.sh` NO se llama desde aquí, a propósito. Juzga la INSTALACIÓN —que
# ~/.claude siga enlazado a este repositorio—, no el cambio, y desde cualquier
# worktree encuentra los enlaces apuntando a la raíz: fallaría en todas las
# ramas, siempre, diciendo la verdad sobre algo que no es lo que se prueba. Lo
# llama un hook de SessionStart, que es cuando esa pregunta sí toca.
set -uo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fallos=0

titulo() { printf '\n=== %s ===\n' "$1"; }

# Con `/bin/bash` a posta, el 3.2 de Apple, y no el 5.x de Homebrew: el 3.2 es
# quien ejecuta los hooks y acepta menos cosas. Un `case` dentro de `$( )` sin
# paréntesis de apertura en el patrón se lo traga el 5.x y lo rechaza el 3.2 —y
# un hook PreToolUse con un error de sintaxis sale con 2, que significa
# «bloqueado»: una errata aquí bloquea todo git en todas las sesiones.
titulo "sintaxis de todos los .sh (bash 3.2, el de los hooks)"
mirados=0
while IFS= read -r guion; do
  mirados=$((mirados + 1))
  if salida=$(/bin/bash -n "$guion" 2>&1); then
    printf '  ok      %s\n' "${guion#"$repo"/}"
  else
    printf '  FALLO   %s\n' "${guion#"$repo"/}"
    printf '%s\n' "$salida" | sed 's/^/          /'
    fallos=$((fallos + 1))
  fi
# La exclusión de los worktrees va ANCLADA a `$repo` y no como `*/worktrees/*`:
# el worktree desde el que se lanza esto vive él mismo dentro de
# `…/.claude/worktrees/wtloquesea`, así que el patrón suelto se excluía a sí
# mismo y la lista salía vacía — cero ficheros comprobados, y ni un FALLO que lo
# contara. Un chequeo que no mira nada no se distingue de uno que va bien.
done < <(find "$repo" -name '*.sh' \
           -not -path '*/.git/*' \
           -not -path "$repo/.claude/worktrees/*" | sort)

# Y la lista vacía se cuenta como fallo, que es la forma que tuvo de aparecer:
# con el patrón mal, cero ficheros comprobados y un TODO BIEN idéntico al de
# verdad. Un cero aquí no es «todo correcto», es «no he mirado nada».
if [ "$mirados" -eq 0 ]; then
  printf '  FALLO   no he encontrado ni un .sh que mirar; el filtro del find está mal\n'
  fallos=$((fallos + 1))
fi

titulo "matriz de abrir/probar/cerrar-rama.sh"
"$repo/claude/bin/probar-ramas.sh" || fallos=$((fallos + 1))

# Las dos matrices de hooks ya prueban por defecto la copia de al lado, así que
# aquí no hace falta HOOK=: lanzando la de este worktree se juzga el hook de esta
# rama, que es lo que se está cambiando. HOOK= sigue sirviendo para la otra
# pregunta —«¿tiene la máquina lo que creo?»—, que no es la de un push.
titulo "matriz del hook git-no-main.sh"
"$repo/claude/hooks/probar-git-no-main.sh" || fallos=$((fallos + 1))

titulo "matriz del hook git-una-sesion-por-checkout.sh"
"$repo/claude/hooks/probar-git-una-sesion.sh" || fallos=$((fallos + 1))

echo
if [ "$fallos" -eq 0 ]; then
  echo "verificar.sh: TODO BIEN"
else
  echo "verificar.sh: $fallos comprobacion(es) en rojo"
  exit 1
fi
