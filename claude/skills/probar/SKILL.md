---
name: probar
description: Deja una rama lista para que el usuario la pruebe con ~/.claude/bin/probar-rama.sh - empuja, abre la PR, espera al CI y levanta la pila local de esa rama con una copia de sus datos. No fusiona nada. Usar al terminar de trabajar en una rama, y cuando el usuario diga "pruébalo", "levántalo", "déjamelo listo" o "/probar".
---

# Dejar una rama lista para probar

Es el primer tiempo del cierre. El segundo es la skill `cerrar`, y **solo lo
lanza el usuario**.

```bash
~/.claude/bin/probar-rama.sh <rama>
```

Empuja, abre la PR si falta, espera al CI y —solo en verde— levanta la pila de
esa rama: proyecto de Compose propio, puerto propio y **una copia** del volumen
de datos del usuario. Después avisa con una notificación del sistema.

El CI de welzy tarda unos 12 minutos: **lánzalo con `run_in_background`** y sigue
a lo tuyo. Cuando termine, dile al usuario la URL y que la PR está esperando.

## Cómo leer lo que diga

- **«Lista para probar: http://127.0.0.1:…»** → dale la URL al usuario y **para
  ahí**. No cierres, no fusiones, no despliegues: falta que lo mire.
- **«El CI no está verde»** → enseña los jobs con sus enlaces. No ha levantado
  nada. Arregla en el worktree, commitea y vuelve a lanzarlo.
- **«no ha disparado ningún check»** → normalmente el `paths-ignore` de una PR de
  solo documentación. No levanta nada; la PR queda esperando al usuario.
- **«La pila no responde»** → pásale al usuario la salida de
  `docker compose -p <proyecto> logs`.

## Lo que hay que tener claro

- **Los datos son una copia.** La pila de siempre del usuario no se toca, y una
  migración de Flyway de la rama se aplica sobre la copia. Se puede decir con
  esas palabras: da tranquilidad y es verdad.
- Si hay que cambiar algo después de probar, se cambia **en la rama** y se
  relanza esto. Ese es justo el motivo de que exista: que main reciba una fusión
  limpia en vez de tres commits arreglando lo que se vio al probar.
- Dos ramas pueden estar levantadas a la vez, cada una en su puerto.
