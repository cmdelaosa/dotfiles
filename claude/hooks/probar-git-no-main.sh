#!/bin/bash
# Prueba git-no-main.sh contra una matriz. Se ejecuta desde DONDE SEA: monta sus
# propios repos y se mete en uno que está en main, porque el hook resuelve la
# rama desde su directorio de trabajo. Lanzarlo desde una rama daba 22 fallos
# que no eran del hook — el hook deja pasar todo fuera de main, así que caían a
# la vez los 22 casos de «BLOQUEA». Rojo falso, nunca verde falso, pero cuesta
# un minuto averiguarlo.
# Por defecto el hook de AL LADO, no el instalado. Hasta el 13-08-2026 era al
# revés (`~/.claude/hooks/git-no-main.sh`) y eso daba un verde falso justo en el
# caso normal: se toca el hook en un worktree, pero ~/.claude/hooks es un enlace
# a la RAÍZ del repositorio, así que la matriz probaba la versión de main y no la
# que se acababa de escribir. Con HOOK=<ruta> se prueba otro — el instalado, por
# ejemplo, para confirmar que la máquina tiene lo que se cree que tiene.
# `set -u` como las otras dos matrices: era la única sin él, y es justo el freno
# que convierte una variable de ruta vacía —por una errata en el nombre— en un
# error a la vista en vez de en un `git -C ""` silencioso sobre el repositorio
# desde el que se lanza. Aquí no hay ningún `git -C` con una ruta que pueda
# quedar vacía (todas se construyen como "$TMP/algo"), pero la asimetría entre
# las tres matrices es en sí misma la clase de detalle que esconde el próximo.
set -uo pipefail

aqui=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
hook=${HOOK:-$aqui/git-no-main.sh}
fallos=0

probar() {           # probar <esperado: BLOQUEA|PASA> <comando>
  esperado=$1; shift
  cmd=$1
  salida=$(printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$cmd" | jq -Rs .)" | bash "$hook" 2>/dev/null)
  codigo=$?
  if [ $codigo -eq 2 ]; then real=BLOQUEA; else real=PASA; fi
  if [ "$real" = "$esperado" ]; then
    printf '  ok    %-7s %s\n' "$real" "$cmd"
  else
    printf '  FALLO esperaba %s y dio %s: %s\n' "$esperado" "$real" "$cmd"
    fallos=$((fallos + 1))
  fi
}

# Igual, pero desde OTRO directorio de trabajo. Hace falta para el `cd`: ese
# agujero solo se ve cuando el cwd no es un repo en main, que es lo normal en
# una sesión de verdad —el scratchpad, otro proyecto, un worktree en rama— y
# justo por eso pasó desapercibido.
probar_desde() {     # probar_desde <dir> <esperado: BLOQUEA|PASA> <comando>
  dir=$1; esperado=$2; cmd=$3
  salida=$(cd "$dir" && printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$cmd" | jq -Rs .)" | bash "$hook" 2>/dev/null)
  codigo=$?
  if [ $codigo -eq 2 ]; then real=BLOQUEA; else real=PASA; fi
  if [ "$real" = "$esperado" ]; then
    printf '  ok    %-7s [desde %s] %s\n' "$real" "$(basename "$dir")" "$cmd"
  else
    printf '  FALLO esperaba %s y dio %s [desde %s]: %s\n' "$esperado" "$real" "$(basename "$dir")" "$cmd"
    fallos=$((fallos + 1))
  fi
}

# Dos repos de mentira para probar `-C`: uno en main y otro en una rama. El hook
# tiene que juzgar el HEAD del repo APUNTADO, no el del directorio desde el que
# se le llama.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP_MAIN=$TMP/en-main
TMP_RAMA=$TMP/en-rama
for d in "$TMP_MAIN" "$TMP_RAMA"; do
  git init -q -b main "$d"
  git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m inicial
done
git -C "$TMP_RAMA" checkout -q -b la-rama

# Y se trabaja DESDE el que está en main: así los casos sin `-C` se juzgan
# siempre contra un main, venga uno de donde venga.
cd "$TMP_MAIN" || exit 1

echo "--- lo que tiene que SEGUIR bloqueado (estando en main) ---"
probar BLOQUEA 'git commit -m "algo"'
probar BLOQUEA 'git merge otra-rama'
probar BLOQUEA 'git push'
probar BLOQUEA 'git push origin main'
probar BLOQUEA 'git push --force origin main'
probar BLOQUEA 'git push origin --delete main'
probar BLOQUEA 'git push origin --delete master'
probar BLOQUEA 'git push origin -d main'

echo "--- LA FISURA que había que cerrar ---"
probar BLOQUEA 'git merge --ff-only otra-rama'
probar BLOQUEA 'git merge --ff-only 888755e'
probar BLOQUEA 'git commit -m "trampa --ff-only"'
probar BLOQUEA 'git push origin main && git push origin --delete rama-x'
probar BLOQUEA 'git push origin --delete rama-x && git push origin main'
# Y encadenar descarta la excepción sea cual sea el operador, no solo con &&.
probar BLOQUEA 'git branch -D rama-x; git push origin --delete rama-x'
probar BLOQUEA 'git push origin --delete rama-x || git push origin main'

echo "--- la tubería final, que no cambia lo que git hace ---"
probar PASA    'git push origin --delete rama-x | tail -2'
probar PASA    'git push origin --delete rama-x 2>&1 | tail -2'
probar PASA    'git pull --ff-only | tail -3'
probar PASA    'git pull --ff-only 2>&1'
probar PASA    'git push origin --delete rama-x | grep deleted | tail -1'
# ...pero detrás de la tubería no se cuela un git.
probar BLOQUEA 'git push origin --delete rama-x | git push origin main'
probar BLOQUEA 'git push origin --delete rama-x | tail && git push origin main'
probar BLOQUEA 'git push origin main | tail -2'
probar BLOQUEA 'git pull --ff-only | git push origin main'

echo "--- la limpieza de después de fusionar, que ahora TIENE que pasar ---"
probar PASA 'git pull --ff-only'
probar PASA 'git pull --ff-only origin main'
probar PASA 'git merge --ff-only origin/main'
probar PASA 'git merge --ff-only @{u}'
probar PASA 'git push origin --delete la-rama-de-la-pr'
probar PASA 'git push origin -d fuera-los-atajos-que-ya-no-se-usan'
probar PASA 'git push upstream --delete rama/con-barra'

echo "--- el heredoc es TEXTO: mencionar una orden no es darla ---"
probar PASA    $'gh pr create --body "$(cat <<\'EOF\'\ngit push origin main\nEOF\n)"'
probar PASA    $'gh pr create --title x --body "$(cat <<\'EOF\'\nAntes hacíamos git merge otra-rama\ny también git commit -m algo\nEOF\n)"'
# ...pero la línea que ABRE el heredoc sí es una orden, y lo de después también.
probar BLOQUEA $'git commit -F - <<\'MSG\'\nun mensaje cualquiera\nMSG'
probar BLOQUEA $'cat <<\'EOF\' > f\ntexto\nEOF\ngit push origin main'
probar BLOQUEA $'gh pr create --body "$(cat <<\'EOF\'\ntexto\nEOF\n)" && git push origin main'

echo "--- '-C': manda la rama del repo APUNTADO, no la del cwd ---"
probar BLOQUEA "git -C $TMP_MAIN commit -m algo"
probar BLOQUEA "git -C $TMP_MAIN push origin main"
probar BLOQUEA "git -C $TMP_MAIN merge --ff-only una-rama"
probar PASA    "git -C $TMP_RAMA commit -m algo"
probar PASA    "git -C $TMP_RAMA push -u origin la-rama"
probar PASA    "git -C $TMP_MAIN push origin --delete la-rama-de-la-pr"

echo "--- 'cd <repo> && git …' apunta tan fuerte como '-C' ---"
mkdir -p "$TMP/sin-repo"
probar_desde "$TMP/sin-repo" BLOQUEA "cd $TMP_MAIN && git commit -m algo"
probar_desde "$TMP/sin-repo" BLOQUEA "cd $TMP_MAIN && git push origin main"
probar_desde "$TMP/sin-repo" BLOQUEA "cd $TMP_MAIN; git commit -m algo"
probar_desde "$TMP/sin-repo" BLOQUEA "cd \"$TMP_MAIN\" && git commit -m algo"
probar_desde "$TMP_RAMA"     BLOQUEA "cd $TMP_MAIN && git commit -m algo"
probar_desde "$TMP"          BLOQUEA "cd en-main && git commit -m algo"
probar_desde "$TMP/sin-repo" PASA    "cd $TMP_RAMA && git commit -m algo"
# `-C` es lo que obedece git de verdad, así que gana al `cd`.
probar_desde "$TMP/sin-repo" BLOQUEA "cd $TMP_RAMA && git -C $TMP_MAIN commit -m algo"
probar_desde "$TMP/sin-repo" PASA    "cd $TMP_MAIN && git -C $TMP_RAMA commit -m algo"
# Un `cd` que no lleva a ningún sitio no absuelve: se vuelve a juzgar el cwd.
probar_desde "$TMP_MAIN"     BLOQUEA "cd /no-existe-de-verdad && git commit -m algo"
# Y la limpieza de después de fusionar sigue pasando con un `cd` delante: un `cd`
# no cambia lo que git hace, y es como se escribe desde fuera del repo.
probar_desde "$TMP/sin-repo" PASA    "cd $TMP_MAIN && git push origin --delete la-rama-de-la-pr"
probar_desde "$TMP/sin-repo" PASA    "cd $TMP_MAIN && git pull --ff-only"
probar_desde "$TMP/sin-repo" PASA    "cd $TMP_MAIN; git push origin -d la-rama-de-la-pr"
# Pero el `cd` no abre la puerta a encadenar detrás, que es de lo que protege.
probar_desde "$TMP/sin-repo" BLOQUEA "cd $TMP_MAIN && git push origin --delete r && git push origin main"

echo "--- ...pero un 'cd' NOMBRADO no es un 'cd' DADO ---"
# La misma familia que el agujero de `--ff-only` y que el del heredoc: si el `cd`
# escrito dentro del mensaje contara, sería el mensaje el que elige qué repo se
# juzga.
probar_desde "$TMP_RAMA" PASA    "git commit -m \"vengo de hacer cd $TMP_MAIN\""
probar_desde "$TMP_MAIN" BLOQUEA "git commit -m \"vengo de hacer cd $TMP_RAMA\""

echo "--- lo que nunca le interesó ---"
probar PASA 'git merge-base main otra-rama'
probar PASA 'git status'
probar PASA 'git branch -D una-rama'
probar PASA 'git worktree remove .claude/worktrees/wtalgo'
probar PASA 'git fetch origin --prune'
probar PASA 'CLAUDE_ALLOW_MAIN=1 git push origin main'

echo
[ $fallos -eq 0 ] && echo "TODO BIEN: 0 fallos" || echo "$fallos FALLOS"
exit $fallos
