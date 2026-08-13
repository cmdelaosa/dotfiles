#!/bin/bash
# PreToolUse(Bash) — impide que DOS sesiones de Claude a la vez muevan el índice,
# el HEAD o el árbol del MISMO checkout. En modo `--aviso` (SessionStart) no
# impide nada: solo lo dice al arrancar, que es cuando mudarse sale gratis.
#
# Existe por lo que pasó el 12-08-2026 con welzy: dos sesiones trabajando en
# /Users/cmo/Projects/welzy. La segunda hizo `git checkout main` y `commit -a`, y
# con eso movió el HEAD por debajo de la primera y se llevó dentro de su commit
# ficheros que la primera tenía a medias. No se perdió nada de milagro: el modo de
# fallo que sí borra es `git checkout -- <fichero>`, que restaura DESDE EL ÍNDICE,
# y con un `reset --soft` de otra sesión de por medio devuelve una versión vieja.
#
# La norma que sujeta: la segunda sesión abre un worktree. Un worktree tiene su
# propio HEAD, su propio índice y su propio árbol, así que el problema desaparece
# de raíz en vez de gestionarse.
#
# Cómo sabe que hay otra sesión, y por qué así:
#   - `ps ax`, NO `pgrep`: pgrep en macOS no ve los procesos del grupo que lo llama,
#     o sea que la sesión que pregunta no se ve a sí misma. Medido: 14 procesos con
#     ps, 12 con pgrep — faltaban justo los dos de quien preguntaba.
#   - La instantánea de ps se guarda en una variable ANTES de filtrarla. En un
#     `ps | grep patrón` el grep también está corriendo cuando ps mira, y su propia
#     línea de órdenes lleva el patrón dentro: se contaría a sí mismo. Es el mismo
#     motivo por el que todo el mundo escribe `| grep -v grep`.
#   - Cada sesión son DOS procesos (el envoltorio `disclaimer` y el `claude` que
#     cuelga de él). Se dedupe quedándose con el que NO tiene otro claude por padre,
#     que además es el que hay que mirar: los dos llevan el cwd de la sesión.
#   - Los procesos de menos de 10 s no cuentan. La app lanza `claude` sueltos que
#     viven milisegundos (uno cayó en una instantánea el 13-08-2026, pid 44677, sin
#     pareja y con el cwd de la sesión que lo lanzó). Sin este filtro, pillar uno
#     justo en el `ps` significa bloquear un commit citando un pid ya muerto.
#   - Compara raíces de git (`rev-parse --show-toplevel`), no rutas: una sesión
#     abierta en `welzy/backend` es la misma inquilina, y una abierta en un worktree
#     resuelve a una raíz distinta y por tanto no estorba — que es el objetivo.
#   - Una pestaña abierta pero muerta de aburrimiento no es una inquilina: solo
#     cuenta si su carpeta de transcripciones se ha tocado en las últimas
#     CLAUDE_CHECKOUT_TTL_MIN (4 h). Sin esto, tres pestañas viejas de welzy
#     bloquearían el checkout para siempre, y un falso positivo aquí es peor que
#     el problema. La comprobación excluye la transcripción propia: si no, uno se
#     bloquearía a sí mismo cada vez que la otra pestaña estuviera parada.
#
# Ante cualquier duda, DEJA PASAR. Solo se niega cuando ha identificado a la otra
# sesión de verdad; un hook que bloquea git por sorpresa es peor que el fallo que
# previene. Con una excepción que no se puede tapar desde dentro: bash sale con 2
# ante un error de sintaxis, y 2 es justo lo que este contrato lee como "bloquea".
# O sea que una errata aquí bloquea TODO git. Pásale `bash -n` antes de guardar.
#
# Escotilla, cuando de verdad estás solo (una pestaña vieja que no vas a cerrar):
#   CLAUDE_ALLOW_SHARED_CHECKOUT=1 git commit -m ...

set -uo pipefail

modo="${1:-gate}"
entrada=$(cat)
cwd=$(printf '%s' "$entrada" | jq -r '.cwd // empty' 2>/dev/null)
mi_transcripcion=$(printf '%s' "$entrada" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -z "$cwd" ] && cwd="$PWD"

if [ "$modo" != "--aviso" ]; then
  cmd=$(printf '%s' "$entrada" | jq -r '.tool_input.command // empty' 2>/dev/null)
  [ -z "$cmd" ] && exit 0

  # Solo los verbos que tocan estado compartido: HEAD, el índice o el árbol. Leer
  # (status, diff, log, show, worktree) no molesta a nadie y no se toca, entre otras
  # cosas porque `git worktree add` es justo el remedio que propone el mensaje.
  printf '%s' "$cmd" | grep -qE '(^|[;&|(]|[[:space:]])git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?(-[^[:space:]]+[[:space:]]+)*(add|am|apply|checkout|cherry-pick|clean|commit|merge|mv|pull|rebase|reset|restore|revert|rm|stash|switch)([[:space:]]|$)' || exit 0

  [ "${CLAUDE_ALLOW_SHARED_CHECKOUT:-}" = "1" ] && exit 0
  case "$cmd" in *CLAUDE_ALLOW_SHARED_CHECKOUT=1*) exit 0 ;; esac
fi

# El comando puede trabajar en otro sitio que el cwd de la sesión: `git -C <dir> …` o
# `cd <dir> && git …`. Y eso no es un caso raro, es lo normal desde que existe la
# norma de worktrees: una sesión arrancada en el checkout principal se muda a
# `.claude/worktrees/wt<rama>` y su cwd sigue siendo el de siempre. Sin mirar a dónde
# apunta el comando de verdad, dos sesiones cada una en SU worktree se juzgarían las
# dos contra el checkout principal y se bloquearían sin motivo — el falso positivo
# que hay que evitar por encima de todo. Medido el 13-08-2026 con dos sesiones así.
destino="$cwd"
if [ "$modo" != "--aviso" ]; then
  d=$(printf '%s' "$cmd" | sed -n 's/.*git[[:space:]]\{1,\}-C[[:space:]]\{1,\}\([^[:space:]]\{1,\}\).*/\1/p' | head -1)
  [ -z "$d" ] && d=$(printf '%s' "$cmd" | sed -n 's/^[[:space:]]*cd[[:space:]]\{1,\}\([^;&|]\{1,\}\).*/\1/p' | head -1)
  d=$(printf '%s' "$d" | sed 's/[[:space:]]*$//; s/^"//; s/"$//; s/^'\''//; s/'\''$//')
  case "$d" in
    ("") ;;
    ("~"/*) destino="${HOME}/${d#\~/}" ;;
    (/*) destino="$d" ;;
    (*) destino="${cwd}/${d}" ;;
  esac
  [ -d "$destino" ] || destino="$cwd"
fi

mi_raiz=$(git -C "$destino" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -z "$mi_raiz" ] && exit 0

# ── Quién más está vivo aquí ────────────────────────────────────────────────────
instantanea=$(ps ax -o pid=,ppid=,etime=,command= 2>/dev/null) || exit 0
[ -z "$instantanea" ] && exit 0

# El paréntesis de apertura del patrón no es decorativo: /bin/bash sigue siendo el
# 3.2 de Apple y su parser no cierra bien un `case` dentro de `$( )` sin él.
# `etime` viene como [[DD-]HH:]MM:SS; con día u hora ya sobra de largo.
claudes=$(printf '%s\n' "$instantanea" | while read -r pid ppid etime resto; do
  case "$resto" in
    (*"/MacOS/claude "* | *"/MacOS/claude") ;;
    (*) continue ;;
  esac
  case "$etime" in
    (*-* | *:*:*) ;;
    (*:*) [ $(( 10#${etime%%:*} * 60 + 10#${etime##*:} )) -ge 10 ] || continue ;;
    (*) continue ;;
  esac
  printf '%s %s\n' "$pid" "$ppid"
done)
[ -z "$claudes" ] && exit 0

todos=$(printf '%s\n' "$claudes" | awk '{print $1}')
principales=$(printf '%s\n' "$claudes" | while read -r pid ppid; do
  printf '%s\n' "$todos" | grep -qx "$ppid" || printf '%s\n' "$pid"
done)
[ -z "$principales" ] && exit 0

# Cuál de ellos soy yo: subiendo por los padres desde este propio hook.
mio=""
p=$PPID
for _ in 1 2 3 4 5 6 7 8; do
  [ -z "$p" ] && break
  if printf '%s\n' "$principales" | grep -qx "$p"; then mio="$p"; break; fi
  p=$(printf '%s\n' "$instantanea" | awk -v x="$p" '$1 == x { print $2; exit }')
done

# Un solo lsof para todos: uno por proceso serían décimas de segundo en cada commit.
lista=$(printf '%s' "$principales" | tr '\n' ',' | sed 's/,$//')
cwds=$(lsof -a -d cwd -p "$lista" -Fn 2>/dev/null) || exit 0

ttl_min="${CLAUDE_CHECKOUT_TTL_MIN:-240}"
ahora=$(date +%s)

# ¿Ha dado señales de vida la sesión que trabaja en ese directorio? Sus mensajes se
# escriben en ~/.claude/projects/<ruta con / y . vueltos ->/<sesión>.jsonl.
activa_en() {
  local suyo="$1" dir f m
  dir="$HOME/.claude/projects/$(printf '%s' "$suyo" | sed 's/[/.]/-/g')"
  # Sin carpeta no se puede afinar, y el proceso vivo ya es prueba suficiente.
  [ -d "$dir" ] || return 0
  for f in "$dir"/*.jsonl; do
    [ -f "$f" ] || continue
    [ "$f" = "$mi_transcripcion" ] && continue
    m=$(stat -f %m "$f" 2>/dev/null || stat -c %m "$f" 2>/dev/null) || continue
    [ $(( (ahora - m) / 60 )) -lt "$ttl_min" ] && return 0
  done
  return 1
}

otra_pid="" otra_cwd=""
pid=""
while IFS= read -r linea; do
  case "$linea" in
    p*) pid="${linea#p}" ;;
    n*)
      suyo="${linea#n}"
      [ "$pid" = "$mio" ] && continue
      [ -z "$suyo" ] && continue
      raiz=$(git -C "$suyo" rev-parse --show-toplevel 2>/dev/null) || continue
      [ "$raiz" = "$mi_raiz" ] || continue
      activa_en "$suyo" || continue
      otra_pid="$pid" otra_cwd="$suyo"
      break ;;
  esac
done <<EOF
$cwds
EOF

[ -z "$otra_pid" ] && exit 0

# La rama del checkout del que hablamos, que es el del comando y no el de la sesión.
rama=$(git -C "$mi_raiz" rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)

if [ "$modo" = "--aviso" ]; then
  cat <<EOF
AVISO: hay otra sesión de Claude viva en este mismo checkout (${mi_raiz}, pid
${otra_pid}). Dos sesiones en un checkout comparten HEAD, índice y árbol: un
\`checkout\` o un \`commit -a\` de una se lleva por delante lo que la otra tenía a
medias. Antes de tocar nada, múdate a un worktree:

    git -C ${mi_raiz} worktree add .claude/worktrees/wt<rama> -b <rama>
    cd ${mi_raiz}/.claude/worktrees/wt<rama>

Los comandos de git que mueven el árbol están bloqueados hasta entonces.
EOF
  exit 0
fi

cat >&2 <<EOF
Hay otra sesión de Claude viva en este mismo checkout:

    checkout   ${mi_raiz}   (rama ${rama})
    la otra    pid ${otra_pid}, abierta en ${otra_cwd}

Comparten HEAD, índice y árbol de trabajo, así que este comando puede llevarse por
delante lo que la otra tenga a medias — y al revés. Múdate a un worktree, que tiene
los tres para él solo:

    git -C ${mi_raiz} worktree add .claude/worktrees/wt<rama> -b <rama>
    cd ${mi_raiz}/.claude/worktrees/wt<rama>

Si esa otra sesión es una pestaña vieja que ya no usas, ciérrala; o, si sabes que
no va a tocar git:

    CLAUDE_ALLOW_SHARED_CHECKOUT=1 ${cmd}
EOF
exit 2
