# Las doce dimensiones de `auditar`

Cada subagente lee **solo su sección** y el «Formato del parcial» del final.
Las secciones se parecen a propósito: la pregunta, qué mirar, qué no es un
hallazgo y cómo medirlo. Lo de «no es hallazgo» está para que el parcial no se
llene de ruido: cada línea que el usuario descarta le cuesta la confianza en la
siguiente.

## 1. Diseño: lo decidido, lo construido y lo que se haría hoy

**Pregunta**: ¿el producto es lo que se decidió, y lo decidido sigue siendo lo
mejor con lo que se sabe hoy?

**Qué mirar**
- Cada decisión escrita (`docs/DECISIONS.md`, el plan, los `CLAUDE.md`, las
  `rules`) contra el código que la implementa. Tres estados: cumplida,
  incumplida (el código hace otra cosa) y **vacía** (se decidió y nunca se
  construyó). El cuarto —decisión que el código encarna y nadie escribió— se
  anota aquí y lo hereda la dimensión 11.
- Las reglas de reparto del propio repo (qué va en cada paquete, qué no importa
  a qué): cada violación con el fichero que la comete.
- Lo que se hizo con una idea en mente y acabó siendo otra cosa: abstracciones
  para un caso que nunca llegó, capas que solo delegan, configuración para
  variar lo que nunca varía, una entidad partida por donde no era.
- **Mejores formas**: por cada zona importante, «si se hiciera hoy, ¿qué se
  haría distinto?», con coste, beneficio y cuándo (ahora / al tocarlo / nunca).

**No es hallazgo**: una decisión que no te gusta pero está escrita, cumplida y
con su porqué; una preferencia de estilo; proponer otro framework.

**Cómo medir**: lee las decisiones enteras antes que el código. Por cada una,
`grep` de los nombres que usa y lectura del punto donde se aplica. Para el
reparto, la lista de imports entre paquetes (`grep -rn "from '@` o su
equivalente) cruzada con lo que la regla prohíbe.

## 2. Funcionalidad: el bucle principal cierra

**Pregunta**: ¿lo que el repo afirma que funciona, funciona de punta a punta, y
como lo usa quien lo usa de verdad?

**Qué mirar**
- El bucle principal del producto (en un ERP, pedido → entrega → factura →
  cobro; en una API, petición → efecto → respuesta), seguido en el código paso
  a paso: entradas, estados, salidas, y qué pasa en cada rama de error.
- Fases o hitos marcados como hechos cuyo bucle no cierra: una pantalla que
  existe pero no llega a lo que promete, un estado del que no se sale.
- Lo que el usuario real hace frente a lo que hay: si los docs dicen que algo
  no se ha medido con él (cómo imprime, cómo cobra), es hallazgo, no nota.
- Estados vacíos, errores que el usuario ve, validaciones que existen en la API
  y no en la pantalla, o al revés.

**No es hallazgo**: lo que el plan marca como futuro o aplazado; lo que un
interruptor apaga a propósito en una instancia.

**Cómo medir**: en código, cada paso del bucle con su fichero y línea. Si hay
una pila levantada (el mapa lo dice, o `docker compose ps`), recórrela en el
navegador con `read_page`, sin escribir datos.

## 3. Frontend

**Pregunta**: ¿cada pantalla carga lo justo, dice lo que pasa y sirve a quien
la usa?

**Qué mirar**
- Rutas y lo que carga cada una: listas enteras donde debería haber páginas,
  peticiones repetidas, estado global que crece sin límite.
- Tamaño del bundle y qué lo engorda (iconos enteros, librerías por una
  función, fuentes desde un tercero si la regla lo prohíbe).
- Estados: cargando, vacío, error, sin permiso. Y qué ve el usuario cuando la
  API falla.
- Accesibilidad básica: foco, etiquetas, contraste, teclado en formularios.
- Idioma: cadenas en el idioma equivocado, sobre todo en lo que se imprime.
- Componentes repetidos entre pantallas, o entre productos, con el mismo fin.

**No es hallazgo**: gusto visual; lo que el diseño elegido hace a propósito.

**Cómo medir**: el árbol de rutas del router; `grep` de las llamadas a la API
por pantalla; la salida del build con tamaños, que el mapa trae si el padre la
sacó; una pasada con `read_page` si hay pila.

## 4. Tests

**Pregunta**: ¿lo que sale caro si falla tiene test, y ese test puede fallar?

**Qué mirar**
- Reglas de cálculo, dinero, fecha, fiscalidad, permisos, inmutabilidad: cada
  una con su test, o listada como sin él.
- Tests que no pueden fallar: sin aserción, asertando sobre el mock, con el
  esperado calculado por el mismo código que prueban, o con `expect` dentro de
  una rama que nunca se ejecuta.
- El bucle principal con un test de extremo a extremo, o sin él.
- Tests saltados (`skip`, `only`, `todo`), lentos, flakys conocidos.
- Cuánto tarda la suite y qué necesita (Docker, red).

**No es hallazgo**: el porcentaje de cobertura por sí solo; un unitario que
falta en una utilidad trivial.

**Cómo medir**: la lista de tests del mapa cruzada con las reglas de la
dimensión 9 y con los módulos de cálculo; una muestra de tests por paquete
leída buscando las cuatro formas de no poder fallar;
`grep -rn "\.skip\|\.only\|\.todo"`.

## 5. Rendimiento

**Pregunta**: ¿dónde se paga de más?

**Qué mirar**
- Consultas en bucle (N+1), sin índice para su `WHERE` u `ORDER BY`, que traen
  columnas o filas que luego no se usan.
- Respuestas grandes: endpoints que devuelven todo cuando la pantalla pinta
  veinte; su tamaño real si se puede medir.
- Trabajo repetido: cálculos por petición que no cambian, recargas de lo
  mismo, ficheros generados que no se cachean.
- Tiempo de build, de verificación y de CI: lo que cada cambio paga.

**No es hallazgo**: una micro-optimización sin medida; lo que no está en el
camino de nadie.

**Cómo medir**: `grep` de consultas dentro de bucles y `map`; los índices del
esquema frente a los `WHERE` reales; con pila, `read_network_requests` para
tamaños; los tiempos del mapa.

## 6. Seguridad

**Pregunta**: ¿quién puede hacer qué, y qué entra sin comprobar?

**Qué mirar**
- Cada endpoint con su autenticación y su autorización —rol, entidad,
  inquilino—. Los que no la tienen, con su ruta.
- Puertas de desarrollo (`SIN_AUTH`, usuarios semilla, claves por defecto), y
  si algo impide que lleguen a producción.
- Secretos en el repo o en su historia; contraseñas en claro en datos o
  ficheros importados.
- Entradas: subida de ficheros, consultas construidas con texto, plantillas
  renderizadas con datos del usuario, PDF o HTML generados por un navegador
  interno.
- Dependencias con aviso (el `audit` del mapa), CORS, cabeceras, límites de
  tamaño y de tasa.

**No es hallazgo**: un aviso de `audit` en una dependencia de desarrollo sin
camino a producción, dicho como tal.

**Cómo medir**: la lista de rutas del framework cruzada con sus guardas (`grep`
del decorador o middleware); `git log -p -S` de las cadenas que huelen a
secreto; `grep -rn` de los interruptores de desarrollo.

## 7. Datos

**Pregunta**: ¿el esquema impide lo que la regla prohíbe, y las migraciones van
y vuelven?

**Qué mirar**
- Reglas que la base debería imponer y solo impone la API: unicidad,
  inmutabilidad, referencias, rangos.
- Migraciones: reversibles o no, con datos o sin ellos, numeración que puede
  chocar entre ramas, alguna aplicada a mano en producción.
- Índices que faltan o sobran; tipos que mienten (dinero en float, fechas en
  texto, zona horaria ausente).
- Huérfanos posibles: borrados sin cascada ni bloqueo.

**No es hallazgo**: una columna nullable que el dominio permite nula.

**Cómo medir**: el esquema y las migraciones leídos enteros; los `comprobar-*`
que el repo tenga, con su salida; con base levantada, consultas de integridad
de solo lectura.

## 8. Operación

**Pregunta**: si se cae, ¿se sabe, se recupera, y se sabe cuánto se perdió?

**Qué mirar**
- Copias de seguridad: si existen, cada cuánto, dónde, y si alguien ensayó
  restaurar una. Sin ensayo no hay copia.
- Despliegue: reproducible, imagen construida donde debe, variables
  documentadas, vuelta atrás.
- Salud y avisos: qué señal llega a alguien cuando el servicio deja de
  contestar, se llena el disco o falla una tarea programada.
- Resiliencia: base caída, servicio externo sin responder, navegador de PDF
  muerto; qué ve el usuario y qué se queda a medias.
- Registros: bastan para reconstruir qué pasó, sin datos personales de más.
- Zona horaria y reloj en cada sitio donde corre.

**No es hallazgo**: lo que los docs de despliegue ya dicen que falta y por qué,
si tiene fecha y dueño.

**Cómo medir**: los ficheros de despliegue y sus docs; `grep` de los `catch` y
qué hacen; la definición de las tareas programadas.

## 9. Cumplimiento

**Pregunta**: ¿cada norma del dominio tiene regla, fuente y test, y los datos
reales están donde deben?

**Qué mirar**
- Si el repo tiene un informe legal o una lista de normas, cada regla
  implementada con su artículo y su test; las reglas sin fuente y las fuentes
  sin regla.
- Plazos legales que obligan al producto y no solo a quien lo usa.
- Datos personales: qué se guarda, quién lo ve, cuánto tiempo, y qué deber
  recae en quien instala el programa frente a quien lo entrega.
- Datos reales de clientes fuera de producción: copias locales, semillas,
  fixtures, capturas en docs.
- Documentos que salen impresos: idioma, campos obligatorios, numeración.

**No es hallazgo**: una norma que el producto declara fuera de alcance, por
escrito.

**Cómo medir**: el informe legal o las `rules` fiscales contra `grep` de cada
regla en código y tests; `git ls-files` buscando exportaciones, volcados y csv
con datos.

## 10. Duplicación y código muerto

**Pregunta**: ¿qué está dos veces, qué no se usa, y qué interruptor no cambia
nunca?

**Qué mirar**
- Lógica repetida entre paquetes o productos con el mismo fin; utilidades que
  existen en el núcleo y se reescribieron en una hoja.
- Exports sin uso, ficheros que nadie importa, ramas inalcanzables.
- Interruptores (flags, variables de entorno): cada uno con sus dos ramas
  probadas, o retirado; los que están siempre en el mismo valor.
- Los `TODO` y `FIXME` del mapa: cuáles siguen vigentes y cuáles se
  resolvieron sin borrarlos.
- Dependencias sin usar, duplicadas entre paquetes o desactualizadas (del
  mapa), y qué costaría subir cada una.

**No es hallazgo**: dos funciones parecidas con distinto motivo de cambio.

**Cómo medir**: `knip`, `ts-prune`, `depcheck` o el equivalente si están; si
no, `grep` de cada export. Los flags, `grep -rn` de cada nombre: dónde se lee
y dónde se fija.

## 11. Documentación al día

**Pregunta**: ¿todo lo que los md afirman existe y es verdad hoy?

**Qué mirar**
- Cada ruta, comando, puerto, variable, script y nombre de paquete citado en
  un md: existe y hace lo que dice.
- Cada cifra —tests, tamaños, tiempos, fases hechas— vuelta a medir; si no
  lleva fecha, es hallazgo aunque coincida.
- Estados: fases o tareas marcadas como hechas o pendientes que ya no lo están;
  decisiones que el código encarna y ningún doc recoge.
- README de cada herramienta contra su `--help` y lo que hace.
- Comentarios en código que citan fechas, fases o tickets: siguen siendo
  verdad.
- Lo que vive dos veces (dos md que cuentan lo mismo) y cuál manda.

**No es hallazgo**: prosa histórica con fecha que se presenta como historia.

**Cómo medir**: un guión rápido: extrae de cada md lo que parezca ruta
(`[a-zA-Z0-9_./-]+\.(sh|ts|tsx|md|yml|yaml|json|sql)` y rutas con `/`) y
comprueba `test -e` desde la raíz; extrae los comandos de los bloques de código
y búscalos en `package.json`, `Makefile` o `bin/`; puertos y cifras, a mano
contra el mapa.

## 12. Trabajar con IA y la cadena de herramientas

**Pregunta**: ¿una sesión nueva encuentra lo que necesita, lo verifica en
segundos y no puede romper `main`?

**Qué mirar**
- Las instrucciones que se cargan siempre (`CLAUDE.md` raíz) frente a las que
  se cargan por ruta (`.claude/rules/`, `CLAUDE.md` por directorio): lo que
  está en la raíz y solo sirve al tocar un directorio; la crónica que debería
  vivir en git o en un doc de porqués; bytes y líneas.
- El contraste es `~/.claude/templates/project/`: `CLAUDE.md` de menos de 80
  líneas, reglas por ruta, subagente `code-reviewer`, `verificar.sh` rápido y
  con nombre fijo, `docs/ARCHITECTURE.md` y `docs/DECISIONS.md`. Lo que falte,
  con qué cuesta no tenerlo.
- Ficheros fuente que no se editan de una pieza: más de 500 líneas, o tres
  responsabilidades mezcladas.
- Nombres que dicen qué hacen; comentarios que dicen por qué y no qué; tests
  con nombre de especificación.
- Scripts con `--help`, ejecutables de una línea, que dicen qué han hecho y qué
  no.
- `verificar.sh`: cuánto tarda, si filtra por diff y si el filtro puede
  saltarse un dependiente. CI: tiempo, flakys, si juzga lo mismo.
- Hooks y settings del repo: lo que impiden y lo que dejan pasar.
- Higiene: ramas y worktrees huérfanos, PR abiertas sin actividad, ficheros de
  sesión dentro del repo.

**No es hallazgo**: un md largo que solo se carga cuando toca.

**Cómo medir**: `wc -c` y `wc -l` de cada `CLAUDE.md` sin comentarios HTML; los
veinte ficheros más largos del mapa; `git branch -a`, `git worktree list`,
`gh pr list`; el tiempo de `verificar.sh` del mapa; lectura de
`.claude/settings.json` y de los hooks.

## Formato del parcial

Cada `dimension-<nn>.md`:

```markdown
# <n>. <Dimensión>

## Hallazgos
### D<n>-01 · <título de una línea>
- **Evidencia**: fichero:línea, o comando y salida, que otro pueda repetir.
- **Por qué importa**: qué se pierde o qué se paga si sigue así.
- **Propuesta**: la mínima que lo resuelve; si es cambiar de forma, coste,
  beneficio y cuándo.
- **Impacto**: alto (datos, dinero, cliente, legal) · medio (encarece lo
  demás) · bajo.
- **Coste**: S (una tarde) · M (uno o dos días) · L (más, o toca lo sensible).

## Lo que está bien
Tres cosas como mucho, con su evidencia: las que nadie debería tocar.

## Sospechas
Lo que parece y no se pudo demostrar, y qué haría falta para demostrarlo.

## No medido
Qué no se pudo mirar y por qué.

## Contra la auditoría anterior
Solo si el mapa dice que la hay: de sus hallazgos de esta dimensión, cuál está
cerrado y cuál sigue abierto.
```

Los hallazgos van ordenados por impacto y luego por coste. La última línea del
fichero es el recuento, que es lo primero que lee el padre:
`Hallazgos: <n> (alto <a>, medio <m>, bajo <b>) · S <s> · M <m> · L <l>`.
