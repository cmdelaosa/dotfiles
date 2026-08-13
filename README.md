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
| `claude/hooks/git-no-main.sh` | Rechaza `commit`/`merge`/`push` estando en `main`. La protección de rama de GitHub pide plan de pago y estos repositorios son privados en el gratuito: esto es lo único que hay |
| `claude/hooks/git-una-sesion-por-checkout.sh` | Rechaza los verbos que mueven árbol o índice cuando hay otra sesión viva en la misma raíz de git, y lo avisa al arrancar |
| `claude/hooks/dotfiles-al-dia.sh` | Avisa si la máquina y este repositorio han dejado de coincidir |
| `claude/bin/` | `abrir-rama.sh`, `probar-rama.sh`, `marcar-revisado.sh`, `cerrar-rama.sh` y su matriz `probar-ramas.sh`: el flujo entero de rama → PR → fusión |
| `claude/skills/` | `rama`, `probar`, `cerrar`, `despliega`, `grill-me`, `new-project` |
| `verificar.sh` | Sintaxis de todos los guiones y las dos matrices de pruebas. Lo lanza `probar-rama.sh` antes de empujar, así que un lint roto se ve aquí y no doce minutos después en el CI |
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

## La trampa

`settings.json` **lo reescribe la propia app** cuando cambias de modelo, de estilo de
salida o de plugins. Si esa escritura borra y crea el fichero en vez de escribir
encima, se lleva el enlace por delante: la máquina sigue funcionando, el repositorio
se queda con una copia vieja, y no hay ningún diff que lo cuente — que es justo el
problema que este repositorio venía a resolver.

Por eso `comprobar.sh` no mira el contenido: mira que **siga siendo un enlace**. Y por
eso lo llama un hook de `SessionStart`, para que la respuesta llegue sin que nadie
tenga que acordarse de preguntar.

## Al tocar los guiones de `claude/bin/`

`~/.claude/bin/probar-rama.sh` es un **enlace al checkout de `main`**, así que
lanzarlo desde un worktree prueba el guión de antes de tu cambio y no el tuyo. Se
nota poco y engaña mucho: la primera vez que se estrenaron los frenos de
`verificar.sh` y de la revisión, la PR se abrió sin que ninguno de los dos llegara
a correr, y por fuera parecía que habían pasado.

Desde una rama de este repositorio, el guión que vale es **el del worktree**:

```bash
./claude/bin/probar-rama.sh <rama>
```

Es la misma regla que el `HOOK=` de `probar-git-no-main.sh`, y por el mismo motivo.

## Al tocar un hook

- Un hook `PreToolUse` que sale con **2 bloquea la herramienta**, y bash sale con 2
  ante un error de sintaxis: una errata aquí bloquea todo git. **`/bin/bash -n` antes
  de commitear**, y con `/bin/bash` (el 3.2 de Apple), no con el de Homebrew: el 3.2
  no cierra bien un `case` dentro de `$( )` sin paréntesis de apertura en el patrón, y
  el 5.x lo acepta sin rechistar.
- Los cambios en `settings.json` y en los hooks **no valen para las sesiones ya
  abiertas**: se leen al arrancar. Basta con abrir una pestaña nueva.
