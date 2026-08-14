---
name: probar
description: Deja una rama lista para que el usuario la pruebe con ~/.claude/bin/probar-rama.sh - empuja, abre la PR y espera al CI. La pila local NO se levanta sola: se pregunta antes. Usar al terminar de trabajar en una rama, y cuando el usuario diga "pruébalo", "levántalo", "déjamelo listo" o "/probar".
---

# Dejar una rama lista para probar

Es el primer tiempo del cierre. El segundo es la skill `cerrar`, y **solo lo
lanza el usuario**.

## 1. Lánzalo de fondo, y pregunta mientras corre

```bash
~/.claude/bin/probar-rama.sh <rama>
```

**Con `run_in_background`, y sin esperar a nada para lanzarlo.** El CI de welzy
tarda unos 12 minutos, y ese es el rato en el que hay que hacer la pregunta del
punto 2: preguntar primero y lanzar después regala esos minutos a la espera.

Así, sin banderas, empuja, abre la PR si falta, espera al CI y **no levanta
ninguna pila**. Eso es lo que se quiere por defecto: levantar una pila construye
imágenes, clona el volumen de datos y ocupa un puerto, y la mayoría de las ramas
se juzgan enteras mirando la PR.

## 2. Pregunta si quiere probarlo en local

Con `AskUserQuestion`, **nada más lanzar lo anterior** y sin esperar a que
termine. La pregunta es una sola: *¿levanto la pila local de esta rama?*, con el
sí y el no, y diciendo en el «no» que se puede levantar después.

**Sáltate la pregunta si el worktree no tiene `docker-compose.yml`** — en
dotfiles, por ejemplo, no hay pila que levantar y preguntarlo es ruido. Míralo
antes de preguntar, no después.

## 3. Cuando el CI termine, haz lo que dijera

- **Dijo que sí** → en cuanto el lanzamiento de fondo acabe en verde:

  ```bash
  ~/.claude/bin/probar-rama.sh <rama> --solo-pila
  ```

  Solo levanta la pila: no vuelve a empujar, ni a abrir PR, ni a esperar al CI,
  que ya pasó. Después dale la URL.

- **Dijo que no** → dale la URL de la PR y para. El guión ya le habrá dicho cómo
  levantarla si cambia de idea; no insistas.

**En el repositorio dotfiles, y solo ahí, `./claude/bin/probar-rama.sh <rama>`**:
`~/.claude/bin` es un enlace al checkout de `main`, así que la otra forma prueba
el guión de antes de tu cambio.

## Cómo leer lo que diga

- **«La PR está esperando: …»** → el camino normal. Dale esa URL y **para ahí**.
  No cierres, no fusiones, no despliegues: falta que lo mire.
- **«Lista para probar: http://127.0.0.1:…»** → la pila está arriba. Dale la URL
  y para igual.
- **«El CI no está verde»** → enseña los jobs con sus enlaces. Arregla en el
  worktree, commitea y vuelve a lanzarlo.
- **«no ha disparado ningún check»** → normalmente el `paths-ignore` de una PR de
  solo documentación. La PR queda esperando al usuario.
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
- `--con-pila` levanta la pila en la misma pasada, sin la segunda llamada. Sirve
  cuando el usuario ya ha dicho de antemano que quiere probarlo en local.
