#!/bin/bash
# Prueba git-no-main.sh contra una matriz. Se ejecuta DESDE un repo en main.
hook=~/.claude/hooks/git-no-main.sh
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
