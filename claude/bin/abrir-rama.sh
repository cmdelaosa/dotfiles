#!/bin/bash
# Abre la rama Y su worktree de una vez, que es el único sitio donde se trabaja.
#
# Existe por lo que pasó en welzy el 13-08-2026: tres sesiones de Claude a la vez
# en la raíz del repositorio. Una movió HEAD por debajo de otra, el WIP de una
# acabó dentro de la PR de la otra (`5b727d2 wip: punto seguro (activity log)`,
# hoy en la historia de main dentro de la PR #100) y un `commit` fue a parar
# directamente a main. Nadie decidió saltarse el worktree: es que abrirlo era un
# paso manual, y los pasos manuales se olvidan. Este script lo vuelve el camino
# corto.
#
# Lo que fija, que a mano salía mal:
#   - el nombre del worktree se DERIVA de la rama (wt<rama>). No se inventa, y no
#     se acepta el que inventa el harness (`sleepy-pare-10a9f6`): con cuatro
#     abiertos no hay forma de saber cuál tiene qué sin entrar en cada uno.
#   - la rama sale de `origin/<principal>` recién traído, NO del HEAD local, que
#     puede estar diez commits atrás o a medias de otra cosa. Es la diferencia
#     entre una PR con tu cambio y una PR con tu cambio más lo que arrastrabas.
#   - se niega antes de tocar nada si la rama o el worktree ya existen, en vez de
#     dejar el repositorio a medio abrir.
#
# Imprime en la salida estándar UNA línea: la ruta del worktree. Todo lo demás va
# a stderr, para que quien lo llame pueda hacer `cd "$(abrir-rama.sh x)"`.
set -Eeuo pipefail

morir() { printf '%s\n' "$@" >&2; exit 1; }
aviso() { printf '%s\n' "$@" >&2; }

rama="${1:-}"
[ -n "$rama" ] || morir "Uso: abrir-rama.sh <nombre-de-rama>" \
  "" \
  "El nombre dice qué hay dentro: 'retenciones-como-gasto', no 'fix' ni 'wip'."

git rev-parse --git-dir >/dev/null 2>&1 || morir "Aquí no hay ningún repositorio git."

# La raíz de verdad, no el worktree desde el que se llame: `worktree list` da
# siempre el principal el primero. `substr` y no `$2` porque una ruta puede
# llevar espacios.
raiz=$(git worktree list --porcelain | awk '$1 == "worktree" { print substr($0, 10); exit }')
[ -n "$raiz" ] || morir "No consigo averiguar la raíz del repositorio."

case "$rama" in
  main | master)
    morir "'$rama' es la rama principal. Justo de eso va todo esto." ;;
esac

# El nombre que inventa el harness: dos palabras y seis dígitos hexadecimales.
if printf '%s' "$rama" | grep -qE '^[a-z]+-[a-z]+-[0-9a-f]{6}$'; then
  morir "'$rama' es un nombre inventado por el harness, no dice qué hay dentro." \
    "" \
    "Ponle uno que se lea: 'arreglar-el-activity-log', 'retenciones-como-gasto'."
fi

git check-ref-format --branch "$rama" >/dev/null 2>&1 ||
  morir "'$rama' no es un nombre de rama válido para git."

if git -C "$raiz" show-ref --quiet --verify "refs/heads/$rama"; then
  morir "La rama '$rama' ya existe." \
    "" \
    "Si es la que quieres continuar, entra en su worktree:" \
    "    git -C $raiz worktree list"
fi

destino="$raiz/.claude/worktrees/wt$rama"
[ -e "$destino" ] && morir "Ya hay algo en $destino."

# Un worktree dentro del repositorio que no esté ignorado ensucia el `status` de
# todas las ramas, y acaba commiteado por accidente.
git -C "$raiz" check-ignore -q .claude/worktrees 2>/dev/null ||
  aviso "OJO: '.claude/worktrees/' no está en el .gitignore de este repositorio." \
        "     Añádelo, o el worktree saldrá como fichero sin seguir."

# De dónde sale la rama. Sin remoto (repositorio recién creado) se usa HEAD, que
# es lo único que hay.
base=HEAD
if git -C "$raiz" remote get-url origin >/dev/null 2>&1; then
  git -C "$raiz" fetch origin --quiet --prune
  principal=$(git -C "$raiz" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
  principal=${principal#origin/}
  [ -n "$principal" ] || principal=main
  if git -C "$raiz" rev-parse --verify --quiet "origin/$principal" >/dev/null; then
    base="origin/$principal"
  fi
fi

git -C "$raiz" worktree add "$destino" -b "$rama" "$base" >&2

aviso "" \
      "Rama '$rama' abierta desde $base." \
      "Trabaja aquí — y solo aquí:"
printf '%s\n' "$destino"
