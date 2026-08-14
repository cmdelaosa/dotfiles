---
name: probar
description: Cadena automática al acabar de programar - verificar.sh, code-review a max en el mejor Opus, sus arreglos commiteados, y push+PR+CI con ~/.claude/bin/probar-rama.sh. No fusiona nada. Con el CI ya corriendo (sin esperar a que acabe) pregunta si levantar la pila local. Usar SIEMPRE al terminar de programar una rama, sin que el usuario lo pida, y también cuando diga "pruébalo", "levántalo", "déjamelo listo" o "/probar".
---

# Dejar una rama lista para probar

Es el primer tiempo del cierre. El segundo es la skill `cerrar`, y **solo lo
lanza el usuario**.

**Este primer tiempo arranca solo** *(14-08-2026)*: en cuanto el código de la
rama está terminado y commiteado, la cadena empieza sin esperar a que el usuario
diga nada. «Pruébalo», «levántalo» y «déjamelo listo» siguen valiendo — son la
forma de entrar a mitad o de repetir —, pero no son requisito.

**Lo que arranca la cadena es la tarea acabada, no un commit cualquiera.** Si lo
que pidió el usuario tiene partes y solo va una, sigue programando: una PR por
trozo es exactamente la historia de «arreglo lo revisado» que el paso 2 existe
para no tener.

Cinco pasos. Los tres primeros van en orden; el 4 corre **mientras** el 3 sigue
vivo, y el 5 depende de cómo acabe el 3. Al usuario solo se le pregunta una vez
en toda la cadena, y es la del paso 4.

## 1. `verificar.sh`, si lo hay

```bash
./verificar.sh
```

Desde el worktree. Es formato, lint, tipos y unitarios, y tarda segundos. Si está
rojo, **arréglalo antes de revisar**: gastar la revisión en código que ni pasa el
lint es gastarla dos veces, porque cada commit nuevo la invalida.

Si el repositorio no tiene `verificar.sh`, sáltalo — y dilo al informar, porque
entonces el CI es la única red.

## 2. La revisión: a `max`, en el mejor Opus que haya

```
/code-review <rama> max --fix
```

Sobre el diff de la rama entera contra `main`, no sobre lo último que tocaste, y
a nivel `max`: es la única lectura completa antes de que el usuario mire la PR.

**La revisión la hace el mejor Opus disponible** (el alias `opus`; hoy,
`claude-opus-5`). Si la sesión corre en otro modelo, lanza la revisión en un
subagente `general-purpose` con `model: "opus"` cuyo encargo sea exactamente
`/code-review <rama> max --fix`; está autorizado de antemano en el CLAUDE.md
global, no hay que volver a pedirlo.

`--fix` deja los arreglos en el árbol de trabajo: **léelos**, quédate con lo que
sea correcto, descarta lo que no —**y nombra los descartes en el informe final,
con su porqué**: un revisor también se equivoca, pero en silencio no—, y
commitéalo todo con un mensaje que diga que viene de la revisión. **Lo que
descartes, reviértelo**; si se queda suelto en el árbol, el paso 3 se para en
seco con «El worktree tiene cambios sin guardar».

En un proyecto montado con `new-project` hay además un subagente `code-reviewer`
con las reglas de ese repositorio: úsalo también, no en su lugar. Lanzarlo
también está autorizado de antemano en el CLAUDE.md global; no hace falta volver
a pedirlo.

Que la PR nazca ya revisada es el punto. Una PR que crece a base de commits de
«arreglo lo revisado» obliga a leerla dos veces.

Cuando esté commiteado:

```bash
~/.claude/bin/marcar-revisado.sh <rama>
```

La marca es el SHA de HEAD y caduca sola: **si commiteas algo después, hay que
volver a revisar y volver a marcar**. Eso no es un incordio, es lo único que
hace que la marca signifique algo.

## 3. Empujar, PR y CI

```bash
~/.claude/bin/probar-rama.sh <rama>              # el caso normal
~/.claude/bin/probar-rama.sh <rama> --con-pila   # si ya dijo «levántalo»
```

**En el repositorio dotfiles, y solo ahí, `./claude/bin/probar-rama.sh <rama>`**:
`~/.claude/bin` es un enlace al checkout de `main`, así que la otra forma prueba
el guión de antes de tu cambio.

**Lánzalo con `run_in_background`**: el CI de welzy tarda unos 12 minutos. Vuelve
a lanzar `verificar.sh`, comprueba la marca de la revisión, empuja, abre la PR si
falta y espera al CI. Sin `--con-pila` no levanta ninguna pila: levantar una
construye imágenes, clona el volumen de datos y ocupa un puerto, y la mayoría de
las ramas se juzgan enteras mirando la PR.

**La excepción**: si el usuario ha dicho «levántalo» **en cualquier momento**
—al encargar la tarea, al invocar la skill o a mitad—, eso ya es la respuesta del
paso 4: `--con-pila` y sáltate la pregunta. Con una advertencia que hay que
decirle: `--con-pila` levanta la pila **solo si el CI acaba en verde**; con rojo
sale con error sin levantar nada. Si la quiere ver pase lo que pase, es
`--solo-pila` cuando el CI ya haya contestado.

## 4. La pregunta de la pila — con el CI ya corriendo

**Sáltate el paso entero si el worktree no tiene `docker-compose.yml`** — en
dotfiles, por ejemplo, no hay pila que levantar y preguntarlo es ruido. Pero no
informes aún: sigue vigilando el guión hasta que termine, y da la URL de la PR
**con el veredicto del CI**, que es lo único que el usuario no puede ver de un
vistazo.

Con pila, hay que leer la salida **mientras el guión corre**, y eso no ocurre
solo: `run_in_background` devuelve el control enseguida y solo te despierta **al
terminar el proceso**, que es doce minutos tarde. Así que **no cierres el turno
aquí**: sondea la salida (`BashOutput`, o `Monitor` con un bucle `until`) cada
pocos segundos hasta ver la línea. Sale por **stderr** y con dos espacios
delante:

```
  espero al CI de la PR #12
```

Ahí el push está hecho y el CI en marcha. **No esperes a que termine**: pregunta
con `AskUserQuestion` —*¿levanto la pila local de esta rama?*— con el sí y el no,
diciendo en el «no» que se puede levantar después.

**Esa pregunta para el turno hasta que conteste**, así que al volver mira primero
cómo acabó el guión y solo después la respuesta:

- **Si el CI salió rojo mientras esperabas**, manda el paso 5: no levantes nada
  —sería una pila de un commit que el CI ya ha rechazado—, dilo al contestar y
  vuelve a ofrecerlo cuando haya verde.
- **Si acabó en verde y dijo que sí**:

```bash
~/.claude/bin/probar-rama.sh <rama> --solo-pila
```

Solo levanta: no comprueba, no revisa, no empuja y no mira el CI —por eso el
orden de arriba importa, porque no hay nada que le impida levantar una rama en
rojo—. Funciona con el árbol sucio a propósito.

La pregunta va aquí y no en otro sitio por dos razones. No al principio, porque
la cadena arranca sin el usuario delante y una pregunta ahí la bloqueaba antes de
empezar. No después del verde, porque entonces el CI ya gastó sus doce minutos y
la respuesta se cobra aparte: aquí, mientras contesta, el CI sigue quemando los
mismos minutos.

## 5. Si el CI sale rojo: arregla sin preguntar, con un freno

**Antes de dar nada por rojo, lee las líneas de encima.** El guión despide con
«El CI no está verde» en dos casos distintos: cuando hay jobs en rojo —debajo
salen sus nombres y sus enlaces— y cuando **solo siguen corriendo** («El CI
todavía está corriendo»), que es lo que pasa si el `--watch` se cae a mitad. Si
no ha fallado nada, no hay nada que arreglar: relanza y vuelve a esperar.

Con rojo de verdad: arregla en el worktree, commitea, **vuelve a revisar** (la
marca caducó con ese commit, y es código que nadie ha leído), **vuelve a marcar**
y relanza. Sin pedir permiso: para eso existe la cadena.

```bash
~/.claude/bin/marcar-revisado.sh <rama>
~/.claude/bin/probar-rama.sh <rama>
```

En dotfiles, `./claude/bin/…` las dos, por lo mismo que en el paso 3. Y **no
vuelvas a preguntar por la pila**: el guión reimprime «espero al CI de la PR #N»
en cada pasada, pero la pregunta del paso 4 es una por cadena.

**El freno son dos piezas, porque con una sola no frena:**

- **Como mucho dos rondas de arreglo automático.** A la tercera, para pase lo que
  pase — el tiempo y el dinero son de él.
- **Y para antes si un check ya salió rojo en alguna ronda anterior**, aunque
  entre medias fallara otro distinto: con `--fail-fast` los hermanos salen como
  `cancel`, que también cuenta como rojo, así que el nombre rota solo y «dos
  veces seguidas» no distinguiría nada. Apunta los nombres de cada ronda y
  compáralos contra **todas** las anteriores, no contra la última.

Al parar, enseña los jobs con sus enlaces. Un bucle contra un rojo persistente
—un flaky, un secreto que falta— quema rondas de CI y revisiones de Opus sin
avanzar.

## Cómo leer lo que diga el guión

- **«espero al CI de la PR #N»** → la señal del paso 4: pregunta por la pila
  ahora, con el guión aún corriendo. Salvo que ya lleve `--con-pila`, que no haya
  `docker-compose.yml`, o que sea un relanzamiento del paso 5: la pregunta es una
  por cadena.
- **«No he levantado nada: la pila local se pide.»** → ha terminado sin levantar
  nada. **El verde no lo dice esta línea, lo dice el «Su CI está verde.» de
  debajo**; con `--sin-ci` pone «Su CI está sin mirar», y eso no es un verde. Si
  la pregunta del paso 4 no llegó a hacerse, hazla ahora — o, sin
  `docker-compose.yml`, da la URL de la PR. Y **para ahí**: no cierres, no
  fusiones, no despliegues; falta que lo mire el usuario.
- **«Lista para probar: http://127.0.0.1:…»** → la pila está arriba. Dale la URL
  y para igual. Si venía del paso 4, di también cómo acabó el CI.
- **«El worktree tiene cambios sin guardar»** → no ha empujado nada. Suele ser lo
  que descartaste de la revisión y se quedó suelto: revíértelo o commitéalo. El
  `--forzar` que ofrece tira esos cambios, y es del usuario.
- **«verificar.sh ha fallado»** → no ha empujado nada. Arréglalo en el worktree,
  commitea, **vuelve a revisar y a marcar** (la marca ha caducado con ese commit)
  y relánzalo.
- **«Estos commits no han pasado por el revisor»** → te has saltado el paso 2, o
  has commiteado después de marcar. Haz la revisión y `marcar-revisado.sh`. Los
  `--sin-verificar` y `--sin-revisar` existen, pero son del usuario: si crees que
  hace falta uno, dilo y que decida él.
- **«El CI no está verde»** → el paso 5, pero mira antes si lo que hay debajo son
  jobs en rojo o un «El CI todavía está corriendo»: eso último no se arregla, se
  espera. Con rojo: arregla, re-revisa, re-marca, relanza; a la tercera ronda, o
  al segundo rojo de un check que ya falló antes, para y enseña los jobs.
- **«no ha disparado ningún check»** → normalmente el `paths-ignore` de una PR de
  solo documentación. La PR queda esperando al usuario. Si en cambio dice «este
  repositorio no tiene CI», dilo con esas palabras: no es lo mismo y no hay red.
- **«La pila no responde»** → pásale al usuario la salida de
  `docker compose -p <proyecto> logs`.

**Casi todas avisan por el sistema**, así que el usuario se entera sin estar
mirando el terminal. Las que **no**: la señal del paso 4 y los tres frenos de
antes del push —árbol sucio, `verificar.sh` rojo y diff sin revisar—, que salen
por `morir` y no suenan. Justo los casos en que la cadena se para sin haber
empujado nada, así que **esos hay que contarlos tú**, y no darlos por avisados.

## Lo que hay que tener claro

- **Los datos son una copia.** La pila de siempre del usuario no se toca, y una
  migración de Flyway de la rama se aplica sobre la copia. Se puede decir con
  esas palabras: da tranquilidad y es verdad.
- Si hay que cambiar algo después de probar, se cambia **en la rama** y se
  relanza esto. Ese es justo el motivo de que exista: que main reciba una fusión
  limpia en vez de tres commits arreglando lo que se vio al probar.
- Dos ramas pueden estar levantadas a la vez, cada una en su puerto. La misma
  rama, no: un `--solo-pila` de más recrea el proyecto en otro puerto y mata la
  URL que ya diste.
