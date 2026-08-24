---
name: probar
description: Cadena automática al acabar de programar - clasificar el diff, una sola revisión al nivel que pida, verificar, y push+PR con probar-rama.sh, que deja el CI esperando de fondo. No fusiona nada. Con la PR recién abierta pregunta si levantar la pila local. Si la rama solo toca ficheros .md, va por el atajo --solo-md y lo que pregunta es si fusionar. Usar SIEMPRE al terminar de programar una rama, sin que el usuario lo pida, y también cuando diga "pruébalo", "levántalo", "déjamelo listo" o "/probar".
---

# Dejar una rama lista para probar

Es el primer tiempo del cierre. El segundo es la skill `cerrar`, y **solo lo
lanza el usuario**.

**Arranca solo**: en cuanto el código de la rama está terminado y commiteado, sin
esperar a que el usuario diga nada. «Pruébalo», «levántalo» y «déjamelo listo»
siguen valiendo — son la forma de entrar a mitad o de repetir.

**Lo que arranca la cadena es la tarea acabada, no un commit cualquiera.** Si lo
que pidió el usuario tiene partes y solo va una, sigue programando: una PR por
trozo es exactamente la historia de «arreglo lo revisado» que el paso 2 existe
para no tener.

Al usuario se le pregunta **una sola vez** en toda la cadena, y es en el paso 4.

## 1. ¿De qué tramo es esto?

```bash
~/.claude/bin/clasificar-diff.sh <rama>
```

**En el repositorio dotfiles, `./claude/bin/clasificar-diff.sh`** — igual que en
el paso 3, y por lo mismo: `~/.claude/bin` es un enlace al checkout de `main`.

Imprime el tramo y el nivel de revisión que pide, mirando el diff entero contra
`main`:

| tramo | qué es | revisión |
|---|---|---|
| `solo-md` | ni un fichero fuera de `.md` | ninguna → [atajo](#el-atajo-de-solo-markdown) |
| `trivial` | ≤30 líneas, sin ficheros nuevos, nada delicado | `low` |
| `normal` | lo demás | `high` |
| `sensible` | ruta delicada (hooks, migraciones, auth, CI, settings) o >600 líneas | `max` |

**No lo decidas tú.** Lo decide el guión leyendo el diff, y `probar-rama.sh` se
niega a empujar si la marca de revisión dice un nivel más bajo del que pide el
tramo. Quien pide el atajo es siempre quien acaba de decidir, él solo, que lo
suyo es sencillo.

## 2. La revisión: una, al nivel que salga, y solo sobre lo que nadie ha leído

```bash
~/.claude/bin/revision-pendiente.sh <rama>
```

**En dotfiles, `./claude/bin/…`**, por lo mismo que el resto. Imprime **qué hay
que leer**, que no siempre es la rama entera:

| lo que imprime | qué significa | qué lanzas |
|---|---|---|
| `nada <nivel>` | la marca es de este HEAD | nada: al paso 3 |
| `todo <nivel>` | no hay marca que heredar | `/code-review <rama> <nivel> --fix` |
| `<sha> <nivel>` | falta lo de después de ahí | `/code-review <sha>..HEAD <nivel> --fix` |

**Y una sola**: nada de pasar además el diff por el subagente `code-reviewer`
—dos lecturas completas del mismo diff, las dos a esfuerzo máximo, era la mitad
del coste de cada PR—. El subagente sigue estando para cuando el usuario lo pida.

El tercer caso entra cuando **sigues trabajando en una rama ya revisada**. **El
nivel no baja por ser un trozo** —lo pide el diff completo—, y el guión cae a
`todo` con cualquier duda. Lo medido, en `docs/porques.md`.

**Lo que esto NO ve**, y lo miras tú: si el commit nuevo cambia el contrato de
algo ya aprobado —una firma, lo que devuelve, un invariante—, nadie vuelve a
mirar las llamadas que se dieron por buenas. Ahí pide `todo` a mano.

**Escribe el nivel siempre**: sin nivel, la skill reutiliza el último que se
tecleó, que puede venir de cualquier otra cosa.

`--fix` deja los arreglos en el árbol de trabajo: **léelos**, quédate con lo que
sea correcto, descarta lo que no —**y nombra los descartes en el informe final,
con su porqué**: un revisor también se equivoca, pero en silencio no—, y
commitéalo todo con un mensaje que diga que viene de la revisión. **Lo que
descartes, reviértelo**; si se queda suelto en el árbol, el paso 3 se para en
seco con «El worktree tiene cambios sin guardar».

Cuando esté commiteado:

```bash
~/.claude/bin/marcar-revisado.sh <rama> --nivel <el-nivel-que-has-usado>
```

La marca es el SHA de HEAD y caduca sola: **si commiteas algo después, hay que
volver a revisar y volver a marcar**. Eso no es un incordio, es lo único que
hace que la marca signifique algo.

## 3. Empujar y abrir la PR — sin esperar al CI

```bash
~/.claude/bin/probar-rama.sh <rama> --sin-ci
```

**En el repositorio dotfiles, y solo ahí, `./claude/bin/probar-rama.sh`**:
`~/.claude/bin` es un enlace al checkout de `main`, así que la otra forma prueba
el guión de antes de tu cambio.

Esto lanza `verificar.sh`, comprueba la marca de la revisión, empuja y abre la PR
si falta. **Tarda segundos, así que va en primer plano.** No espera al CI: eso es
el paso 5, y el motivo de partirlo en dos es que la pregunta del paso 4 se pueda
hacer ya, en vez de sondear doce minutos la salida de un guión.

## 4. La pregunta de la pila

**Sáltate el paso entero si el worktree no tiene `docker-compose.yml`** — en
dotfiles, por ejemplo, no hay pila que levantar y preguntarlo es ruido.

Si la hay, `AskUserQuestion` —*¿levanto la pila local de esta rama?*— con la URL
de la PR delante, diciendo en el «no» que se puede levantar después. Levantar una
construye imágenes, clona el volumen de datos y ocupa un puerto, y la mayoría de
las ramas se juzgan enteras mirando la PR.

**Si el usuario ya dijo «levántalo» en cualquier momento**, eso es la respuesta:
no preguntes. Con el sí, y **solo cuando el CI del paso 5 esté verde**:

```bash
~/.claude/bin/probar-rama.sh <rama> --solo-pila
```

Solo levanta: no comprueba, no revisa, no empuja y no mira el CI. Un sí levantado
sobre un rojo es una pila de un commit que el CI ya ha rechazado; dilo y ofrécelo
otra vez cuando haya verde.

## 5. El CI, de fondo

```bash
~/.claude/bin/probar-rama.sh <rama> --esperar-ci
```

**Con `run_in_background`, y no lo sondees**: el harness te despierta cuando el
proceso termine. Sondearla cada pocos segundos gasta un turno entero por sondeo.

Cómo acaba:

- **Verde** → informa con la URL de la PR. Y **para ahí**: no cierres, no
  fusiones, no despliegues; falta que lo mire el usuario.
- **Rojo (sale con 1)** → arréglalo sin preguntar: parche en el worktree,
  commit, **vuelve a clasificar, revisar y marcar** —la marca caducó con ese
  commit— y relanza desde el paso 3. Para eso existe la cadena.
- **Faltan checks (sale con 1)** → no es rojo: el CI no ha corrido entero, casi
  siempre porque choca con `main`. Rebasa y relanza desde el paso 3.
- **Rojo con `PARO:` (sale con 3)** → el guión ha echado el freno: van tres
  rondas, o un check que ya falló ha vuelto a fallar. **No relances.** Enseña los
  jobs con sus enlaces y para: un bucle contra un flaky quema rondas de CI y
  revisiones sin mover nada.

El freno lo lleva el guión en un fichero, no tú.

## El atajo de solo markdown

Si el paso 1 dice `solo-md`, la cadena de arriba no se ejecuta: un cambio de
prosa no tiene lint que romper, ni tipos, ni pruebas que pasen de verdes a rojas,
y una revisión sobre él se gasta leyendo texto. Tampoco se despliega.

Tres tiempos, y solo el segundo espera al usuario:

**1.** `~/.claude/bin/probar-rama.sh <rama> --solo-md` (de fondo; en dotfiles,
`./claude/bin/…`). No hay que escribir `--sin-verificar` ni `--sin-revisar`: el
guión los rechaza al lado de `--solo-md`: esta bandera **comprueba el diff antes
de perdonar nada**.

**2.** Cuando termine, `AskUserQuestion` —*¿la fusiono?*— con la URL delante. Es
la única pregunta del atajo. Con el CI en rojo no se pregunta: se arregla. «Sin
checks» no es rojo —es el `paths-ignore` de welzy— y ahí se pregunta igual.

**3.** Con su sí: `ExitWorktree` con `action: "keep"` y, desde la raíz,
`~/.claude/bin/cerrar-rama.sh <rama> --solo-md`, que fusiona sin checks, **no
despliega** y limpia worktree y ramas. Vuelve a comprobar el diff por su cuenta.

## Lo que hay que tener claro

- **Los datos son una copia.** La pila de siempre del usuario no se toca, y una
  migración de la rama se aplica sobre la copia. Se puede decir con esas
  palabras: da tranquilidad y es verdad.
- Si hay que cambiar algo después de probar, se cambia **en la rama** y se
  relanza esto. Ese es justo el motivo de que exista: que main reciba una fusión
  limpia en vez de tres commits arreglando lo que se vio al probar.
- Dos ramas pueden estar levantadas a la vez, cada una en su puerto. La misma
  rama, no: un `--solo-pila` de más recrea el proyecto en otro puerto y mata la
  URL que ya diste.
- **Las despedidas avisan por el sistema**, pero lo que sale por `morir` no suena:
  los frenos de antes del push y dos abortos de después. Esos hay que contarlos
  tú, y no darlos por avisados.

Cuando el guión diga algo que no entiendas, está en
[referencia.md](referencia.md) — no hace falta leerlo antes.
