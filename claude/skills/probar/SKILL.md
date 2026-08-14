---
name: probar
description: Revisa el diff de la rama, aplica lo que salga y la deja lista para que el usuario la pruebe con ~/.claude/bin/probar-rama.sh - empuja, abre la PR y espera al CI. No fusiona nada. La pila local NO se levanta sola: se pregunta antes. Usar al terminar de trabajar en una rama, y cuando el usuario diga "pruébalo", "levántalo", "déjamelo listo" o "/probar".
---

# Dejar una rama lista para probar

Es el primer tiempo del cierre. El segundo es la skill `cerrar`, y **solo lo
lanza el usuario**.

Son cinco pasos y van en este orden. El primero es una pregunta, los dos
siguientes los haces tú, y los dos últimos son un guión.

## 0. Pregunta primero: ¿quiere probarlo en local?

Con `AskUserQuestion`, **antes de nada**. Una sola pregunta —*¿levanto la pila
local de esta rama?*— con el sí y el no, diciendo en el «no» que se puede
levantar después.

Va la primera porque es la única forma de que no cueste tiempo: mientras el
usuario contesta, `verificar.sh`, la revisión y el CI ya están corriendo.
Preguntarlo al final, cuando el CI acaba de gastar doce minutos, es cobrarle la
espera dos veces.

**Sáltate la pregunta si el worktree no tiene `docker-compose.yml`** — en
dotfiles, por ejemplo, no hay pila que levantar y preguntarlo es ruido.

Guarda la respuesta: decide la bandera del paso 3.

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
con las reglas de ese repositorio: úsalo también, no en su lugar. Lanzarlo está
autorizado de antemano en el CLAUDE.md global; no hace falta volver a pedirlo.

Que la PR nazca ya revisada es el punto. Una PR que crece a base de commits de
«arreglo lo revisado» obliga a leerla dos veces.

Cuando esté commiteado:

```bash
~/.claude/bin/marcar-revisado.sh <rama>
```

La marca es el SHA de HEAD y caduca sola: **si commiteas algo después, hay que
volver a revisar**. Eso no es un incordio, es lo único que hace que la marca
signifique algo.

## 3. Empujar, PR y CI — con la respuesta del paso 0 ya puesta

```bash
~/.claude/bin/probar-rama.sh <rama>              # dijo que no
~/.claude/bin/probar-rama.sh <rama> --con-pila   # dijo que sí
```

**En el repositorio dotfiles, y solo ahí, `./claude/bin/probar-rama.sh <rama>`**:
`~/.claude/bin` es un enlace al checkout de `main`, así que la otra forma prueba
el guión de antes de tu cambio.

**Lánzalo con `run_in_background`**: el CI de welzy tarda unos 12 minutos y no
hay nada que esperar mirando. Vuelve a lanzar `verificar.sh`, comprueba la marca
de la revisión, empuja, abre la PR si falta y espera al CI. Sin `--con-pila` no
levanta ninguna pila, que es lo que se quiere por defecto: levantar una construye
imágenes, clona el volumen de datos y ocupa un puerto, y la mayoría de las ramas
se juzgan enteras mirando la PR.

## 4. Y si cambia de idea después

```bash
~/.claude/bin/probar-rama.sh <rama> --solo-pila
```

Solo levanta la pila: no comprueba, no revisa, no empuja y no espera al CI, que
ya pasó. Funciona con el árbol sucio a propósito —para entonces el revisor suele
haber dejado sus arreglos ahí— y es lo que el propio guión ofrece al terminar.

## Cómo leer lo que diga

- **«No he levantado nada: la pila local se pide.»** → el camino normal. Dale la
  URL de la PR y **para ahí**. No cierres, no fusiones, no despliegues: falta que
  lo mire.
- **«Lista para probar: http://127.0.0.1:…»** → la pila está arriba. Dale la URL
  y para igual.
- **«verificar.sh ha fallado»** → no ha empujado nada. Arréglalo en el worktree,
  commitea, **vuelve a revisar** (la marca ha caducado con ese commit) y
  relánzalo.
- **«Estos commits no han pasado por el revisor»** → te has saltado el paso 2, o
  has commiteado después de marcar. Haz la revisión y `marcar-revisado.sh`. Los
  `--sin-verificar` y `--sin-revisar` existen, pero son del usuario: si crees que
  hace falta uno, dilo y que decida él.
- **«El CI no está verde»** → enseña los jobs con sus enlaces. Arregla en el
  worktree, commitea y vuelve a lanzarlo.
- **«no ha disparado ningún check»** → normalmente el `paths-ignore` de una PR de
  solo documentación. La PR queda esperando al usuario.
- **«La pila no responde»** → pásale al usuario la salida de
  `docker compose -p <proyecto> logs`.

Todas esas salidas avisan además por el sistema, así que el usuario se entera sin
que nadie tenga que estar mirando el terminal.

## Lo que hay que tener claro

- **Los datos son una copia.** La pila de siempre del usuario no se toca, y una
  migración de Flyway de la rama se aplica sobre la copia. Se puede decir con
  esas palabras: da tranquilidad y es verdad.
- Si hay que cambiar algo después de probar, se cambia **en la rama** y se
  relanza esto. Ese es justo el motivo de que exista: que main reciba una fusión
  limpia en vez de tres commits arreglando lo que se vio al probar.
- Dos ramas pueden estar levantadas a la vez, cada una en su puerto.
- Si el usuario ha dicho «levántalo» al invocar la skill, eso **ya es** la
  respuesta del paso 0: no se la vuelvas a preguntar, ve directo a `--con-pila`.
