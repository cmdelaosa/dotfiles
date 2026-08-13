#!/bin/bash
# PreToolUse(Bash) — impide commit, merge y push directos sobre main/master.
#
# Existe porque la protección de rama de GitHub pide plan Pro o repo público, y
# los repos de Carlos son privados en el plan gratuito: no hay nada del lado del
# servidor que pare un push directo a main.
#
# Deja pasar la LIMPIEZA de después de fusionar —traer main a su remoto y borrar
# la rama ya fusionada—, porque nada de eso mete trabajo en main y cobrar una
# escotilla por ello la convierte en rutina.
#
# Escotilla, cuando de verdad haga falta:
#   CLAUDE_ALLOW_MAIN=1 git push origin main
# o exportarla para toda la sesión.

set -uo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

# Los cuerpos de heredoc son TEXTO, no órdenes: un `gh pr create` cuyo cuerpo
# MENCIONA un empujón a main no empuja nada. Hasta el 2026-08-13 el hook leía la
# línea entera como una cadena y bloqueaba justo eso — la misma familia que el
# agujero de `--ff-only`, que casaba dentro de un mensaje de commit.
#
# La línea que ABRE el heredoc sí se conserva (ahí está la orden de verdad); se
# tira lo de dentro, hasta la marca de cierre.
#
# Precio conocido y aceptado: un `bash <<EOF` con git dentro deja de verse. Hay
# que escribirlo a propósito, y el falso positivo se pagaba a diario. Las comillas
# se escriben en octal (\047 \042) para no pelearse con el entrecomillado de awk.
orden=$(printf '%s\n' "$cmd" | awk '
  {
    if (dentro) { if ($0 ~ marca) dentro = 0; next }
    if (match($0, /<<-?[ \t]*[\047\042]?[A-Za-z_][A-Za-z0-9_]*[\047\042]?/)) {
      m = substr($0, RSTART, RLENGTH)
      sub(/^<<-?[ \t]*/, "", m)
      gsub(/[\047\042]/, "", m)
      marca = "^[ \t]*" m "[ \t]*$"
      dentro = 1
    }
    print
  }
')

# Solo las tres órdenes que mueven la rama. El subcomando tiene que terminar ahí:
# `git merge-base` es de solo lectura y con `*"git merge"*` lo bloqueaba también.
printf '%s' "$orden" | grep -qE '(^|[;&|(]|[[:space:]])git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?(-[^[:space:]]+[[:space:]]+)*(commit|merge|push)([[:space:]]|$)' || exit 0

# Espacios normalizados: las excepciones de abajo se comparan con la orden
# ENTERA, así que no pueden pelearse con el formato — pero tampoco se dejan
# colar encadenando (`git push origin main && git push origin --delete x`).
norm=$(printf '%s' "$orden" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')

# Y sin un `cd <ruta> &&` delante, que no cambia lo que git hace y es como se
# escribe la limpieza desde un directorio que no es el repo. Solo si va el
# PRIMERO y solo una vez: lo que venga detrás del git sigue contando, que es lo
# que impide colar `cd x && git push origin --delete r && git push origin main`.
sin_cd=$(printf '%s' "$norm" | sed -E 's#^cd ("[^"]*"|[^ ]+) *(&&|;) *##')

# Y sin el `-C <ruta>`, para que las excepciones valgan igual desde dentro del
# repo que desde fuera. A qué repo apunta se resuelve abajo, por separado.
sin_c=$(printf '%s' "$sin_cd" | sed -E 's#^git -C [^ ]+ #git #')

# Y sin la tubería final ni el `2>&1`: `… --delete rama | tail -2` es como
# escribe todo el mundo, y ni la tubería ni la redirección cambian lo que git
# hace. Pero solo se quita si detrás NO se menciona git — así
# `git push origin --delete rama | git push origin main` sigue sin encajar en
# ninguna excepción, que es lo que tiene que pasar.
cola=${sin_c#*|}
if [ "$cola" != "$sin_c" ]; then
  case "$cola" in
    *git*) ;;
    *) sin_c=${sin_c%%|*} ;;
  esac
fi
# El espacio sobrante va PRIMERO: al cortar por la tubería queda uno pegado
# detrás, y con él delante el `2>&1$` no casaba.
sin_c=$(printf '%s' "$sin_c" | sed -E 's/ +$//; s/ 2>&1$//; s/ +$//')

# Excepción 1 — sincronizar main con SU remoto tras fusionar una PR. Adelantar
# el puntero hasta lo que ya está en origin no es trabajar sobre main, y sin
# esto el hook se dispara cada vez que se vuelve de una PR.
#
# Ojo a lo que NO entra, que es la fisura que esto cierra: hasta el 2026-08-13
# valía cualquier orden que contuviera "--ff-only", así que
# `git merge --ff-only una-rama-local` pasaba y adelantaba main hasta commits
# que ninguna PR había juzgado. Por eso ahora la lista es cerrada y solo nombra
# el upstream.
case "$sin_c" in
  "git pull --ff-only" | \
  "git pull --ff-only origin main" | "git pull --ff-only origin master" | \
  "git pull origin main --ff-only" | "git pull origin master --ff-only" | \
  "git merge --ff-only origin/main" | "git merge --ff-only origin/master" | \
  "git merge --ff-only @{u}" | "git merge --ff-only @{upstream}")
    exit 0 ;;
esac

# Excepción 2 — borrar en el remoto la rama de una PR ya fusionada. Es limpieza,
# no un empujón sobre main: `git push origin --delete otra-rama` no toca main ni
# de lejos, pero el hook saltaba porque la orden empieza por `git push` y HEAD
# dice main. Eso obligaba a pedir la escotilla para cada limpieza, que es
# gastarla en lo que no importa — y una escotilla que se pide a diario deja de
# leerse.
#
# Las tres condiciones son el candado: la orden es SOLO ese push (sin encadenar),
# borra UNA rama, y esa rama no es main ni master. Borrar main en el remoto sigue
# necesitando la escotilla, que es como tiene que ser.
if [[ $sin_c =~ ^git\ push\ ([A-Za-z0-9._-]+)\ (--delete|-d)\ ([A-Za-z0-9._/-]+)$ ]]; then
  case "${BASH_REMATCH[3]}" in
    main | master) ;;
    *) exit 0 ;;
  esac
fi

# Escotilla: exportada en el entorno, o escrita delante del comando.
[ "${CLAUDE_ALLOW_MAIN:-}" = "1" ] && exit 0
case "$cmd" in *CLAUDE_ALLOW_MAIN=1*) exit 0 ;; esac

# La rama que importa es la del repo al que apunta la ORDEN, no la del directorio
# donde estoy. Hasta el 2026-08-13 esto leía el HEAD del cwd, y con `-C` fallaba
# por los dos lados: bloqueaba commitear en la rama de OTRO repo solo porque aquí
# hubiera un main, y —lo grave— dejaba pasar un `git -C otro-repo push origin
# main` de verdad con solo estar aquí en una rama cualquiera.
#
# Limitación conocida: con varias órdenes encadenadas se juzga la primera. Las
# dos excepciones de arriba ya exigen orden única, así que lo encadenado acaba
# bloqueado igual.
# Y `cd <ruta> && git …` apunta tan fuerte como `-C`. Hasta el 2026-08-13 esta
# forma NO se miraba, y era un agujero de verdad: con el directorio de trabajo
# fuera de un repo en main —el scratchpad, otro proyecto, un worktree en rama—
# un `cd <repo-en-main> && git commit` pasaba entero. Medido:
#
#     rc=0 PASA     cd /Users/cmo/Projects/welzy && git commit -m x
#     rc=2 BLOQUEA  git -C /Users/cmo/Projects/welzy commit -m x
#
# El hook hermano (git-una-sesion-por-checkout.sh) ya parseaba el `cd`; este, que
# es el que de verdad para los commits sobre main, no. Es la explicación más
# plausible de `f78d799`, un `wip:` commiteado directamente sobre el main de
# welzy el 13-08-2026 a las 09:35.
#
# El `cd` solo cuenta si aparece ANTES de la orden de git. Si no, un mensaje que
# lo mencione —`git commit -m "cd /otro-repo"`— elegiría el repo a juzgar, que es
# exactamente la familia del agujero de `--ff-only`: prosa que nombra una orden
# no es esa orden.
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] || cwd=$PWD
destino=$cwd

# Dónde empieza la orden de git, para mirar solo lo que va delante. awk casa por
# la izquierda, que es justo lo que hace falta y lo que `sed` con `.*` no da.
corte=$(printf '%s' "$norm" | awk '{
  if (match($0, /(^|[;&|[:space:]])git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?(-[^[:space:]]+[[:space:]]+)*(commit|merge|push)([[:space:]]|$)/))
    print RSTART - 1
  else
    print 0
}')
delante=${norm:0:corte}

# `-C` manda sobre el `cd`, que es lo que hace git.
apuntada=""
if [[ $norm =~ (^|[[:space:]])git[[:space:]]+-C[[:space:]]+([^[:space:]]+) ]]; then
  apuntada="${BASH_REMATCH[2]}"
elif [[ $delante =~ (^|[;&|[:space:]])cd[[:space:]]+([^[:space:]\;\&\|]+) ]]; then
  apuntada="${BASH_REMATCH[2]}"
fi

apuntada=${apuntada#\"}; apuntada=${apuntada%\"}
apuntada=${apuntada#\'}; apuntada=${apuntada%\'}
case "$apuntada" in
  ("") ;;
  ("~"/*) destino="${HOME}/${apuntada#\~/}" ;;
  (/*)    destino="$apuntada" ;;
  (*)     destino="${cwd}/${apuntada}" ;;
esac
# Una ruta que no existe no puede absolver: se vuelve al cwd, nunca a «nada».
[ -d "$destino" ] || destino="$cwd"

# Fuera de un repo git no hay nada que proteger.
branch=$(git -C "$destino" rev-parse --abbrev-ref HEAD 2>/dev/null) || exit 0
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

Limpiar después de fusionar SÍ pasa por aquí, no hace falta escotilla:
  git pull --ff-only                     — traer main a su remoto
  git push origin --delete <rama>        — borrar la rama fusionada
  git branch -D <rama>                   — y su copia local
  git worktree remove <ruta>             — y su worktree
Cada una SUELTA: el hook compara la orden entera, así que encadenar con &&, ;
o || la descarta. Una tubería final sí vale (| tail -2), mientras detrás no se
nombre git.

Si de verdad hace falta tocar main, díselo a Carlos y que lo apruebe él:
  CLAUDE_ALLOW_MAIN=1 $cmd
EOF
exit 2
