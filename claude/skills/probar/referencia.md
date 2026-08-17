# Cómo leer lo que diga `probar-rama.sh`

Esto **no hace falta leerlo antes**: es la tabla que se consulta cuando el guión
dice algo que no cuadra con el paso en el que crees estar. Vive aquí y no en el
`SKILL.md` porque la skill se carga entera cada vez que arranca la cadena.

- **«No he levantado nada: la pila local se pide.»** → ha terminado sin levantar
  nada. **El verde no lo dice esta línea, lo dice el «Su CI está verde.» de
  debajo**; con `--sin-ci` pone «Su CI está sin mirar», y eso no es un verde. Da
  la URL de la PR y **para ahí**: no cierres, no fusiones, no despliegues.
- **«Lista para probar: http://127.0.0.1:…»** → la pila está arriba. Dale la URL
  y para igual. Di también cómo acabó el CI.
- **«El worktree tiene cambios sin guardar»** → no ha empujado nada. Suele ser lo
  que descartaste de la revisión y se quedó suelto: reviértelo o commitéalo. El
  `--forzar` que ofrece tira esos cambios, y es del usuario.
- **«no tiene ningún commit que origin/main no tenga»** (o «no tiene remoto») →
  no hay nada que empujar y no hay PR que abrir. Con la cadena automática es más
  fácil de lo que parece: se dispara sobre una rama ya fusionada o todavía
  vacía. No lo arregles a base de commits: dilo y para.
- **«verificar.sh ha fallado»** → no ha empujado nada. Arréglalo en el worktree,
  commitea, **vuelve a revisar y a marcar** (la marca ha caducado con ese commit)
  y relánzalo.
- **«Estos commits no han pasado por el revisor»** → te has saltado el paso 2, o
  has commiteado después de marcar. Revisa y `marcar-revisado.sh … --nivel …`.
- **«pide una revisión a 'max'» / «La marca dice low»** → el diff es de un tramo
  más alto del que dice la marca. No se arregla volviendo a marcar con el nivel
  de antes: se lanza `/code-review` al nivel que pide y se marca con ese. El
  mensaje trae las dos órdenes escritas.
- **«sin nivel» (marca de antes de los tramos)** → una marca vieja, de cuando
  solo llevaba el SHA. Revisa y vuelve a marcar diciendo el nivel.
- **«El CI no está verde»** → mira lo que hay debajo antes de darlo por rojo: si
  dice «El CI todavía está corriendo», es que el `--watch` se cayó a mitad y no
  hay nada que arreglar, se relanza el `--esperar-ci`. Con jobs en rojo de
  verdad: arregla, re-revisa, re-marca, relanza.
- **«Ronda N en rojo. Quedan …»** → el guión lleva la cuenta. Sigue arreglando.
- **«PARO: …»** (sale con 3) → se acabó el arreglo automático, por rondas
  gastadas o porque un check que ya había fallado ha vuelto a fallar. Enseña los
  jobs con sus enlaces y para.
- **«La rama no tiene ninguna PR que mirar»** → has lanzado `--esperar-ci` sin
  haber hecho el paso 3. Lánzalo con `--sin-ci` primero.
- **«no ha disparado ningún check»** → normalmente el `paths-ignore` de una PR de
  solo documentación. La PR queda esperando al usuario. Si en cambio dice «este
  repositorio no tiene CI», dilo con esas palabras: no es lo mismo y no hay red.
- **«La pila no responde»** → pásale al usuario la salida de
  `docker compose -p <proyecto> logs`.

## Banderas que existen y no son tuyas

`--sin-verificar`, `--sin-revisar` y `--forzar` los autoriza el usuario. Si crees
que hace falta uno, dilo y que decida él.

`--sin-ci`, `--esperar-ci`, `--solo-pila`, `--con-pila` y `--solo-md` sí son de
la cadena, y están en el `SKILL.md`.
