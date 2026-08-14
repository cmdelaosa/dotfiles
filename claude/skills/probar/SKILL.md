---
name: probar
description: Cadena automática al acabar de programar - verificar.sh, code-review a max en el mejor Opus, sus arreglos commiteados, y push+PR+CI con ~/.claude/bin/probar-rama.sh. No fusiona nada. Con el CI ya corriendo (sin esperar a que acabe) pregunta si levantar la pila local. Arranca sola al terminar el código de una rama; también cuando el usuario diga "pruébalo", "levántalo", "déjamelo listo" o "/probar".
---

# Dejar una rama lista para probar

Es el primer tiempo del cierre. El segundo es la skill `cerrar`, y **solo lo
lanza el usuario**.

**Este primer tiempo arranca solo** *(14-08-2026)*: en cuanto el código de la
rama está terminado y commiteado, la cadena empieza sin esperar a que el usuario
diga nada. «Pruébalo», «levántalo» y «déjamelo listo» siguen valiendo — son la
forma de entrar a mitad o de repetir —, pero no son requisito. La única pregunta
de toda la cadena va al final, con el CI ya corriendo; hasta ahí no hay nada que
preguntar.

Cinco pasos, en este orden.

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
subagente `general-purpose` con `model: "opus"` cuyo encargo sea exactamente esa
skill con `--fix`; está autorizado de antemano en el CLAUDE.md global, no hay
que volver a pedirlo.

`--fix` deja los arreglos en el árbol de trabajo: **léelos**, quédate con lo que
sea correcto, descarta lo que no —**y nombra los descartes en el informe final,
con su porqué**: un revisor también se equivoca, pero en silencio no—, y
commitéalo todo con un mensaje que diga que viene de la revisión.

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

## 3. Empujar, PR y CI — sin pila

```bash
~/.claude/bin/probar-rama.sh <rama>
```

**En el repositorio dotfiles, y solo ahí, `./claude/bin/probar-rama.sh <rama>`**:
`~/.claude/bin` es un enlace al checkout de `main`, así que la otra forma prueba
el guión de antes de tu cambio.

**Lánzalo con `run_in_background`**: el CI de welzy tarda unos 12 minutos y no
hay nada que esperar mirando. Vuelve a lanzar `verificar.sh`, comprueba la marca
de la revisión, empuja, abre la PR si falta y espera al CI. Sin `--con-pila` no
levanta ninguna pila: levantar una construye imágenes, clona el volumen de datos
y ocupa un puerto, y la mayoría de las ramas se juzgan enteras mirando la PR.

**La excepción**: si el usuario ya dijo «levántalo» al encargar la tarea, esa es
la respuesta del paso 4 adelantada — añade `--con-pila` y sáltate la pregunta.

## 4. La pregunta de la pila — con el CI ya corriendo

Vigila la salida del guión en segundo plano. En cuanto diga **«espero al CI de
la PR #N»** —el push está hecho y el CI en marcha; **no esperes a que
termine**—, pregunta con `AskUserQuestion`: *¿levanto la pila local de esta
rama?* Con el sí y el no, diciendo en el «no» que se puede levantar después. Si
dice que sí:

```bash
~/.claude/bin/probar-rama.sh <rama> --solo-pila
```

Solo levanta: no comprueba, no revisa, no empuja y no espera al CI. Funciona con
el árbol sucio a propósito.

La pregunta va aquí y no en otro sitio por dos razones. No al principio, porque
la cadena arranca sin el usuario delante y una pregunta en el paso 0 la
bloqueaba antes de empezar. No al final, porque entonces el CI ya gastó sus doce
minutos y la respuesta se cobra aparte: aquí, mientras contesta, el CI sigue
quemando los mismos minutos.

**Sáltate la pregunta si el worktree no tiene `docker-compose.yml`** — en
dotfiles, por ejemplo, no hay pila que levantar y preguntarlo es ruido. Informa
directamente con la URL de la PR.

## 5. Si el CI sale rojo: arregla sin preguntar, con un freno

Arregla en el worktree, commitea, **vuelve a revisar** (la marca caducó con ese
commit, y es código que nadie ha leído) y relanza el guión. Sin pedir permiso:
para eso existe la cadena.

**El freno: si el mismo check sale rojo dos veces seguidas, para** y enseña los
jobs con sus enlaces. Un bucle contra un rojo persistente —un flaky, un secreto
que falta— quema rondas de CI y revisiones de Opus sin avanzar.

## Cómo leer lo que diga el guión

- **«espero al CI de la PR #N»** → la señal del paso 4: pregunta por la pila
  ahora, con el guión aún corriendo.
- **«No he levantado nada: la pila local se pide.»** → ha terminado en verde. Si
  la pregunta del paso 4 no llegó a hacerse (un CI rápido), hazla ahora — o, sin
  `docker-compose.yml`, da la URL de la PR. Y **para ahí**: no cierres, no
  fusiones, no despliegues; falta que lo mire el usuario.
- **«Lista para probar: http://127.0.0.1:…»** → la pila está arriba. Dale la URL
  y para igual.
- **«verificar.sh ha fallado»** → no ha empujado nada. Arréglalo en el worktree,
  commitea, **vuelve a revisar** (la marca ha caducado con ese commit) y
  relánzalo.
- **«Estos commits no han pasado por el revisor»** → te has saltado el paso 2, o
  has commiteado después de marcar. Haz la revisión y `marcar-revisado.sh`. Los
  `--sin-verificar` y `--sin-revisar` existen, pero son del usuario: si crees que
  hace falta uno, dilo y que decida él.
- **«El CI no está verde»** → el paso 5: arregla, re-revisa, relanza; al segundo
  rojo del mismo check, para y enseña los jobs.
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
