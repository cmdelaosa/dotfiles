---
name: cerrar
description: Cierra una rama que el usuario YA ha probado, con ~/.claude/bin/cerrar-rama.sh - fusiona la PR, despliega a producción y borra la pila local, el worktree y las dos ramas. Usar solo cuando el usuario lo pida con "cierra", "fusiona", "dale el visto bueno" o "/cerrar".
---

# Cerrar una rama

**Esto fusiona y despliega a producción. No lo lances por tu cuenta**: solo
cuando el usuario lo pida con todas las letras. Antes va la skill `probar`, que
deja la PR verde y esperando —y la pila local levantada, si el usuario dijo que
quería probarla ahí—; el visto bueno es que te diga que cierres.

Dos pasos, en este orden:

1. **Sal del worktree**: `ExitWorktree` con `action: "keep"`. El script se niega a
   borrar el directorio desde el que se le llama, y hace bien: borrarlo deja el
   shell en un sitio que ya no existe y el worktree a medio quitar.
2. Desde la raíz del repositorio:

```bash
~/.claude/bin/cerrar-rama.sh <rama>
```

Comprueba que el CI sigue verde, fusiona, despliega con `cmdlo-infra/desplegar.sh`
si el repositorio tiene ese contrato, tumba la pila de la rama con sus volúmenes
de copia y borra worktree, rama local y rama remota.

`--sin-desplegar` fusiona y limpia sin tocar producción. `--solo-limpiar` es para
cuando la PR ya se fusionó por otro camino.

## Cómo leer lo que diga

- **«El CI no está verde»** → enseña los jobs. No ha fusionado ni borrado nada.
- **«no ha disparado ningún check»** → la PR queda abierta a propósito; fusionarla
  sin checks lo decide el usuario. Luego: `cerrar-rama.sh <rama> --solo-limpiar`.
- **«OJO: el despliegue ha fallado»** → **la PR sí está fusionada** y producción
  sigue con lo anterior. Pega la salida entera y para; no reintentes solo.
- **«El worktree tiene cambios sin guardar»** → lista los ficheros. `--forzar` los
  **tira**, así que solo con el sí explícito del usuario.
- **«NO está dentro de origin/main»** → el freno que impide perder commits. Enseña
  el `git log` que imprime y pregunta.

## Lo que NO hay que hacer

- **Nunca `gh pr merge --delete-branch`.** Fusiona en GitHub y luego falla en
  local si un worktree tiene la rama o tiene `main`, dejándola viva y sin decirlo.
- No borrar worktree ni ramas a mano, y menos encadenando con `&&`: el hook
  `git-no-main.sh` mira la línea entera y su excepción de limpieza exige órdenes
  sueltas.
- No cerrar una rama que el usuario no haya probado.
