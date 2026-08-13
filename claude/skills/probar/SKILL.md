---
name: probar
description: Revisa el diff de la rama, aplica lo que salga y la deja lista para que el usuario la pruebe con ~/.claude/bin/probar-rama.sh - empuja, abre la PR, espera al CI y levanta la pila local de esa rama con una copia de sus datos. No fusiona nada. Usar al terminar de trabajar en una rama, y cuando el usuario diga "pruébalo", "levántalo", "déjamelo listo" o "/probar".
---

# Dejar una rama lista para probar

Es el primer tiempo del cierre. El segundo es la skill `cerrar`, y **solo lo
lanza el usuario**.

Son cuatro pasos y van en este orden. Los dos primeros los haces tú; los dos
últimos son un guión.

## 1. `verificar.sh`, si lo hay

```bash
./verificar.sh
```

Desde el worktree. Es formato, lint, tipos y unitarios, y tarda segundos. Si está
rojo, **arréglalo antes de revisar**: gastar la revisión en código que ni pasa el
lint es gastarla dos veces, porque cada commit nuevo la invalida.

Si el repositorio no tiene `verificar.sh`, sáltalo — y dilo al informar, porque
entonces el CI es la única red.

## 2. La revisión, y sus arreglos DENTRO de la PR

```
/code-review <rama> --fix
```

Sobre el diff de la rama entera contra `main`, no sobre lo último que tocaste.
`--fix` deja los arreglos en el árbol de trabajo: **léelos**, quédate con lo que
sea correcto, descarta lo que no, y commitéalo todo con un mensaje que diga que
viene de la revisión.

En un proyecto montado con `new-project` hay además un subagente `code-reviewer`
con las reglas de ese repositorio: úsalo también, no en su lugar.

Que la PR nazca ya revisada es el punto. Una PR que crece a base de commits de
«arreglo lo revisado» obliga a leerla dos veces.

Cuando esté commiteado:

```bash
~/.claude/bin/marcar-revisado.sh <rama>
```

La marca es el SHA de HEAD y caduca sola: **si commiteas algo después, hay que
volver a revisar**. Eso no es un incordio, es lo único que hace que la marca
signifique algo.

## 3. y 4. Empujar, PR, CI y pila

```bash
~/.claude/bin/probar-rama.sh <rama>
```

**En el repositorio dotfiles, y solo ahí, `./claude/bin/probar-rama.sh <rama>`**:
`~/.claude/bin` es un enlace al checkout de `main`, así que la otra forma prueba
el guión de antes de tu cambio.

Vuelve a lanzar `verificar.sh`, comprueba la marca de la revisión, empuja, abre
la PR si falta, espera al CI y —solo en verde— levanta la pila de esa rama:
proyecto de Compose propio, puerto propio y **una copia** del volumen de datos
del usuario. Después avisa con una notificación del sistema.

El CI de welzy tarda unos 12 minutos: **lánzalo con `run_in_background`** y sigue
a lo tuyo. Cuando termine, dile al usuario la URL y que la PR está esperando.

## Cómo leer lo que diga

- **«Lista para probar: http://127.0.0.1:…»** → dale la URL al usuario y **para
  ahí**. No cierres, no fusiones, no despliegues: falta que lo mire.
- **«verificar.sh ha fallado»** → no ha empujado nada. Arréglalo en el worktree,
  commitea, **vuelve a revisar** (la marca ha caducado con ese commit) y
  relánzalo.
- **«Estos commits no han pasado por el revisor»** → te has saltado el paso 2, o
  has commiteado después de marcar. Haz la revisión y `marcar-revisado.sh`. Los
  `--sin-verificar` y `--sin-revisar` existen, pero son del usuario: si crees que
  hace falta uno, dilo y que decida él.
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
