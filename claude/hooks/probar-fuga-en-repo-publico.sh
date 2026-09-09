#!/bin/bash
# Prueba fuga-en-repo-publico.sh contra una matriz. Monta sus propios repos:
# uno «público», uno «privado» y uno del que no se sabe, porque el hook aplica
# listones distintos a cada uno y esa es justo la parte que puede salir mal.
#
# La visibilidad se siembra ESCRIBIENDO la memoria que el hook consulta
# (`<git-dir>/visibilidad-remoto`), no llamando a `gh`: una matriz que necesita
# red no se puede lanzar en el CI ni en un avión, y acabaría desactivada.
#
# Por defecto el hook de AL LADO, no el instalado: `~/.claude/hooks` es un enlace
# a la RAÍZ del repositorio, así que probar el instalado desde un worktree juzga
# la versión de main y da un verde falso justo en el caso normal. HOOK=<ruta>
# prueba otro.
set -uo pipefail

aqui=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
hook=${HOOK:-$aqui/fuga-en-repo-publico.sh}
fallos=0

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# montar <nombre> <visibilidad|->  → deja el repo en $TMP/<nombre>
montar() {
  local d="$TMP/$1"
  git init -q -b main "$d"
  git -C "$d" config user.email t@t
  git -C "$d" config user.name t
  printf 'inicial\n' > "$d/README.md"
  git -C "$d" add -A
  git -C "$d" commit -qm inicial
  [ "$2" = "-" ] || printf '%s' "$2" > "$d/.git/visibilidad-remoto"
}

# probar <repo> <esperado> <qué> <fichero> <contenido> [orden]
# Escribe el fichero, lo añade al índice y juzga el `git commit`.
probar() {
  local repo=$1 esperado=$2 que=$3 fichero=$4 contenido=$5
  local orden=${6:-git commit -m prueba}
  local d="$TMP/$repo"
  printf '%s\n' "$contenido" > "$d/$fichero"
  git -C "$d" add -A 2>/dev/null
  local real codigo
  printf '{"cwd":%s,"tool_input":{"command":%s}}' \
    "$(printf '%s' "$d" | jq -Rs .)" "$(printf '%s' "$orden" | jq -Rs .)" |
    bash "$hook" > /dev/null 2>&1
  codigo=$?
  if [ $codigo -eq 2 ]; then real=BLOQUEA; else real=PASA; fi
  if [ "$real" = "$esperado" ]; then
    printf '  ok    %-7s %s\n' "$real" "$que"
  else
    printf '  FALLO esperaba %s y dio %s: %s\n' "$esperado" "$real" "$que"
    fallos=$((fallos + 1))
  fi
  # El índice se limpia entre casos, o el hallazgo de uno contaminaría el
  # siguiente y toda la matriz saldría en rojo detrás del primer bloqueo.
  git -C "$d" reset -q --hard HEAD 2>/dev/null
  rm -f "$d/$fichero"
}

montar publico si
montar privado no
montar sinsaber -

echo "--- credenciales: en cualquier repositorio, mire quien mire ---"
probar publico BLOQUEA "clave privada"          k.txt '-----BEGIN OPENSSH PRIVATE KEY-----'
probar privado BLOQUEA "clave privada (privado)" k.txt '-----BEGIN RSA PRIVATE KEY-----'
probar sinsaber BLOQUEA "clave privada (sin saber la visibilidad)" k.txt '-----BEGIN PRIVATE KEY-----'
probar publico BLOQUEA "token de GitHub"        c.txt 'GH_TOKEN=ghp_abcdefghijklmnopqrstuvwxyz0123'
probar privado BLOQUEA "token de GitHub (privado)" c.txt 'token: github_pat_11ABCDEFG0abcdefghijklmnop'
probar publico BLOQUEA "clave de AWS"           c.txt 'AKIAIOSFODNN7EXAMPLE'
probar publico BLOQUEA "identidad de age"       c.txt 'AGE-SECRET-KEY-1QQPQZRFQ7X8VJ4KLM9NPZ2WXYT'
probar publico BLOQUEA "contraseña con valor de verdad" c.txt 'password: "s3cr3t0LargoDeVerdad123"'
probar publico BLOQUEA "fichero .env"           .env 'FOO=bar'
probar publico BLOQUEA "fichero .env.local"     .env.local 'DB_HOST=db.interno'
probar privado BLOQUEA "fichero .pem"           id.pem 'lo que sea'

echo "--- ...pero lo que se escribe BIEN no se marca ---"
# Este es el falso positivo que apagaría el hook: así es como se escribe una
# credencial que no está en el repositorio.
probar publico PASA "token por variable"        c.sh 'TOKEN=$GITHUB_TOKEN'
probar publico PASA "contraseña por variable"   c.sh 'password: ${PGPASSWORD}'
probar publico PASA "un .env.example"           .env.example 'FOO=pon-aqui-lo-tuyo'
probar publico PASA "un .env.dist"              .env.dist 'FOO=pon-aqui-lo-tuyo'
# En español, que es como están escritos estos repositorios. Faltaban, y por
# eso `erp` tuvo que renombrar su plantilla para poder commitearla.
probar publico PASA "un .env.ejemplo"           .env.ejemplo 'FOO=pon-aqui-lo-tuyo'
probar publico PASA "un .env.plantilla"         .env.plantilla 'FOO=pon-aqui-lo-tuyo'
probar publico PASA "un env.ejemplo, sin punto" env.ejemplo 'FOO=pon-aqui-lo-tuyo'
# Y la plantilla no es una barra libre: el nombre la exime de la lista de
# nombres, no del repaso del CONTENIDO. Una plantilla con una credencial de
# verdad dentro es el descuido exacto que este hook existe para cazar.
probar publico BLOQUEA "una clave DENTRO de la plantilla" \
       .env.ejemplo 'AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE'
# El fichero de verdad sigue bloqueado, que es de lo que va todo esto.
probar publico BLOQUEA "el .env de verdad"      .env 'POSTGRES_PASSWORD=lo-que-sea'
probar publico PASA "prosa que habla de tokens" doc.md 'El token se lee de la variable, nunca del fichero.'

echo "--- datos de la máquina: solo pesan en un repositorio PÚBLICO ---"
probar publico  BLOQUEA "IP privada"            c.txt 'ProxyPass http://192.168.1.44:8080/'
probar privado  PASA    "IP privada (privado)"  c.txt 'ProxyPass http://192.168.1.44:8080/'
probar publico  BLOQUEA "ruta de servidor"      c.sh  'cd /opt/welzy && docker compose up'
probar privado  PASA    "ruta de servidor (privado)" c.sh 'cd /opt/welzy && docker compose up'
probar publico  BLOQUEA "host de la infraestructura" c.sh 'ssh ssh.cmdlo.com true'
probar privado  PASA    "host de la infraestructura (privado)" c.sh 'ssh ssh.cmdlo.com true'
probar publico  BLOQUEA "usuario@host"          c.sh 'scp fichero deploy@servidor.ejemplo.com:/tmp/'
probar sinsaber PASA    "IP privada, sin saber la visibilidad" c.txt 'http://10.0.0.5:8080/'

echo "--- lo que en este repositorio es normal y no se toca ---"
# `/Users/cmo/...` está por todo dotfiles a propósito: los hooks se instalan con
# ruta absoluta. Marcarlo sería marcar el fichero cada vez.
probar publico PASA "ruta local del Mac"        s.json '"command": "/Users/cmo/.claude/hooks/git-no-main.sh"'
probar publico PASA "código corriente"          a.ts   'export const suma = (a: number, b: number) => a + b'
probar publico PASA "un dominio público a secas" doc.md 'La documentación está en https://docs.github.com/es'

echo "--- el nombre del fichero no puede esconderlo ---"
# La lista de ficheros se leia partida por espacios, asi que este se leia como
# dos que no existen y su contenido no lo miraba nadie: rc=0 con una clave de
# AWS dentro. Y sin `core.quotePath=false`, el de los acentos salia escapado.
probar publico BLOQUEA "nombre con espacios"    "mi fichero.txt" 'AKIAIOSFODNN7EXAMPLE'
probar publico BLOQUEA "nombre con acentos"     "configuracion-ñ.txt" 'AKIAIOSFODNN7EXAMPLE'

echo "--- lo que ni siquiera es un commit ---"
probar publico PASA "git status"                c.txt 'AKIAIOSFODNN7EXAMPLE' 'git status'
probar publico PASA "git add"                   c.txt 'AKIAIOSFODNN7EXAMPLE' 'git add -A'
# La misma familia que el agujero del heredoc en git-no-main.sh: prosa que
# NOMBRA un commit no es un commit. Sin esto, escribir un guión que mencione
# `git commit` —el propio hook, sin ir más lejos— se juzgaría como si commiteara.
probar publico PASA "un heredoc que menciona git commit" c.txt 'AKIAIOSFODNN7EXAMPLE' \
  'cat > guion.sh <<EOF
git commit -m "esto es texto"
EOF'

echo "--- la escotilla ---"
probar publico PASA "con el visto bueno de Carlos" k.txt '-----BEGIN OPENSSH PRIVATE KEY-----' \
  'CLAUDE_ALLOW_FUGA=1 git commit -m prueba'

echo "--- el repositorio lo elige la orden, no el directorio ---"
# Igual que git-no-main.sh: con `-C`, lo que se mira es el repo APUNTADO. Si se
# mirara el cwd, un commit con `-C` a otro repositorio pasaría sin que nadie
# hubiera leído su diff.
printf 'AKIAIOSFODNN7EXAMPLE\n' > "$TMP/publico/c.txt"
git -C "$TMP/publico" add -A
salida_codigo=0
printf '{"cwd":%s,"tool_input":{"command":%s}}' \
  "$(printf '%s' "$TMP/privado" | jq -Rs .)" \
  "$(printf 'git -C %s commit -m x' "$TMP/publico" | jq -Rs .)" |
  bash "$hook" > /dev/null 2>&1 || salida_codigo=$?
if [ "$salida_codigo" -eq 2 ]; then
  printf '  ok    %-7s %s\n' BLOQUEA "git -C <repo-público> commit desde otro repo"
else
  printf '  FALLO esperaba BLOQUEA y dio PASA: git -C <repo-público> commit desde otro repo\n'
  fallos=$((fallos + 1))
fi
git -C "$TMP/publico" reset -q --hard HEAD

echo "--- con -a entra lo que no está en el índice, y también se mira ---"
printf 'seguido\n' > "$TMP/publico/seguido.txt"
git -C "$TMP/publico" add -A
git -C "$TMP/publico" commit -qm "fichero seguido"
printf 'ghp_abcdefghijklmnopqrstuvwxyz0123\n' > "$TMP/publico/seguido.txt"
for caso in "git commit -m x:PASA" "git commit -am x:BLOQUEA" "git commit -a -m x:BLOQUEA"; do
  orden=${caso%:*}; esperado=${caso##*:}
  codigo=0
  printf '{"cwd":%s,"tool_input":{"command":%s}}' \
    "$(printf '%s' "$TMP/publico" | jq -Rs .)" "$(printf '%s' "$orden" | jq -Rs .)" |
    bash "$hook" > /dev/null 2>&1 || codigo=$?
  if [ "$codigo" -eq 2 ]; then real=BLOQUEA; else real=PASA; fi
  if [ "$real" = "$esperado" ]; then
    printf '  ok    %-7s %s\n' "$real" "$orden (modificado sin añadir)"
  else
    printf '  FALLO esperaba %s y dio %s: %s\n' "$esperado" "$real" "$orden"
    fallos=$((fallos + 1))
  fi
done

echo "--- y el MENSAJE no amplia el alcance ---"
# Un mensaje que HABLA del flag `-a` no pide `-a`. Antes de mirar la orden sin
# lo entrecomillado, esa frase llevaba el alcance a HEAD y bloqueaba por un
# fichero que no entra en el commit — el falso positivo que apaga un hook.
printf 'limpio\n' > "$TMP/publico/otro.txt"
git -C "$TMP/publico" add otro.txt
for caso in 'git commit -m "arregla el flag -a de la CLI":PASA' \
            'git commit -m "sin banderas":PASA' \
            'git commit -am "esto si lleva -a":BLOQUEA'; do
  orden=${caso%:*}; esperado=${caso##*:}
  codigo=0
  printf '{"cwd":%s,"tool_input":{"command":%s}}' \
    "$(printf '%s' "$TMP/publico" | jq -Rs .)" "$(printf '%s' "$orden" | jq -Rs .)" |
    bash "$hook" > /dev/null 2>&1 || codigo=$?
  if [ "$codigo" -eq 2 ]; then real=BLOQUEA; else real=PASA; fi
  if [ "$real" = "$esperado" ]; then
    printf '  ok    %-7s %s\n' "$real" "$orden"
  else
    printf '  FALLO esperaba %s y dio %s: %s\n' "$esperado" "$real" "$orden"
    fallos=$((fallos + 1))
  fi
done

echo
[ $fallos -eq 0 ] && echo "TODO BIEN: 0 fallos" || echo "$fallos FALLOS"
exit $fallos
