---
name: cerrar
description: Cierra la rama en la que se ha trabajado con ~/.claude/bin/cerrar-rama.sh - espera al CI, fusiona la PR si está verde y borra worktree, rama local y rama remota. Usar cuando el usuario diga "cierra", "cierra la rama", "fusiona", "mergea la PR" o "/cerrar".
---

# Cerrar una rama

Dos pasos, y en este orden:

1. **Sal del worktree**: `ExitWorktree` con `action: "keep"`. El script se niega
   a borrar el directorio desde el que se le llama, y hace bien: borrarlo deja el
   shell en un sitio que ya no existe y el worktree a medio quitar.
2. Desde la raíz del repositorio:

```bash
~/.claude/bin/cerrar-rama.sh <rama>
```

Empuja, abre la PR si no la había, **espera al CI**, y solo si está verde fusiona
y limpia: worktree fuera, rama local fuera, rama remota fuera, y `main` de la raíz
adelantado.

## Cómo leer lo que diga

- **«El CI no está verde»** → enseña al usuario los jobs y sus enlaces. No ha
  fusionado ni borrado nada. Arregla y vuelve a lanzarlo.
- **«este repositorio no tiene CI»** → la PR queda abierta a propósito. Díselo al
  usuario con el enlace: fusionar sin checks lo decide él, no tú. Cuando la
  fusione: `cerrar-rama.sh <rama> --solo-limpiar`.
- **«El worktree tiene cambios sin guardar»** → lista los ficheros. Commitéalos si
  son parte del trabajo. `--forzar` los **tira**, así que solo con el sí explícito
  del usuario.
- **«NO está dentro de origin/main»** → el freno que impide perder commits.
  Enseña el `git log` que imprime y pregunta antes de nada.
- **«la raíz está en X, no en main»** o **«la raíz tiene cambios sin guardar»** →
  ha limpiado igual, pero no ha adelantado `main`. Repítelo al usuario: suele
  significar que hay otra sesión trabajando ahí.

## Lo que NO hay que hacer

- **Nunca `gh pr merge --delete-branch`.** Fusiona en GitHub y luego falla en
  local si un worktree tiene la rama o tiene `main` — y se calla, dejando la rama
  viva y sin PR.
- No borrar worktree y ramas a mano, y menos encadenando con `&&`: el hook
  `git-no-main.sh` mira la línea entera y la excepción de limpieza exige órdenes
  sueltas.
- No dar la tarea por terminada con el worktree todavía abierto.
