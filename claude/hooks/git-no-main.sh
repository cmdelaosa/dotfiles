#!/bin/bash
# PreToolUse(Bash) — impide commit, merge y push directos sobre main/master.
#
# Existe porque la protección de rama de GitHub pide plan Pro o repo público, y
# los repos de Carlos son privados en el plan gratuito: no hay nada del lado del
# servidor que pare un push directo a main.
#
# Escotilla, cuando de verdad haga falta:
#   CLAUDE_ALLOW_MAIN=1 git push origin main
# o exportarla para toda la sesión.

set -uo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

# Solo las tres órdenes que mueven la rama. El subcomando tiene que terminar ahí:
# `git merge-base` es de solo lectura y con `*"git merge"*` lo bloqueaba también.
printf '%s' "$cmd" | grep -qE '(^|[;&|(]|[[:space:]])git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?(-[^[:space:]]+[[:space:]]+)*(commit|merge|push)([[:space:]]|$)' || exit 0

# Sincronizar main con su remoto tras fusionar una PR no es "trabajar sobre
# main": --ff-only solo adelanta el puntero y no puede crear un commit. Sin esta
# excepción el hook se dispara cada vez que se vuelve de una PR.
case "$cmd" in *"--ff-only"*) exit 0 ;; esac

# Escotilla: exportada en el entorno, o escrita delante del comando.
[ "${CLAUDE_ALLOW_MAIN:-}" = "1" ] && exit 0
case "$cmd" in *CLAUDE_ALLOW_MAIN=1*) exit 0 ;; esac

# Fuera de un repo git no hay nada que proteger.
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || exit 0
case "$branch" in
  main | master) ;;
  *) exit 0 ;;
esac

cat >&2 <<EOF
Estás en '$branch'. Los cambios no van sobre main directamente.

  1. git checkout -b <nombre-que-diga-qué-hay-dentro>
  2. commitea ahí
  3. gh pr create   — el CI se corre en la PR
  4. fusiona a main desde la PR, ya en verde

Si de verdad hace falta tocar main, díselo a Carlos y que lo apruebe él:
  CLAUDE_ALLOW_MAIN=1 $cmd
EOF
exit 2
