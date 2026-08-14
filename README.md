# dotfiles

La configuración de la máquina que hasta ahora solo existía en un sitio: dentro de
`~/.claude`, sin historia, sin revisión y sin nada que avisara si cambiaba. Hoy son
enlaces simbólicos a este repositorio, así que cualquier cambio es un diff.

El empujón fue el 13-08-2026: la única barrera que impide que dos sesiones de Claude
se pisen en un mismo checkout es un hook que vivía aquí dentro, en un directorio que
nadie versionaba. Una barrera que se puede apagar sin dejar rastro no es una barrera.

```bash
git clone https://github.com/cmdelaosa/dotfiles.git ~/Projects/dotfiles
~/Projects/dotfiles/instalar.sh
```

`instalar.sh` es idempotente y **no pisa nada**: lo que encuentre como fichero de
verdad lo aparta con fecha antes de enlazar. `comprobar.sh` dice si `~/.claude`
sigue viniendo de aquí, y `verificar.sh` dice si un cambio de este repositorio se
sostiene: son dos preguntas distintas y por eso son dos guiones.

## Qué hay dentro

| | |
|---|---|
| `claude/CLAUDE.md` | Las instrucciones globales: cómo informar, ramas y PR, worktrees, planificación |
| `claude/settings.json` | Modelo, estilo de salida, permisos y **los hooks** |
| `claude/hooks/git-no-main.sh` | Rechaza `commit`/`merge`/`push` estando en `main`. En los repositorios privados sigue siendo **lo único que hay**: la protección de rama de GitHub pide plan de pago o repositorio público. Aquí ya no (ver abajo) |
| `claude/hooks/git-una-sesion-por-checkout.sh` | Rechaza los verbos que mueven árbol o índice cuando hay otra sesión viva en la misma raíz de git, y lo avisa al arrancar |
| `claude/hooks/dotfiles-al-dia.sh` | Avisa si la máquina y este repositorio han dejado de coincidir |
| `claude/hooks/probar-*.sh` | Las matrices de los dos hooks bloqueantes (64 y 57 casos) |
| `claude/bin/abrir-rama.sh` | Abre la rama **y** su worktree `wt<rama>` desde `origin/<principal>` recién traído, y rechaza los nombres que no dicen nada |
| `claude/bin/probar-rama.sh` | Lanza el `verificar.sh` de la rama, exige que el diff esté revisado, empuja, abre la PR y espera al CI. No fusiona nunca, y **no levanta nada** si no se pide: con `--con-pila` (o `--solo-pila` después) monta la pila local de esa rama con una **copia** de los datos |
| `claude/bin/marcar-revisado.sh` | Sella el HEAD que ya ha pasado por el revisor. Caduca con el commit siguiente, que es lo que hace que el sello signifique algo |
| `claude/bin/cerrar-rama.sh` | Recomprueba el verde, comprueba que no es anterior al `main` de ahora, fusiona, despliega si el repo tiene el contrato de cmdlo, y limpia pila, worktree y las dos ramas |
| `claude/bin/lib-ramas.sh` | Lo que comparten los tres: resolver el repo, los frenos, el CI, la pila |
| `claude/bin/probar-ramas.sh` | La matriz de los cuatro (196 casos), con GitHub, Docker, curl y nc de mentira |
| `claude/skills/` | `rama`, `probar`, `cerrar` (el flujo de ramas), más `despliega`, `grill-me` y `new-project` |
| `verificar.sh` | Sintaxis de todos los guiones y las tres matrices. Lo lanza `probar-rama.sh` antes de empujar, así que un error se ve aquí y no doce minutos después en el CI |
| `.github/workflows/ci.yml` | Un trabajo, y es **este mismo `verificar.sh`**. El verde de la PR y el de tu portátil son la misma pregunta, no dos listas que se desincronizan |
| `claude/output-styles/concise.md` | El estilo que referencia `settings.json`; sin él, la referencia queda coja |
| `claude/templates/project/` | El esqueleto que usa el skill `new-project` |

## Qué se queda fuera, a propósito

`~/.claude` es sobre todo estado, no configuración, y casi todo es privado:

- **`projects/`**: 1,5 GB de transcripciones de conversaciones, más los ficheros de
  memoria. Ni cabe ni debe salir de la máquina.
- **`plugins/`, `cache/`, `sessions/`, `session-env/`, `shell-snapshots/`,
  `telemetry/`, `history.jsonl`, `tasks/`, `plans/`, `scheduled-tasks/`,
  `backups/`, `stats-cache.json`**: estado que la app regenera.
- Nada con credenciales: las de Claude viven en el llavero de macOS y las de `gh` en
  su propio llavero. **Si algún día aparece un fichero con un token dentro de
  `~/.claude`, no lo enlaces aquí.**

## Este repositorio es público, y no por presumir

Se hizo público el 14-08-2026 porque el CI no arrancaba: los trabajos morían en
dos segundos sin runner asignado y con los logs vacíos, que es como se ve
quedarse sin los minutos incluidos de Actions en un repositorio privado del plan
gratuito. En público son ilimitados, y el mismo commit pasó a verde en 28
segundos sin tocar una línea del workflow.

Lo segundo vino de regalo y vale más: **`main` tiene protección del lado del
servidor**, que en privado pedía plan de pago. Hace falta una PR, `verificar.sh`
tiene que pasar, la rama tiene que estar al día con `main` —el mismo verde
caducado que `cerrar-rama.sh` ya vigilaba, ahora también desde GitHub—, y no se
admiten ni `--force` ni borrar `main`. **Con los administradores dentro**: aquí
`CLAUDE_ALLOW_MAIN=1` ya no compra un push directo, porque el que frena es
GitHub y no el hook.

Lo que eso expone, dicho claro: el correo de los commits, las rutas
`/Users/cmo/…` y los nombres de los proyectos privados que se mencionan en los
comentarios. Ninguna credencial — se comprobó la historia entera antes de
pulsar el botón, y el criterio de qué no entra aquí sigue estando dos secciones
más arriba.

## La trampa

`settings.json` **lo reescribe la propia app** cuando cambias de modelo, de estilo de
salida o de plugins. Si esa escritura borra y crea el fichero en vez de escribir
encima, se lleva el enlace por delante: la máquina sigue funcionando, el repositorio
se queda con una copia vieja, y no hay ningún diff que lo cuente — que es justo el
problema que este repositorio venía a resolver.

Por eso `comprobar.sh` no mira el contenido: mira que **siga siendo un enlace**. Y por
eso lo llama un hook de `SessionStart`, para que la respuesta llegue sin que nadie
tenga que acordarse de preguntar.

## Al tocar un hook o un guión de ramas

- **Lanza su matriz, y rómpela a propósito para verla fallar.** Cada pieza tiene la
  suya al lado: `claude/hooks/probar-git-no-main.sh`,
  `claude/hooks/probar-git-una-sesion.sh` y `claude/bin/probar-ramas.sh`. Las tres
  prueban por defecto **la copia de al lado**, que en un worktree es la que acabas de
  escribir. `~/.claude/hooks` y `~/.claude/bin` son enlaces a la **raíz** del
  repositorio, o sea a `main`: hasta el 13-08-2026 la matriz del hook apuntaba ahí por
  defecto y daba verde sobre un fichero que no había leído. Con `HOOK=<ruta>` se
  prueba el instalado, que es otra pregunta —«¿tiene la máquina lo que creo?»— y
  también vale la pena hacerla.
- **Y lo mismo al lanzar `probar-rama.sh` sobre una rama de este repositorio**: usa
  `./claude/bin/probar-rama.sh`, no el de `~/.claude/bin`, que es el de `main`. La
  primera vez que se estrenaron los frenos de `verificar.sh` y de la revisión, la PR
  se abrió sin que ninguno de los dos llegara a correr y por fuera no se notaba nada.
- **`./verificar.sh` lo lanza todo**: `/bin/bash -n` sobre cada guión y las tres
  matrices. Es también lo que `probar-rama.sh` ejecuta antes de empujar y lo único
  que corre el CI, así que un fallo aquí es un push que no ocurre y una PR que no
  se fusiona.
- **El CI corre en Ubuntu, y eso no es gratis del todo**: `/bin/bash` allí es un
  5.x, no el 3.2 de Apple, así que la comprobación de sintaxis pilla lo de siempre
  pero no lo específico del 3.2 — eso solo lo ve `./verificar.sh` lanzado en el Mac,
  y el propio guión avisa de en cuál está. A cambio, correrlo en Linux encontró algo
  que en macOS no se veía: el hook leía la fecha de las transcripciones con
  `stat -f %m || stat -c %m`, y resulta que en GNU `-f` **no falla** —es «estado del
  sistema de ficheros»— y `%m` es el punto de montaje. Fuera de macOS el hook dejaba
  pasar lo que existe para frenar. Ahora es `date -r <fichero> +%s`, que significa lo
  mismo en los dos.
- Un hook `PreToolUse` que sale con **2 bloquea la herramienta**, y bash sale con 2
  ante un error de sintaxis: una errata aquí bloquea todo git. **`/bin/bash -n` antes
  de commitear**, y con `/bin/bash` (el 3.2 de Apple), no con el de Homebrew: el 3.2
  no cierra bien un `case` dentro de `$( )` sin paréntesis de apertura en el patrón, y
  el 5.x lo acepta sin rechistar.
- Los cambios en `settings.json` y en los hooks **no valen para las sesiones ya
  abiertas**: se leen al arrancar. Basta con abrir una pestaña nueva.

## Lo que las matrices no pueden probar

`probar-ramas.sh` falsea `gh`, `docker`, `curl`, `nc` y el avisador, así que corre en
cualquier sitio y no toca nada de verdad. Lo que eso deja fuera, y hay que probar a
mano de vez en cuando **en welzy**, que es el único repositorio con pila:

```bash
~/.claude/bin/probar-rama.sh <una-rama-de-verdad> --con-pila
```

Y comprobar con los ojos: que `docker volume ls` enseña un `<repo>-<rama>_postgres-data`
nuevo con los datos dentro, que la URL abre la app con tu cartera y no una vacía, que
la notificación llega, y que al cerrar la rama ese volumen desaparece y **el de tu pila
de siempre sigue ahí**. Eso último es lo único de todo esto que puede destruir datos.
