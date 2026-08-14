---
name: rama
description: Abre una rama nueva y su worktree con ~/.claude/bin/abrir-rama.sh y mete la sesión dentro. Usar SIEMPRE antes del primer cambio de cualquier tarea que vaya a tocar ficheros, y cuando el usuario diga "abre una rama", "trabaja en una rama", "empieza una rama" o "/rama".
---

# Abrir una rama

**Antes de tocar el primer fichero.** No es una cortesía: dos sesiones en el
mismo checkout comparten HEAD, índice y árbol, y la de al lado se lleva por
delante lo que tengas a medias sin que nadie se entere.

```bash
~/.claude/bin/abrir-rama.sh <nombre-de-la-rama>
```

Imprime **una línea en la salida estándar: la ruta del worktree**. Entra ahí con
`EnterWorktree` pasándole esa ruta en `path`, y trabaja dentro y solo dentro.

## El nombre

Dice qué hay dentro, en minúsculas y con guiones: `retenciones-como-gasto`,
`arreglar-el-activity-log`. **Nunca** `fix`, `wip`, `cambios`, ni el nombre que
inventa el harness (`sleepy-pare-10a9f6`) — el script lo rechaza, porque con
cuatro worktrees abiertos no hay forma de saber cuál tiene qué sin entrar.

## Si la sesión ya nació dentro de un worktree

Pasa a menudo: la app abre la sesión en `.claude/worktrees/<nombre-inventado>`,
en la rama `claude/<nombre-inventado>`. Es el mismo directorio que usa
`abrir-rama.sh` con el único nombre que rechaza, solo que nadie llegó a
preguntárselo. **Múdate antes de tocar el primer fichero**, en este orden y con
cada orden de git suelta:

```bash
~/.claude/bin/abrir-rama.sh <nombre-de-la-rama>
```

`EnterWorktree` con la ruta que imprime, y luego:

```bash
git -C <repo> worktree remove .claude/worktrees/<nombre-inventado>
```

```bash
git -C <repo> branch -D claude/<nombre-inventado>
```

No se pierde nada: esa rama está en el commit de `main` y sin nada encima.

## Si se niega

- **«la rama ya existe»** → esa tarea ya está empezada. Mira
  `git worktree list` y entra en su worktree en vez de abrir otro.
- **«no está en el .gitignore»** → avísalo al usuario y añade
  `.claude/worktrees/` al `.gitignore` del repositorio en el primer commit.

## Lo que NO hay que hacer

- No `git checkout -b` a mano: eso deja la rama sin worktree y la sesión en la
  raíz, que es de donde venimos.
- No `EnterWorktree` con `name` a secas: el harness inventa el nombre y se pierde
  la correspondencia rama ↔ worktree.
- No trabajar en la raíz «solo para una cosa rápida». La colisión del 13-08-2026
  fue exactamente una cosa rápida.

Al terminar de trabajar, la skill `probar`, que deja la PR abierta y verde para
que la mire su dueño — y le pregunta antes si además quiere la pila local.
`cerrar` solo cuando dé el visto bueno.
