#!/usr/bin/env bash
# Todo lo que se puede juzgar de un cambio de este repositorio sin salir de la
# máquina: la sintaxis de cada guión y las dos matrices de pruebas.
#
# Lo lanza `probar-rama.sh` antes de empujar, así que aquí va lo RÁPIDO. Si algo
# tarda minutos, su sitio es el CI: un freno que cuesta cinco minutos cada vez
# acaba con un `--sin-verificar` en cada llamada, y entonces no frena nada.
#
# Por eso, desde el 17-08-2026, las tres matrices solo se lanzan si el cambio
# toca lo que prueban —`claude/bin` o `claude/hooks`—, y `--todo` las fuerza. Un
# cambio de prosa o de settings sale de aquí en un segundo; uno que toca los
# guiones de rama sigue pagando su minuto, que es justo cuando vale la pena.
#
# `comprobar.sh` NO se llama desde aquí, a propósito. Juzga la INSTALACIÓN —que
# ~/.claude siga enlazado a este repositorio—, no el cambio, y desde cualquier
# worktree encuentra los enlaces apuntando a la raíz: fallaría en todas las
# ramas, siempre, diciendo la verdad sobre algo que no es lo que se prueba. Lo
# llama un hook de SessionStart, que es cuando esa pregunta sí toca.
set -uo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fallos=0

todo=0
for bandera in "$@"; do
  case "$bandera" in
    --todo) todo=1 ;;
    -h | --help)
      printf 'Uso: verificar.sh [--todo]\n\n'
      printf '  Sin banderas: sintaxis y presupuesto de instrucciones, y las tres\n'
      printf '  matrices SOLO si el cambio toca claude/bin o claude/hooks.\n'
      printf '  --todo: lanza las tres matrices pase lo que pase. Es lo que usa el CI.\n'
      exit 0 ;;
    *) printf 'Opción desconocida: %s\n' "$bandera" >&2; exit 1 ;;
  esac
done

titulo() { printf '\n=== %s ===\n' "$1"; }

# Con `/bin/bash` a posta, el 3.2 de Apple, y no el 5.x de Homebrew: el 3.2 es
# quien ejecuta los hooks y acepta menos cosas. Un `case` dentro de `$( )` sin
# paréntesis de apertura en el patrón se lo traga el 5.x y lo rechaza el 3.2 —y
# un hook PreToolUse con un error de sintaxis sale con 2, que significa
# «bloqueado»: una errata aquí bloquea todo git en todas las sesiones.
titulo "sintaxis de todos los .sh ($(/bin/bash --version | head -1 | sed 's/.*version \([^ (]*\).*/\1/'))"
# Y si el /bin/bash de aquí no es el 3.2 —en el CI de GitHub es un 5.x de
# Ubuntu—, se dice, porque entonces esta sección comprueba menos de lo que su
# título promete: pilla los errores de sintaxis de siempre, pero no los que solo
# el 3.2 rechaza, que son justo los que bloquean git en esta máquina.
case "$(/bin/bash --version | head -1)" in
  *"version 3.2"*) ;;
  # Un printf, y no dos argumentos: sin `%s` en el formato, el segundo se cae
  # sin decir nada y el aviso salía cortado a mitad de frase.
  *) printf '%s\n%s\n' \
       '  (ojo: aquí /bin/bash no es el 3.2 de Apple, que es quien ejecuta los hooks:' \
       '   lo específico de esa versión solo lo ve esta comprobación lanzada en el Mac)' ;;
esac
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

# ── El presupuesto de las instrucciones ─────────────────────────────────────
# *(17-08-2026)* El CLAUDE.md global se carga entero en CADA sesión de CADA
# proyecto, así que cada línea se paga siempre. Llegó a 19,5 KB —unos 5.000
# tokens— y la propia documentación de Anthropic avisa de lo que eso provoca:
# un fichero largo hace que se ignoren justo las reglas que importan.
#
# Ya se había recortado antes y volvió a crecer solo, regla a regla, porque cada
# lección nueva se escribía ahí con su porqué entero. Por eso el límite es una
# comprobación y no un propósito: el CI de este repositorio lanza este guión en
# cada PR, así que el fichero no puede volver a estallar sin que alguien suba
# este número a propósito, que es una decisión y se ve en el diff.
#
# Dónde va lo que no cabe: el porqué histórico, a `docs/porques.md` —que no lo
# carga nadie—; el detalle operativo, al cuerpo de las skills, que se cargan
# solo cuando toca.
titulo "presupuesto de las instrucciones que se cargan siempre"
presupuesto() {                         # presupuesto <fichero> <bytes> <líneas>
  local f="$repo/$1" bytes lineas
  if [ ! -f "$f" ]; then
    printf '  FALLO   %s no existe, y el presupuesto lo vigila\n' "$1"
    fallos=$((fallos + 1)); return
  fi
  # Se mide lo que se CARGA, no lo que ocupa el fichero: Claude Code quita los
  # comentarios HTML de bloque antes de meter esto en contexto, así que una nota
  # para quien mantiene el fichero no debe gastar presupuesto —ni empujar a
  # borrarla, que es lo que haría contarla.
  bytes=$(sed '/<!--/,/-->/d' "$f" | wc -c | tr -d ' ')
  lineas=$(sed '/<!--/,/-->/d' "$f" | wc -l | tr -d ' ')
  if [ "$bytes" -le "$2" ] && [ "$lineas" -le "$3" ]; then
    printf '  ok      %-34s %5s B / %3s líneas (tope %s B / %s)\n' "$1" "$bytes" "$lineas" "$2" "$3"
  else
    printf '  FALLO   %-34s %5s B / %3s líneas — el tope es %s B / %s\n' "$1" "$bytes" "$lineas" "$2" "$3"
    printf '          Saca lo que sobre a docs/porques.md o al cuerpo de una skill.\n'
    printf '          Subir el tope es una decisión tuya, no el arreglo de este fallo.\n'
    fallos=$((fallos + 1))
  fi
}
presupuesto claude/CLAUDE.md 6000 80
# La skill más gorda. No se carga siempre —solo cuando la cadena arranca—, pero
# se carga justo en el momento más caro, así que también tiene tope, más flojo.
presupuesto claude/skills/probar/SKILL.md 9000 220

# ── Las tres matrices: a la vez, y solo si tocan ────────────────────────────
# Dos cambios del 17-08-2026, y los dos salen de haberlo medido: este guión
# tardaba 58 s —con `sys 26s`, o sea casi todo arrancando procesos— contra los
# **32 s que tarda el CI entero** al que pretende ahorrar viajes, y encima corría
# dos veces por cadena. Un freno más lento que el CI que protege está al revés.
#
# 1. En paralelo. Salva los trece segundos de las dos matrices de hooks; la de
#    los guiones de rama es la que manda y esa no se parte sin reescribirla.
# 2. **Solo se lanzan si el cambio las toca.** Una matriz prueba un fichero
#    concreto: si `claude/bin` y `claude/hooks` están intactos, lanzarlas es
#    gastar un minuto en volver a demostrar lo mismo que ayer. Lo decide el
#    diff, no quien llama —el mismo criterio que `clasificar-diff.sh`—, y cuando
#    se las salta lo DICE, porque un chequeo callado no se distingue de uno que
#    aprueba.
#
# `--todo` las fuerza, y es lo que usa el CI: allí hay tiempo de sobra, la
# comparación con `origin/main` no siempre existe, y el verde de una PR tiene que
# significar que se ha probado todo.
#
# La salida de cada una se guarda y se imprime junta al final: mezcladas línea a
# línea no se entiende cuál dijo qué.
#
# Las dos matrices de hooks ya prueban por defecto la copia de al lado, así que
# aquí no hace falta HOOK=: lanzando la de este worktree se juzga el hook de esta
# rama, que es lo que se está cambiando. HOOK= sigue sirviendo para la otra
# pregunta —«¿tiene la máquina lo que creo?»—, que no es la de un push.
lanzar_matrices=0
motivo_matrices=""
if [ "$todo" = 1 ]; then
  lanzar_matrices=1
  motivo_matrices="me lo han pedido con --todo"
elif ! base=$(git -C "$repo" merge-base HEAD origin/main 2>/dev/null); then
  # Sin base con la que comparar no se decide a la ligera: se lanzan. Un freno
  # que no sabe responder tiene que decir que sí a lo caro, no que no.
  lanzar_matrices=1
  motivo_matrices="no encuentro origin/main para comparar, así que las lanzo todas"
elif git -C "$repo" diff --quiet "$base" -- claude/bin claude/hooks &&
     git -C "$repo" diff --quiet -- claude/bin claude/hooks; then
  motivo_matrices="ni claude/bin ni claude/hooks han cambiado desde origin/main"
else
  lanzar_matrices=1
  motivo_matrices="el cambio toca claude/bin o claude/hooks"
fi

if [ "$lanzar_matrices" != 1 ]; then
  titulo "matrices de pruebas"
  printf '  ----    NO las he lanzado: %s.\n' "$motivo_matrices"
  printf '          Las lanza igualmente el CI, que tarda medio minuto.\n'
  printf '          A mano, aquí:  ./verificar.sh --todo\n'
  echo
  # Lo que este guión tarda es parte de lo que comprueba *(17-08-2026)*: la regla
  # de casa dice «mantenlo en segundos» y había llegado a 58 sin que nadie lo
  # midiera. Un freno que cuesta un minuto acaba con un `--sin-verificar` en cada
  # llamada, y entonces no frena nada. Avisa y no suspende: un chequeo que se
  # pone rojo por lento se apaga a la semana.
  if [ "$SECONDS" -gt "${TOPE_SEGUNDOS:-15}" ]; then
    echo "OJO: sin matrices esto ha tardado ${SECONDS}s, y el objetivo son ${TOPE_SEGUNDOS:-15}s."
    echo "     Lo lento tiene su sitio en el CI, no en el freno de antes del push."
  fi
  if [ "$fallos" -eq 0 ]; then
    echo "verificar.sh: TODO BIEN (${SECONDS}s, sin matrices)"
    exit 0
  fi
  echo "verificar.sh: $fallos comprobacion(es) en rojo (${SECONDS}s)"
  exit 1
fi

salidas=$(mktemp -d)
trap 'rm -rf "$salidas"' EXIT

matrices="claude/bin/probar-ramas.sh:matriz de abrir/probar/cerrar-rama.sh
claude/hooks/probar-git-no-main.sh:matriz del hook git-no-main.sh
claude/hooks/probar-git-una-sesion.sh:matriz del hook git-una-sesion-por-checkout.sh"

n=0
while IFS= read -r linea; do
  n=$((n + 1))
  guion=${linea%%:*}
  ( "$repo/$guion" > "$salidas/$n.out" 2>&1; printf '%s' "$?" > "$salidas/$n.cod" ) &
done <<MATRICES
$matrices
MATRICES
wait

n=0
while IFS= read -r linea; do
  n=$((n + 1))
  titulo "${linea#*:}"
  cat "$salidas/$n.out"
  # Una matriz que no deja código es una matriz que no llegó a correr, y eso
  # cuenta como rojo: el silencio de un chequeo no se distingue de su aprobado.
  [ "$(cat "$salidas/$n.cod" 2>/dev/null || echo 1)" = 0 ] || fallos=$((fallos + 1))
done <<MATRICES
$matrices
MATRICES

echo
if [ "$fallos" -eq 0 ]; then
  echo "verificar.sh: TODO BIEN (${SECONDS}s)"
else
  echo "verificar.sh: $fallos comprobacion(es) en rojo (${SECONDS}s)"
  exit 1
fi
