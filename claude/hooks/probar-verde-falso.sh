#!/bin/bash
# Prueba verde-falso.sh contra una matriz. No necesita repos ni directorio: el
# hook solo lee el comando, así que se ejecuta desde donde sea.
#
# Por defecto el hook de AL LADO, no el instalado: `~/.claude/hooks` es un enlace
# a la RAÍZ del repositorio, así que probar el instalado desde un worktree juzga
# la versión de main y da un verde falso justo en el caso normal —se acaba de
# tocar el hook—. Con HOOK=<ruta> se prueba otro.
set -uo pipefail

aqui=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
hook=${HOOK:-$aqui/verde-falso.sh}
fallos=0

probar() {           # probar <esperado: BLOQUEA|PASA> <comando>
  esperado=$1; cmd=$2
  printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$cmd" | jq -Rs .)" |
    bash "$hook" > /dev/null 2>&1
  codigo=$?
  if [ $codigo -eq 2 ]; then real=BLOQUEA; else real=PASA; fi
  if [ "$real" = "$esperado" ]; then
    printf '  ok    %-7s %s\n' "$real" "$cmd"
  else
    printf '  FALLO esperaba %s y dio %s: %s\n' "$esperado" "$real" "$cmd"
    fallos=$((fallos + 1))
  fi
}

echo "--- una puerta con tubería detrás: el rc es de la tubería ---"
probar BLOQUEA 'make check | tail -40'
probar BLOQUEA 'make check 2>&1 | tail -40'
probar BLOQUEA 'make test | grep -i fail'
probar BLOQUEA './verificar.sh | tail -5'
probar BLOQUEA './gradlew check | tail -20'
probar BLOQUEA 'flutter test | tail'
probar BLOQUEA 'pnpm verify | tail -3'
probar BLOQUEA 'npm run test | head -50'
probar BLOQUEA 'pytest | tail'
probar BLOQUEA 'go test ./... | tail'
probar BLOQUEA 'gh pr checks mi-rama | tail -5'
# Tuberías largas: la primera etapa sigue siendo la puerta.
probar BLOQUEA 'make check 2>&1 | grep -v warning | tail -20'
# Y dentro de una sustitución, que es como se guarda una salida para mirarla.
probar BLOQUEA 'salida=$(make check | tail -40)'
# `tee` no salva: el código que vuelve es el suyo.
probar BLOQUEA 'make check 2>&1 | tee /tmp/check.log'
# En un tramo posterior también cuenta.
probar BLOQUEA 'cd /repo && make check | tail -10'

echo "--- ...pero solo si la tubería es SUYA ---"
# La tubería es del `echo`, no de la puerta. Este es el falso positivo que haría
# que el hook estorbara a diario.
probar PASA 'make check && echo listo | tee /tmp/x'
probar PASA 'make check; ls | head -3'
probar PASA 'grep -rn "make check" CLAUDE.md | head -5'
probar PASA 'cat registro.txt | grep pytest'

echo "--- lo que conserva el código de salida ---"
probar PASA 'make check'
probar PASA 'make check > /tmp/check.log 2>&1'
probar PASA 'make check > /tmp/check.log 2>&1; rc=$?; tail -40 /tmp/check.log'
probar PASA 'set -o pipefail; make check | tail -40'
probar PASA 'make check | tail -40; echo ${PIPESTATUS[0]}'

echo "--- prosa que NOMBRA una tubería no es una tubería ---"
# La misma familia que el agujero del heredoc en git-no-main.sh: si el texto
# contara, sería el mensaje el que decide si se bloquea.
probar PASA 'git commit -m "arreglado: make check | tail mentía"'
probar PASA "echo 'make check | tail' >> notas.md"
probar PASA 'gh pr create --body "$(cat <<EOF
Antes esto se leía con make check | tail y el rc era del tail.
EOF
)"'

echo "--- lo que nunca le interesó ---"
probar PASA 'ls -la | head'
probar PASA 'docker compose logs backend | grep abc123'
probar PASA 'git log --oneline | head -20'
probar PASA 'CLAUDE_ALLOW_TUBERIA=1 make check | tail -5'

echo
[ $fallos -eq 0 ] && echo "TODO BIEN: 0 fallos" || echo "$fallos FALLOS"
exit $fallos
