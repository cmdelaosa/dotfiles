# Los porqués

Esto no lo carga nadie. Ni Claude Code al arrancar una sesión, ni ninguna skill:
es un fichero para leer cuando una regla del `CLAUDE.md` parezca arbitraria y
haya que decidir si sigue teniendo sentido.

Está aquí porque el `CLAUDE.md` global se carga entero en **cada sesión de cada
proyecto**, así que cada línea suya se paga siempre. El 17-08-2026 había llegado
a 19,5 KB —unos 5.000 tokens por sesión— casi todo porqués: cada lección nueva se
escribía allí con su historia entera. Y el porqué es justo lo que **no** hace
falta tener delante para cumplir la regla; hace falta el día que alguien quiere
cambiarla. Ese día se lee esto.

El presupuesto del `CLAUDE.md` —6.000 bytes y 80 líneas— lo comprueba
`verificar.sh`, y el CI lo ejecuta en cada PR. **Ya se había recortado antes y
volvió a estallar solo**, así que el límite no es un propósito: es un freno.
Subirlo es una decisión deliberada, y se ve en el diff.

## Nunca se trabaja en main

**Tres sesiones en el mismo checkout se destrozan entre ellas** *(13-08-2026)*.
Aterrizaron a la vez en la raíz de welzy: una movió HEAD por debajo de otra, un
WIP acabó dentro de la PR de un tercero (`5b727d2`, hoy en la historia de main) y
un `commit` fue directo a `main`. Nadie decidió saltarse el worktree — abrir uno
era un paso manual, y los pasos manuales se saltan. De ahí que la regla sea
«antes de tocar el primer fichero», y no «cuando veas que hace falta».

**Las sesiones nacen a veces dentro de un worktree con nombre inventado**
(`focused-pascal-b3d58d`): el mismo directorio que usa `abrir-rama.sh`, con el
único nombre que rechaza, salvo que nunca se le pregunta porque la rama y el
directorio ya existen. Renombrar no sirve: deja el directorio con el nombre
viejo, y el directorio no se puede mover desde dentro de la sesión que vive en
él. Por eso la receta es salir, no arreglar.

**El prefijo `wt`** existe porque con cuatro worktrees abiertos con nombres
Docker no hay forma de saber cuál tiene qué sin entrar en todos.

**`main` vive en la raíz.** Si está sacado en otro sitio, `gh pr merge` y
`git checkout main` fallan en la raíz con `'main' is already used by worktree`.

**Los hooks no ven dentro de los guiones.** Un `PreToolUse` solo lee la línea de
Bash, así que el `git push origin --delete` y el `git branch -D` que
`cerrar-rama.sh` ejecuta por dentro nunca le llegan. Los hooks protegen lo que se
teclea a mano; los guiones se fían de su matriz de pruebas.

**La limpieza no es «tocar main»** *(13-08-2026)*. Pedir el `CLAUDE_ALLOW_MAIN=1`
para borrar una rama ya fusionada era gastar la escotilla en lo único que no
importa, y una escotilla que se pide a diario deja de leerse. La excepción exige
cada comando por separado porque el hook mira la línea entera: encadenar con
`&&`, `;` o `||` la tira. Un `cd <ruta> &&` delante sí vale —no cambia lo que
hace git— y además decide qué repositorio juzga el hook, igual que `git -C`.

**`dotfiles` tiene protección de servidor desde el 14-08-2026**: es público, así
que `main` exige PR, exige el verde de `verificar.sh`, rechaza force-push y
borrado, e **incluye a los administradores**. Ahí la escotilla ya no compra un
push directo. En los repositorios privados el hook sigue siendo la única barrera,
porque la protección de rama de GitHub pide Pro o repositorio público.

## La cadena de después de programar

**Se cierra en dos tiempos, y solo el segundo me espera** *(14-08-2026)*. El
primero arranca solo en cuanto la tarea está terminada, porque esperar a un
«pruébalo» convertía cada trozo en su propia PR, y una PR por trozo es
exactamente la historia de «arreglo lo revisado» que todo esto existe para no
tener.

**Los dos frenos van antes del push** a propósito. Una PR que nace con los
arreglos del revisor dentro se lee una vez; una que crece a base de commits de
«arreglo lo revisado» se lee tres.

**La marca de revisión caduca sola** porque es el SHA de HEAD: cualquier commit
posterior es código que no ha leído nadie. Eso no es un incordio, es lo único
que hace que la marca signifique algo.

**El nivel se escribe a mano en la marca** *(17-08-2026)*. Podría ponerlo el
propio guión preguntándole al clasificador, y entonces la marca se estaría
escribiendo a sí misma: diría siempre que sí. Que haya que teclearlo es lo que
la convierte en la afirmación de alguien.

**La escalera de tramos generaliza `--solo-md`** *(17-08-2026)*. Aquel atajo
descubrió lo que valía —el freno lo elige un guión leyendo el diff, no el agente
que acaba de decidir que lo suyo es sencillo— y lo que faltaba era el resto de la
escalera: revisar a `max` veinte líneas cuesta lo mismo que revisar a `max` dos
mil, y ese coste se pagaba en cada rama. La lista de rutas delicadas se lee de la
RAÍZ, o sea de `main`, porque leerla de la rama dejaría que una rama se rebajara
el listón borrando de la lista justo lo que va a tocar.

**Una sola revisión, no dos** *(17-08-2026)*. La skill mandaba pasar el diff por
`/code-review` **y además** por el subagente `code-reviewer`: dos lecturas
completas del mismo diff, las dos a esfuerzo máximo, en cada PR.

**La cadena va partida en dos desde el 17-08-2026.** Antes se lanzaba entera de
fondo y la skill sondeaba su salida «cada pocos segundos» hasta ver la línea del
CI. Cada sondeo es un turno que reenvía el contexto entero, así que doce minutos
de CI salían por decenas de turnos completos para leer una línea de texto. Con
`--sin-ci` primero y `--esperar-ci` después, la pregunta de la pila se hace con
el push recién hecho y nadie sondea nada.

**La pila local no se levanta sola** *(14-08-2026)*: construye imágenes, clona el
volumen de datos y ocupa un puerto, y la mayoría de las ramas se juzgan enteras
mirando la PR. Se pregunta con el CI ya corriendo, no después: así la respuesta
no cuesta doce minutos aparte, se paga con los que el CI está quemando igual.

**El freno de las rondas se mudó al guión** *(17-08-2026)*. La regla —«dos rondas
de arreglo automático, y para antes si un check que ya falló vuelve a fallar»—
vivía en la cabeza del modelo, que tenía que apuntar los nombres de cada ronda y
compararlos contra todas las anteriores. Eso es lo que un modelo hace mal y un
fichero hace bien. Y hacen falta las dos condiciones porque con `--fail-fast` los
hermanos salen como `cancel`, que cuenta como rojo, así que el nombre del que
falla rota solo y «dos veces seguidas» no distinguiría nada.

**Un verde anterior al main de ahora no es un verde.** El CI prueba el resultado
de FUSIONAR la rama con main en ese momento; si main se mueve después, GitHub
sigue enseñando verde para una fusión que nadie ha probado. Medido el 13-08-2026:
fusionada la PR #8, la #9 seguía diciendo `CLEAN`. Solo muerde con varias ramas
en vuelo, que es justo lo que el flujo de worktrees hace fácil.

**«Sin checks» tiene dos causas distintas** y hasta el 13-08-2026 daban el mismo
mensaje: que el repositorio no tenga CI, o que lo tenga y esta PR no lo dispare
—el `paths-ignore` de welzy hace eso con las PRs de documentación—. Decir «este
repositorio no tiene CI» de welzy es falso, y convierte un repositorio con
pruebas en uno que se fusiona a ojo.

**El despliegue es condicional**: `cerrar-rama.sh` solo llama a
`cmdlo-infra/desplegar.sh` cuando el repositorio lleva el contrato de cmdlo
—`ops/deploy/deploy.sh` **y** `.github/workflows/release.yml`—. Hoy eso es welzy
y nada más, así que no anuncies un despliegue que no va a ocurrir.

## `verificar.sh`

**Su sitio es lo que cuesta segundos.** El de welzy tarda 4 s (Compose, los dos
overlays, el parseo de los env-file, la regla de systemd y la compatibilidad de
`/api/v1`, que ningún `make` miraba), mientras `make test` tarda 4m37s y se queda
fuera. Un freno que cuesta cinco minutos acaba con un `--sin-verificar` en cada
llamada, y entonces no frena nada.

**El de este repositorio se le fue de las manos** *(17-08-2026)*: 58 s medidos,
con `user 22s` y `sys 26s` —casi todo arrancando procesos—, y se ejecuta dos
veces por cadena, contra los **32 s que tarda el CI entero**. Las tres matrices
pasaron a correr en paralelo y el propio guión avisa si vuelve a pasar de 15 s.
Avisa y no suspende: un chequeo que se pone rojo por lento se apaga a la semana.

**El `/bin/bash` que importa es el 3.2 de Apple**, que es quien ejecuta los
hooks y acepta menos cosas: un `case` dentro de `$( )` sin paréntesis de apertura
en el patrón se lo traga el 5.x de Homebrew y lo rechaza el 3.2. Y un hook
`PreToolUse` con un error de sintaxis sale con 2, que significa «bloqueado»: una
errata ahí bloquea todo git en todas las sesiones.

**Una lista vacía no es un aprobado.** Cuando el filtro del `find` se excluía a
sí mismo, cero ficheros comprobados salían idénticos a un TODO BIEN de verdad.
Por eso el cero cuenta como fallo.

## Las matrices de pruebas

**Se lanza la que está al lado del fichero que has tocado.** `~/.claude/hooks` y
`~/.claude/bin` son enlaces a la RAÍZ, o sea a `main`: hasta el 13-08-2026 la
matriz de hooks apuntaba por defecto ahí y daba verde sobre un fichero que no
había leído nunca. Lo mismo con `probar-rama.sh` desde una rama de dotfiles: la
primera vez que se probaron los dos frenos nuevos, se abrió una PR sin que
ninguno de los dos llegara a ejecutarse.

**Hay que romperlas a propósito para creerlas.** Así se encontró el agujero del
`--ff-only`: la excepción antigua casaba esa cadena en cualquier parte del
comando, así que hasta un `git commit -m "fix the --ff-only thing"` pasaba
limpio. Y así se comprobaron los frenos del 17-08-2026 — desactivada la
comparación de niveles, la matriz da 7 fallos; desactivada la repetición de
checks, 2.

**Una matriz que puede commitear el repositorio que está probando no es una
matriz** *(14-08-2026)*. `abrir` falló, la ruta llegó vacía y `git -C ""`
—documentado como «deja el directorio actual sin cambiar»— hizo el `add -A` y el
`commit` sobre el repositorio desde el que se lanzaba, llevándose dentro el
trabajo sin guardar. Y salió verde: el destrozo no estaba en ninguna aserción,
estaba en otro sitio.

## Los subagentes

**El `code-reviewer` está pedido de antemano** *(14-08-2026)* porque la app
inyecta una instrucción de sesión que prohíbe llamar al Agent tool «unless the
user requested it», y el `CLAUDE.md` de welzy exige ese revisor antes de dar nada
por terminado. Las dos chocaban, y cada tarea acababa en «no he pasado el diff
por `code-reviewer`, mis instrucciones me lo prohíben, dime y lo lanzo». La línea
del `CLAUDE.md` **es** ese permiso, escrito una vez en vez de a diario. No es una
forma de saltarse la regla: la regla pide mi petición, y eso es mi petición.

Un «lanza los que quieras» no, y por eso la lista es corta: una flota de agentes
es como una factura se convierte en un susto.

## La entrevista antes de planificar

Era obligatoria en todo diseño de todo proyecto. Se quedó en «cuando el diseño
está abierto» *(17-08-2026)* por lo mismo que dice la documentación de Anthropic
sobre el plan mode: si el diff se puede describir en una frase, planificarlo
cuesta más de lo que ahorra. Cada pregunta es además un turno con el contexto
entero.
