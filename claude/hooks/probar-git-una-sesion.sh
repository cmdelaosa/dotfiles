#!/bin/bash
# Matriz de git-una-sesion-por-checkout.sh, el otro hook que sale con 2 y que
# hasta el 13-08-2026 no tenía ninguna. Son 212 líneas de `ps`, `lsof` y fechas
# de transcripción decidiendo si se bloquea git entero, y la única defensa era
# acordarse de pasarle `bash -n`.
#
# Cómo se falsea el mundo, y por qué así:
#   - `ps` y `lsof` se sustituyen por delante en el PATH. El hook los llama por
#     su nombre pelado, así que no hace falta tocarlo para probarlo — y un hook
#     que hay que modificar para poder probarlo se prueba a sí mismo, no al que
#     está instalado.
#   - El `ps` falso NO inventa la tabla de procesos entera: coge la de verdad,
#     le quita las líneas de Claude y mete las que diga el caso. Hace falta que
#     el árbol real siga ahí porque el hook averigua «cuál de estos soy yo»
#     subiendo por los padres, y con una tabla inventada esa subida no llega a
#     ninguna parte: se creería que ninguna sesión es la suya y se bloquearía a
#     sí mismo en cada comando.
#   - `HOME` se muda a un directorio del caso, porque la comprobación de «¿ha
#     dado señales de vida?» lee ~/.claude/projects/<ruta>/*.jsonl. Sin esto la
#     matriz dependería de las transcripciones de verdad de la máquina.
#
# Por defecto prueba el hook de AL LADO, no el instalado: lo normal es tocarlo
# en un worktree, y ~/.claude/hooks apunta a la raíz. Con HOOK=<ruta> se prueba
# otro (el instalado, por ejemplo).
#
# Al tocar el hook: lánzalo, y rompe a propósito el caso que te importe para
# verlo fallar. Un test que no puede fallar es la falsa confianza de siempre.
set -uo pipefail

aqui=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
hook=${HOOK:-$aqui/git-una-sesion-por-checkout.sh}
fallos=0

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ── El mundo de mentira ─────────────────────────────────────────────────────
mkdir -p "$TMP/bin"

# SESIONES: "pid,ppid,etime,cwd" separadas por ';' (con coma, que el
# etime lleva dos puntos dentro). Cada una es una sesión de
# Claude viva. El cwd solo lo ve el `lsof` falso, igual que en la realidad.
cat > "$TMP/bin/ps" <<'FALSO'
#!/bin/bash
# La tabla de verdad SIN las líneas de Claude, más las que diga el caso.
/bin/ps ax -o pid=,ppid=,etime=,command= | grep -v '/MacOS/claude'
IFS=';' read -ra sesiones <<< "${SESIONES:-}"
for s in "${sesiones[@]}"; do
  [ -n "$s" ] || continue
  IFS=',' read -r pid ppid etime _cwd <<< "$s"
  printf '%s %s %s %s\n' "$pid" "$ppid" "$etime" \
    "/Applications/Claude.app/Contents/MacOS/claude --lo-que-sea"
done
FALSO
chmod +x "$TMP/bin/ps"

cat > "$TMP/bin/lsof" <<'FALSO'
#!/bin/bash
# Solo el formato que pide el hook: -Fn, o sea p<pid> y n<cwd>.
IFS=';' read -ra sesiones <<< "${SESIONES:-}"
for s in "${sesiones[@]}"; do
  [ -n "$s" ] || continue
  IFS=',' read -r pid _ppid _etime cwd <<< "$s"
  printf 'p%s\nn%s\n' "$pid" "$cwd"
done
FALSO
chmod +x "$TMP/bin/lsof"

export PATH="$TMP/bin:$PATH"

# ── Repos de mentira ────────────────────────────────────────────────────────
# Uno principal con un worktree y un subdirectorio, y otro distinto. Con eso se
# cubren las tres respuestas que importan: misma raíz (estorba), raíz distinta
# (no estorba) y otro repositorio (no estorba).
REPO="$TMP/repo"
OTRO="$TMP/otro"
for d in "$REPO" "$OTRO"; do
  git init -q -b main "$d"
  git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m inicial
done
mkdir -p "$REPO/sub"
git -C "$REPO" worktree add -q "$TMP/wt" -b la-rama >/dev/null 2>&1
FUERA="$TMP/sin-repo"; mkdir -p "$FUERA"

# ── Lanzar el hook ──────────────────────────────────────────────────────────
# El pid del propio script hace de «yo»: el hook sube por los padres hasta
# encontrarse, y desde este script hay dos o tres saltos. Así se puede probar lo
# que ninguna otra cosa prueba — que una sesión sola no se bloquea a sí misma.
YO=$$
YO_PADRE=$(/bin/ps -o ppid= -p $$ | tr -d ' ')

# casa <sufijo> <ruta-de-la-otra-sesion> <edad-en-minutos|nada>
# Monta un HOME con la transcripción de la otra sesión, para la comprobación de
# «¿ha dado señales de vida?».
casa() {
  local nombre=$1 suyo=$2 edad=${3:-}
  local h="$TMP/casa-$nombre"
  [ -n "$edad" ] || { mkdir -p "$h"; printf '%s' "$h"; return; }
  local dir="$h/.claude/projects/$(printf '%s' "$suyo" | sed 's/[/.]/-/g')"
  mkdir -p "$dir"
  : > "$dir/sesion.jsonl"
  touch -t "$(date -v -"${edad}"M +%Y%m%d%H%M 2>/dev/null || date -d "-${edad} minutes" +%Y%m%d%H%M)" \
    "$dir/sesion.jsonl"
  printf '%s' "$h"
}

lanzar() {           # lanzar <modo> <cwd> <comando> [transcripcion]
  local modo=$1 cwd=$2 cmd=$3 trans=${4:-$TMP/mi-transcripcion.jsonl}
  local carga
  carga=$(printf '{"cwd":%s,"transcript_path":%s,"tool_input":{"command":%s}}' \
    "$(printf '%s' "$cwd" | jq -Rs .)" \
    "$(printf '%s' "$trans" | jq -Rs .)" \
    "$(printf '%s' "$cmd" | jq -Rs .)")
  if [ "$modo" = --aviso ]; then
    printf '%s' "$carga" | HOME="$CASA" bash "$hook" --aviso 2>/dev/null
  else
    printf '%s' "$carga" | HOME="$CASA" bash "$hook" >/dev/null 2>&1
  fi
}

CASA="$TMP/casa-por-defecto"; mkdir -p "$CASA"

probar() {           # probar <BLOQUEA|PASA> <descripción> <cwd> <comando>
  local esperado=$1 desc=$2 cwd=$3 cmd=$4 real
  lanzar gate "$cwd" "$cmd"
  if [ $? -eq 2 ]; then real=BLOQUEA; else real=PASA; fi
  if [ "$real" = "$esperado" ]; then
    printf '  ok    %-7s %s\n' "$real" "$desc"
  else
    printf '  FALLO esperaba %s y dio %s: %s\n' "$esperado" "$real" "$desc"
    fallos=$((fallos + 1))
  fi
}

caso() { printf '\n--- %s ---\n' "$1"; }

# La otra sesión: dos procesos (el envoltorio y el claude que cuelga de él),
# como en la realidad, para que se pruebe también que se cuentan como UNA.
OTRA="4001,1,05:00,$REPO;4002,4001,05:00,$REPO"
# Y yo, para que el hook se reconozca y no se cuente como inquilino ajeno.
MIO="$YO,$YO_PADRE,10:00,$REPO"

# ════════════════════════════════════════════════════════════════════════════
caso "con otra sesión en la misma raíz, los verbos que mueven el árbol se paran"
export SESIONES="$OTRA"
for v in 'commit -m x' 'checkout main' 'reset --hard' 'restore f' 'stash' \
         'pull' 'rebase main' 'add -A' 'switch main' 'merge otra' \
         'cherry-pick abc123' 'clean -fd' 'mv a b' 'rm f' 'revert abc123' \
         'am parche' 'apply parche'; do
  probar BLOQUEA "git $v" "$REPO" "git $v"
done

caso "…y los que solo leen, no"
for v in 'status' 'diff' 'log --oneline' 'show HEAD' 'fetch origin --prune' \
         'branch -D una-rama' 'worktree add .claude/worktrees/wtx -b x' \
         'worktree remove .claude/worktrees/wtx' 'rev-parse HEAD' \
         'merge-base main otra'; do
  probar PASA "git $v" "$REPO" "git $v"
done

caso "quién estorba y quién no"
export SESIONES="$OTRA"
probar BLOQUEA "la otra está en la raíz, y yo también"          "$REPO" 'git commit -m x'
probar BLOQUEA "la otra está en un SUBDIRECTORIO de la misma raíz" "$REPO/sub" 'git commit -m x'
export SESIONES="4001,1,05:00,$REPO/sub;4002,4001,05:00,$REPO/sub"
probar BLOQUEA "…y al revés: yo en la raíz, ella en el subdirectorio" "$REPO" 'git commit -m x'
export SESIONES="4001,1,05:00,$OTRO;4002,4001,05:00,$OTRO"
probar PASA    "la otra está en OTRO repositorio"                "$REPO" 'git commit -m x'
export SESIONES="4001,1,05:00,$TMP/wt;4002,4001,05:00,$TMP/wt"
probar PASA    "la otra está en un worktree: otra raíz, no estorba" "$REPO" 'git commit -m x'
export SESIONES=""
probar PASA    "no hay ninguna otra sesión"                      "$REPO" 'git commit -m x'
export SESIONES="$OTRA"
probar PASA    "fuera de un repositorio no hay nada que proteger" "$FUERA" 'git commit -m x'

caso "una sesión sola no se bloquea a sí misma"
# Lo que ninguna otra prueba puede ver: si el hook no se reconoce en la lista,
# cada sesión se toma a sí misma por la inquilina de al lado y bloquea todo git.
export SESIONES="$MIO"
probar PASA "el único claude vivo soy yo" "$REPO" 'git commit -m x'
export SESIONES="$MIO;$OTRA"
probar BLOQUEA "yo y una de verdad: esa sí cuenta" "$REPO" 'git commit -m x'

caso "un proceso recién nacido no es una sesión"
# La app lanza `claude` sueltos que viven milisegundos. Pillar uno en el `ps`
# significaba bloquear un commit citando un pid ya muerto.
export SESIONES="4001,1,00:03,$REPO"
probar PASA "menos de 10 s de vida: no cuenta"     "$REPO" 'git commit -m x'
export SESIONES="4001,1,00:12,$REPO"
probar BLOQUEA "12 s ya cuenta"                    "$REPO" 'git commit -m x'
export SESIONES="4001,1,01-02:03:04,$REPO"
probar BLOQUEA "con días de vida, cuenta"          "$REPO" 'git commit -m x'

caso "una pestaña vieja no es una inquilina"
export SESIONES="$OTRA"
CASA=$(casa reciente "$REPO" 5)
probar BLOQUEA "transcripción tocada hace 5 min"   "$REPO" 'git commit -m x'
CASA=$(casa vieja "$REPO" 600)
probar PASA    "transcripción de hace 10 h (TTL 4 h)" "$REPO" 'git commit -m x'
CASA=$(casa sin-carpeta "$REPO")
probar BLOQUEA "sin carpeta de transcripciones, el proceso vivo basta" "$REPO" 'git commit -m x'

# Y la transcripción PROPIA no cuenta como señal de vida ajena: si contara, uno
# se bloquearía a sí mismo cada vez que la otra pestaña estuviera parada.
CASA=$(casa solo-la-mia "$REPO" 5)
mi_jsonl="$CASA/.claude/projects/$(printf '%s' "$REPO" | sed 's/[/.]/-/g')/sesion.jsonl"
if lanzar gate "$REPO" 'git commit -m x' "$mi_jsonl"; then
  printf '  ok    %-7s %s\n' PASA "la única transcripción reciente es la mía"
else
  printf '  FALLO esperaba PASA y dio BLOQUEA: la única transcripción reciente es la mía\n'
  fallos=$((fallos + 1))
fi
CASA="$TMP/casa-por-defecto"

caso "a qué repositorio apunta el comando"
export SESIONES="$OTRA"
probar PASA    "git -C <otro-repo> desde aquí: juzga el otro"  "$REPO" "git -C $OTRO commit -m x"
probar PASA    "cd <otro-repo> && git: igual"                  "$REPO" "cd $OTRO && git commit -m x"
probar BLOQUEA "git -C <este-repo> desde fuera"                "$FUERA" "git -C $REPO commit -m x"
probar BLOQUEA "cd <este-repo> && git desde fuera"             "$FUERA" "cd $REPO && git commit -m x"
probar BLOQUEA "un cd a ninguna parte no absuelve"             "$REPO" 'cd /no-existe && git commit -m x'

caso "la escotilla"
export SESIONES="$OTRA"
probar PASA "escrita delante del comando" "$REPO" 'CLAUDE_ALLOW_SHARED_CHECKOUT=1 git commit -m x'
if ( export CLAUDE_ALLOW_SHARED_CHECKOUT=1
     printf '{"cwd":"%s","tool_input":{"command":"git commit -m x"}}' "$REPO" |
       HOME="$CASA" bash "$hook" >/dev/null 2>&1 ); then
  printf '  ok    %-7s %s\n' PASA "exportada en el entorno"
else
  printf '  FALLO esperaba PASA y dio BLOQUEA: exportada en el entorno\n'
  fallos=$((fallos + 1))
fi

caso "el modo --aviso no bloquea nunca"
export SESIONES="$OTRA"
salida=$(lanzar --aviso "$REPO" ""); codigo=$?
if [ $codigo -eq 0 ]; then
  printf '  ok    %-7s %s\n' PASA "sale 0 aunque haya otra sesión"
else
  printf '  FALLO esperaba salir 0 y salió %s: modo --aviso\n' "$codigo"; fallos=$((fallos + 1))
fi
if printf '%s' "$salida" | grep -q "AVISO"; then
  printf '  ok    %-7s %s\n' PASA "y lo dice por la salida estándar"
else
  printf '  FALLO el aviso no menciona la otra sesión\n'; fallos=$((fallos + 1))
fi
if printf '%s' "$salida" | grep -q "worktree"; then
  printf '  ok    %-7s %s\n' PASA "y propone el worktree como remedio"
else
  printf '  FALLO el aviso no propone el worktree\n'; fallos=$((fallos + 1))
fi
export SESIONES=""
salida=$(lanzar --aviso "$REPO" "")
if [ -z "$salida" ]; then
  printf '  ok    %-7s %s\n' PASA "sin otra sesión, se calla"
else
  printf '  FALLO habla sin haber otra sesión: %s\n' "$salida"; fallos=$((fallos + 1))
fi

caso "lo que no es un comando"
export SESIONES="$OTRA"
if printf '{"cwd":"%s","tool_input":{}}' "$REPO" | HOME="$CASA" bash "$hook" >/dev/null 2>&1; then
  printf '  ok    %-7s %s\n' PASA "sin comando en la carga, no opina"
else
  printf '  FALLO esperaba PASA y dio BLOQUEA: sin comando en la carga\n'; fallos=$((fallos + 1))
fi
probar PASA "un comando que no es git"        "$REPO" 'npm test'
probar PASA "git nombrado dentro de un texto" "$REPO" 'echo "acuérdate de git commit"'

echo
[ $fallos -eq 0 ] && echo "TODO BIEN: 0 fallos" || echo "$fallos FALLOS"
exit $fallos
