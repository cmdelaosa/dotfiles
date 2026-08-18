#!/bin/bash
# PreToolUse(Bash) — mira lo que un `git commit` va a meter y se planta si trae
# credenciales, o —solo en un repositorio PÚBLICO— datos de la máquina.
#
# Existe porque estuvo a punto de pasar: un `claude/settings.json` con rutas y
# detalles del ERP privado, camino de `cmdelaosa/dotfiles`, que es público. Se
# vio a tiempo y a ojo. La regla de «revisa antes de commitear» ya estaba
# entendida y no frenó nada, que es por lo que esto es un guión y no una línea
# más de instrucciones.
#
# Dos listones, y la diferencia importa:
#
#   SIEMPRE   credenciales — una clave privada, un token, una contraseña. Eso no
#             va a ningún repositorio, ni público ni privado: un repo privado
#             sigue siendo un sitio del que las claves no se pueden retirar.
#   PÚBLICO   contexto de la máquina — IPs privadas, hosts de la infraestructura,
#             rutas de servidor. En un repositorio privado eso es legítimo (el
#             CLAUDE.md de Welzy está lleno, y tiene que estarlo); en uno público
#             es un mapa.
#
# Si no sabe si el repositorio es público —sin remoto, sin `gh`, sin red— aplica
# solo el primer listón. Es a propósito: el lado prudente aquí no es bloquear
# todos los commits de la máquina cuando se cae la red, porque un freno que se
# dispara sin motivo se desactiva a la semana, y entonces tampoco para el otro.
#
# Lo que NO mira: lo ya commiteado. Juzga el diff que está a punto de entrar. Lo
# que ya está dentro se arregla de otra forma, y este hook no es quien avisa.
#
# Escotilla, cuando lo que ha encontrado sea legítimo:
#   CLAUDE_ALLOW_FUGA=1 git commit -m "..."
# Y esa la autoriza Carlos, no el agente: la pregunta que hay que hacerle es si
# ESE dato puede ser público, no si el commit corre prisa.
set -uo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

[ "${CLAUDE_ALLOW_FUGA:-}" = "1" ] && exit 0
case "$cmd" in *CLAUDE_ALLOW_FUGA=1*) exit 0 ;; esac

# Igual que en git-no-main.sh: el cuerpo de un heredoc es TEXTO, no una orden.
# Sin esto, escribir un guión que MENCIONE `git commit` —este mismo, sin ir más
# lejos— se juzgaría como si commiteara.
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

printf '%s' "$orden" | grep -qE '(^|[;&|(]|[[:space:]])git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?(-[^[:space:]]+[[:space:]]+)*commit([[:space:]]|$)' || exit 0

norm=$(printf '%s' "$orden" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')

# A qué repositorio apunta la orden: `-C` manda sobre el `cd`, y el `cd` solo
# cuenta si va DELANTE del git —si no, un mensaje que lo mencione elegiría el
# repositorio que se juzga—. Misma resolución que git-no-main.sh, y por el mismo
# agujero que allí se midió el 13-08-2026.
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] || cwd=$PWD
destino=$cwd

corte=$(printf '%s' "$norm" | awk '{
  if (match($0, /(^|[;&|[:space:]])git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?(-[^[:space:]]+[[:space:]]+)*commit([[:space:]]|$)/))
    print RSTART - 1
  else
    print 0
}')
delante=${norm:0:corte}

apuntada=""
if [[ $norm =~ (^|[[:space:]])git[[:space:]]+-C[[:space:]]+([^[:space:]]+) ]]; then
  apuntada="${BASH_REMATCH[2]}"
elif [[ $delante =~ (^|[;\&\|[:space:]])cd[[:space:]]+([^[:space:]\;\&\|]+) ]]; then
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
[ -d "$destino" ] || destino="$cwd"

git -C "$destino" rev-parse --git-dir > /dev/null 2>&1 || exit 0

# Qué se va a commitear. Con `-a`/`--all` entra también lo modificado sin añadir,
# y si solo se mirara el índice ese sería justo el camino que no ve nadie.
rango="--cached"
case " $norm " in
  *" -a "* | *" --all "* | *" -am "*) rango="HEAD" ;;
esac

ficheros=$(git -C "$destino" diff $rango --name-only 2>/dev/null)
[ -z "$ficheros" ] && exit 0

# ── Listón 1: credenciales. En cualquier repositorio ────────────────────────
# El valor tiene que PARECER una credencial: 16 caracteres o más de material
# opaco. Sin eso, `token = $TOKEN` o `password: ${PGPASS}` —que es como se
# escribe bien— saldría marcado, y un hook que marca lo correcto se apaga.
CREDENCIALES='-----BEGIN [A-Z ]*PRIVATE KEY-----
AGE-SECRET-KEY-1[0-9A-Za-z]+
ghp_[A-Za-z0-9]{20,}
github_pat_[A-Za-z0-9_]{20,}
AKIA[0-9A-Z]{16}
xox[abprs]-[A-Za-z0-9-]{10,}
sk-(ant-)?[A-Za-z0-9_-]{20,}
(password|passwd|secret|token|api[_-]?key|apikey)["'\'' ]*[:=][:=]?["'\'' ]*[A-Za-z0-9/+=_-]{16,}'

# ── Listón 2: contexto de la máquina. Solo si el repositorio es público ─────
# Medido contra el contenido ya commiteado de dotfiles: cero coincidencias en
# todo el repositorio salvo un `ssh.cmdlo.com` en una skill. O sea que esto no
# va a estorbar a diario — y ese único caso es justo de los que hay que mirar.
#
# Lo que NO entra aquí, y es deliberado: `/Users/cmo/...`. Está por todo el repo
# a propósito —los hooks se instalan con ruta absoluta—, así que marcarlo sería
# marcar el fichero entero cada vez, y ese es el camino a que lo desactives.
MAQUINA='(^|[^0-9.])(10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|192\.168\.[0-9]{1,3}\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3})([^0-9]|$)
ssh://[^[:space:]]+
[a-zA-Z0-9_.-]+@[a-z0-9.-]+\.[a-z]{2,}:[^[:space:]]
(^|[[:space:]"'\''=(])/(opt|srv)/[a-z]
[a-z0-9-]+\.cmdlo\.com'

# ── ¿Es público? Se pregunta una vez por repositorio y se apunta ────────────
# `gh` es una llamada de red, y esto corre en CADA commit: sin memoria, cada
# commit pagaría el viaje. La respuesta se guarda en el directorio de git —no se
# commitea, no viaja— y se vuelve a preguntar al mes, que es de sobra para algo
# que casi nunca cambia.
publico=desconocido
comun=$(git -C "$destino" rev-parse --git-common-dir 2>/dev/null)
case "$comun" in
  /*) ;;
  *)  comun="$destino/$comun" ;;
esac
memoria="$comun/visibilidad-remoto"

if [ -f "$memoria" ] && [ -n "$(find "$memoria" -mtime -30 2>/dev/null)" ]; then
  publico=$(cat "$memoria" 2>/dev/null)
elif command -v gh > /dev/null 2>&1; then
  url=$(git -C "$destino" remote get-url origin 2>/dev/null)
  repo_gh=$(printf '%s' "$url" | sed -E 's#^git@github\.com:##; s#^https://github\.com/##; s#\.git$##')
  case "$repo_gh" in
    */*)
      privado=$(GH_NO_UPDATE_NOTIFIER=1 gh repo view "$repo_gh" --json isPrivate -q .isPrivate 2>/dev/null)
      case "$privado" in
        false) publico=si ;;
        true)  publico=no ;;
      esac
      # Solo se apunta una respuesta de verdad: guardar «desconocido» congelaría
      # un fallo de red durante un mes.
      [ "$publico" != desconocido ] && printf '%s' "$publico" > "$memoria" 2>/dev/null
      ;;
  esac
fi

# ── Buscar ──────────────────────────────────────────────────────────────────
# Se mira solo lo AÑADIDO (`^+`): una línea que se borra no filtra nada, y con
# el diff entero un fichero que se mueve saldría marcado por lo que ya tenía.
hallazgos=""
apuntar() {          # apuntar <fichero> <clase> <línea>
  # La línea se enseña RECORTADA y con el material tapado: el aviso va al
  # transcript, y un hook que grita el secreto entero lo copia a un sitio más.
  local muestra
  muestra=$(printf '%s' "$3" | cut -c1-70 |
            sed -E 's/[A-Za-z0-9/+=_-]{16,}/«…tapado…»/g')
  hallazgos="${hallazgos}  $1
      $2: $muestra
"
}

for f in $ficheros; do
  # Un fichero que por su NOMBRE no debería entrar nunca.
  case "$f" in
    *.env.example | *.env.sample | *.env.template) ;;
    *.pem | *.key | *id_rsa | *id_ed25519 | *.p12 | *.pfx | .env | *.env | \
    *.env.production | *credentials.json)
      hallazgos="${hallazgos}  $f
      el nombre ya lo dice: esto no se commitea
"
      continue ;;
  esac

  anadidas=$(git -C "$destino" diff $rango -U0 -- "$f" 2>/dev/null | grep -E '^\+[^+]' | sed 's/^+//')
  [ -z "$anadidas" ] && continue

  while IFS= read -r patron; do
    [ -z "$patron" ] && continue
    linea=$(printf '%s\n' "$anadidas" | grep -E -m1 -e "$patron" 2>/dev/null)
    [ -n "$linea" ] && apuntar "$f" "parece una credencial" "$linea"
  done <<PATRONES
$CREDENCIALES
PATRONES

  [ "$publico" = si ] || continue
  while IFS= read -r patron; do
    [ -z "$patron" ] && continue
    linea=$(printf '%s\n' "$anadidas" | grep -E -m1 -e "$patron" 2>/dev/null)
    [ -n "$linea" ] && apuntar "$f" "dato de la máquina, y este repo es PÚBLICO" "$linea"
  done <<PATRONES
$MAQUINA
PATRONES
done

[ -z "$hallazgos" ] && exit 0

nombre=$(basename "$destino")
printf 'Este commit sobre «%s» mete algo que hay que mirar antes:\n\n%s\n' \
  "$nombre" "$hallazgos" >&2

case "$publico" in
  si) printf '%s\n' \
        "El repositorio es PÚBLICO: lo que entre aquí queda en internet, y" \
        "borrarlo después no lo retira — sigue en el historial y en los clones." >&2 ;;
  no) printf '%s\n' \
        "El repositorio es privado, así que esto no es una fuga a internet." \
        "Sigue siendo una credencial en un historial del que no se puede sacar." >&2 ;;
  *)  printf '%s\n' \
        "No he podido averiguar si el repositorio es público, así que solo he" \
        "mirado credenciales — el listón que vale en los dos casos." >&2 ;;
esac

printf '\n%s\n' \
  "Qué hacer, por orden:" \
  "  1. Sácalo del índice:  git restore --staged <fichero>" \
  "  2. Si es un secreto, muévelo fuera del repositorio y deja en su sitio una" \
  "     referencia (\$VARIABLE, un fichero ignorado, el gestor de contraseñas)." \
  "  3. Si crees que es legítimo, PREGÚNTASELO a Carlos antes de insistir: la" \
  "     pregunta es si ese dato puede ser público, no si el commit corre prisa." \
  "" \
  "Con su visto bueno:" \
  "  CLAUDE_ALLOW_FUGA=1 $cmd" >&2
exit 2
