#!/bin/bash
# PreToolUse(Bash) — rechaza una PUERTA con una tubería detrás, porque entonces
# el código de salida que se lee no es el suyo.
#
#     make check | tail -40        → el rc es el de `tail`, que siempre es 0
#
# Existe porque ya pasó, y es el único de los fallos conocidos que puede llegar
# a producción sin que nadie lo vea: se dio `make check` por verde leyendo una
# salida truncada cuyo código de salida venía de `tail`. La regla estaba escrita
# —el CLAUDE.md de Welzy dice «No afirmes que pasa; pégalo»— y no frenó nada, que
# es el argumento entero de este fichero: una regla que ya estaba escrita y se
# saltó no se arregla escribiéndola otra vez.
#
# Lo que NO es: un juez de la calidad del comando. Redirigir a fichero pasa
# —`make check > log 2>&1` conserva el código—, y declarar `pipefail` también:
# quien lo escribe ya ha resuelto el problema del que protege esto.
#
# Escotilla, cuando de verdad haga falta:
#   CLAUDE_ALLOW_TUBERIA=1 make check | tail -5
set -uo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

# Escotilla: exportada en el entorno, o escrita delante del comando.
[ "${CLAUDE_ALLOW_TUBERIA:-}" = "1" ] && exit 0
case "$cmd" in *CLAUDE_ALLOW_TUBERIA=1*) exit 0 ;; esac

# Quien ya se ha ocupado del problema no necesita que le paren: `pipefail` hace
# que la tubería devuelva el primer fallo, y `PIPESTATUS` lee el código de la
# etapa que importa. Las dos son la respuesta correcta, no una excusa.
case "$cmd" in *pipefail* | *PIPESTATUS*) exit 0 ;; esac

# Los cuerpos de heredoc son TEXTO: un `gh pr create` cuyo cuerpo MENCIONE una
# tubería no ejecuta ninguna. Mismo tratamiento —y mismo awk— que en
# git-no-main.sh, donde esta familia de falsos positivos ya costó lo suyo.
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

# Y lo entrecomillado también es texto. Una `|` dentro de comillas es un carácter,
# no una tubería, así que quitar los tramos citados es lo CORRECTO para buscar el
# operador — y de paso desactiva `git commit -m "make check | tail"`, que es la
# misma trampa que el heredoc: prosa que nombra una orden no es esa orden.
#
# Precio conocido: un `bash -c "make check | tail"` deja de verse. Hay que
# escribirlo a propósito, y el falso positivo se pagaría a diario.
sin_citas=$(printf '%s' "$orden" | sed -e 's/"[^"]*"//g' -e "s/'[^']*'//g")

# Las puertas: lo que se lanza para saber si algo está bien. La lista es cerrada
# a propósito —un patrón genérico bloquearía `grep … | head`, que es la mitad del
# trabajo de una sesión— y se amplía cuando aparezca la siguiente.
PUERTAS='(^|[[:space:]=(])(make[[:space:]]+(check|test|e2e|verify|ci)|\./verificar\.sh|\./gradlew|flutter[[:space:]]+(test|analyze)|pnpm[[:space:]]+(verify|test|check|build)|npm[[:space:]]+(test|run[[:space:]]+(test|check|verify|build))|yarn[[:space:]]+(test|check)|pytest|go[[:space:]]+test|cargo[[:space:]]+test|gh[[:space:]]+pr[[:space:]]+checks)([[:space:]]|$)'

# Se juzga tramo a tramo: lo que separa `;`, `&&` y `||` son órdenes distintas, y
# solo cuenta la tubería que va DETRÁS de la puerta. Sin esto, un
# `make check && echo listo | tee log` saldría bloqueado por una tubería que no
# es la suya. El `||` se convierte antes que el `|`, o se leería como dos.
culpable=""
while IFS= read -r tramo; do
  antes=${tramo%%|*}
  [ "$antes" = "$tramo" ] && continue          # ese tramo no lleva tubería
  if printf '%s' "$antes" | grep -qE "$PUERTAS"; then
    culpable=$(printf '%s' "$tramo" | sed 's/^ *//; s/ *$//')
    break
  fi
done <<TRAMOS
$(printf '%s' "$sin_citas" | awk '{ gsub(/\|\|/, "\n"); gsub(/&&/, "\n"); gsub(/;/, "\n"); print }')
TRAMOS

[ -z "$culpable" ] && exit 0

puerta=$(printf '%s' "$culpable" | sed 's/ *|.*//')

cat >&2 <<EOF
Con una tubería detrás, el código de salida que vuelve NO es el de la puerta:

    $culpable
                     └─ el rc de esto es el que se lee, y casi siempre es 0

Cualquiera de estas dos sí dice la verdad:

    $puerta > /tmp/puerta.log 2>&1; rc=\$?; tail -40 /tmp/puerta.log; echo "rc=\$rc"
    set -o pipefail; $culpable

Y enseña el rc junto a la salida: un verde sin su código de salida es una
afirmación, no una prueba.
EOF

# Y si la puerta era el CI, la otra mitad del mismo fallo, que no la arregla
# ninguna tubería: una ejecución en cola no es «sin checks».
case "$puerta" in
  *"gh pr checks"*)
    cat >&2 <<'EOF'

Además, con `gh pr checks`: «en cola» o «pendiente» NO es un aprobado, y
«sin checks» tampoco. Espera a que TODOS estén completados antes de decir verde.
EOF
    ;;
esac

cat >&2 <<EOF

Si de verdad da igual el resultado —mirar una salida por encima, sin concluir
nada de ella—, díselo así:
  CLAUDE_ALLOW_TUBERIA=1 $culpable
EOF
exit 2
