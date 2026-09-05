---
name: auditar
description: Auditoría a fondo de un repositorio ENTERO, no de un diff - doce dimensiones fijas (diseño contra lo decidido, funcionalidad, frontend, tests, rendimiento, seguridad, datos, operación, cumplimiento, duplicación, documentación al día y lo preparado que está para trabajar con IA), un subagente por dimensión en paralelo y un informe con evidencia y coste que vive en el repo, sin tocar código. Usar cuando el usuario diga "audit", "auditoría", "audita el proyecto", "revisa todo el repo", "qué está mal aquí", "¿está la documentación al día?", "¿está optimizado para IA?", "¿hay una forma mejor de hacer esto?" a escala de proyecto, o pida una revisión de calidad general que no sea de una rama o PR concreta; y siempre que diga "/auditar".
---

# Auditar un repositorio entero

`/code-review` lee un diff. Esto lee el repositorio completo a la altura de sus
decisiones: qué se decidió, qué se construyó, qué funciona, qué se prueba, qué
cuesta operar, y si el código y sus md están en condiciones de que una sesión
nueva trabaje encima sin tropezar. **No arregla nada**: produce un informe con
evidencia y coste, y el usuario elige qué hallazgo abre como rama. Mezclar
diagnóstico y cura obliga a discutir cada arreglo antes de ver el conjunto, y
la lista de arreglos de una auditoría es siempre más larga que la que merece
la pena hacer.

**Invocarla es la autorización de sus subagentes.** La regla global pide
preguntar antes de lanzar cualquier subagente que no sea `code-reviewer`; aquí
el usuario ya lo ha pedido al lanzarla. Lo que sí se le dice antes de arrancar
es lo que cuesta: doce subagentes sobre un repo mediano son media hora larga y
varios millones de tokens.

## 0. La rama, y medir una sola vez

**Primero la rama**: `abrir-rama.sh auditoria-<AAAA-MM-DD>` y `EnterWorktree`
con la ruta que imprime. Nada se escribe en `main`, ni un informe; y en un
checkout compartido git está bloqueado hasta salir de él. Todo lo que sigue lee
el repo **desde ese worktree**.

Todo lo que se pueda medir con un comando lo mide el padre aquí, una vez, y lo
deja en un fichero: doce subagentes lanzando la verificación entera son doce
veces cuatro minutos para leer el mismo resultado. Directorio de trabajo,
`<trabajo>` en lo que sigue: `<scratchpad>/auditoria/`, y el scratchpad lo dice el
system prompt. Nada de lo que hay ahí se commitea.

1. **Foto del repo**: fecha, `git rev-parse HEAD`, ramas locales y remotas,
   `git worktree list`, `gh pr list`, los últimos treinta commits, autores del
   último año.
2. **Lo que el repo dice de sí mismo**, leído entero **por ti**, no por un
   subagente: `CLAUDE.md` de la raíz y de cada subdirectorio, `.claude/rules/*`,
   `README`, `docs/` (plan, decisiones, arquitectura, lo que haya). Es el
   contraste de las dimensiones 1 y 11, y lo que te permite escribir un mapa que
   no sea una lista de ficheros.
3. **Medidas**, cada una a su fichero:
   - pila y gestor de paquetes; los paquetes del workspace si lo hay;
   - líneas por paquete y los veinte ficheros fuente más largos;
   - la verificación entera del repo (`./verificar.sh`, `pnpm verify`, lo que
     tenga) con su salida y su tiempo; el recuento de tests si hay comando;
   - auditoría de dependencias y desactualizadas (`pnpm audit`, `pnpm outdated`,
     `pip-audit`…, lo que exista);
   - inventario de markdown con tamaño; cada `CLAUDE.md` con bytes y líneas;
   - `TODO|FIXME|XXX|HACK` con fichero; variables de entorno leídas en el código
     (`process.env.`, `os.environ`) frente a las documentadas;
   - si hay `docs/auditorias/`, la última.
4. **`mapa.md`**, en menos de 150 líneas: qué es el repo, cómo está partido,
   dónde vive cada cosa, cómo se arranca y se verifica, qué documenta, qué dicen
   las medidas y la ruta de cada salida cruda. Es lo único que reciben los
   subagentes además de su dimensión: lo que no esté aquí lo redescubren doce
   veces, cada uno a su manera.

## 1. Doce dimensiones, un subagente cada una, a la vez

| # | dimensión | la pregunta |
|---|---|---|
| 1 | Diseño | ¿el producto es lo que se decidió, y lo decidido sigue siendo lo mejor? |
| 2 | Funcionalidad | ¿cierra el bucle principal de punta a punta, como dicen los docs? |
| 3 | Frontend | ¿cada pantalla carga lo justo, dice lo que pasa y sirve a quien la usa? |
| 4 | Tests | ¿lo que sale caro si falla tiene test, y ese test puede fallar? |
| 5 | Rendimiento | ¿dónde se paga de más: consultas, cargas, tamaños, tiempos? |
| 6 | Seguridad | ¿quién puede hacer qué, y qué entra sin comprobar? |
| 7 | Datos | ¿el esquema impide lo que la regla prohíbe, y las migraciones van y vuelven? |
| 8 | Operación | ¿si se cae, se sabe, se recupera y se sabe cuánto se perdió? |
| 9 | Cumplimiento | ¿cada norma del dominio tiene regla, fuente y test, y los datos reales están donde deben? |
| 10 | Duplicación y código muerto | ¿qué está dos veces, qué no se usa, qué interruptor no cambia nunca? |
| 11 | Documentación | ¿todo lo que los md afirman existe y es verdad hoy? |
| 12 | Trabajar con IA y herramientas | ¿una sesión nueva encuentra lo que necesita, lo verifica en segundos y no puede romper `main`? |

El detalle de cada una —qué mirar, qué no es hallazgo, cómo medirlo— está en
[dimensiones.md](dimensiones.md), por secciones. No lo cargues entero: cada
subagente lee la suya.

Lánzalos **todos en el mismo mensaje**, `subagent_type: general-purpose`, en
segundo plano. En un repo pequeño agrupa (2+3, 7+8, 10+11) y lanza menos; lo
que no cambia es que cada dimensión se responde. El prompt de cada uno:

```
Auditas la dimensión <n> (<nombre>) del repositorio en <ruta del worktree>.
Lee primero <trabajo>/mapa.md y después SOLO la sección <n> y el «Formato del
parcial» de <directorio de esta skill>/dimensiones.md.
No modifiques ningún fichero del repositorio ni lances nada que escriba,
despliegue o borre; las medidas caras ya están hechas y el mapa dice dónde.
Cada hallazgo lleva evidencia que otro pueda comprobar —fichero:línea o un
comando con su salida— o va en «Sospechas», aparte.
Escribe el resultado en <trabajo>/dimension-<nn>.md con ese formato y termina
con la línea de recuento que pide.
```

`<directorio de esta skill>` es el que dice «Base directory» al cargarla.
Cuando lleguen las notificaciones no leas los parciales según caen: espera a
los doce y consolida de una vez. Leerlos uno a uno es reordenar once veces.

## 2. Consolidar

Lee los doce parciales, y con ellos:

- **Junta lo repetido**: el mismo fichero largo sale en 10, 11 y 12; el mismo
  endpoint sin guarda sale en 2 y 6. Un hallazgo, con las dimensiones que lo
  vieron.
- **Ordena por impacto y luego por coste**: primero lo que pierde datos, dinero
  o a un cliente; después lo que encarece todo lo demás (la cadena, los docs);
  al final lo cosmético. Dentro de cada impacto, lo barato antes.
- **Conserva lo sano**: cada parcial trae hasta tres cosas que están bien; van
  juntas. Una auditoría que solo lista fallos hace que se toque lo que funciona.
- **Lo que no se pudo medir** va con su motivo: que falte una pila levantada o
  un acceso no es un cero, es un hueco con nombre.
- **Si hay auditoría anterior**, una sección al final: qué de aquello se cerró
  y qué sigue abierto, con su identificador de entonces.

## 3. El informe vive en el repo

Es un documento con destinatario que se vuelve a leer, así que va a git, no al
chat: `docs/auditorias/<AAAA-MM-DD>.md`, en la rama del paso 0.

```markdown
# Auditoría — <AAAA-MM-DD>

Sobre el commit <sha corto>. Doce dimensiones, <n> subagentes. <Lo que no se midió, en una línea.>

## Los diez primeros
| # | hallazgo | dimensiones | impacto | coste | qué compra |

## Lo que está sano
## Por dimensión
### 1. Diseño
#### D1-01 · <título>
- **Evidencia**: fichero:línea, o el comando y su salida.
- **Por qué importa**:
- **Propuesta**: la mínima; si es cambiar de forma, qué cuesta, qué compra y cuándo.
- **Impacto** · **Coste**: S (una tarde) · M (uno o dos días) · L (más, o toca lo sensible).
…
## Sospechas sin evidencia
## Lo que no se pudo medir
## Contra la auditoría de <fecha anterior>
```

Los identificadores `D<dimensión>-<orden>` no se reciclan: son el nombre de la
rama que arregle cada uno y lo que la siguiente auditoría busca.

Commiteado el informe, la rama solo toca markdown: arranca la cadena de
`probar` por su atajo —`probar-rama.sh <rama> --solo-md`—, que pregunta si
fusionar. Fusionar el informe no arregla nada; lo deja donde se encuentra.

## 4. Contárselo al usuario

Corto: la ruta del informe, los diez primeros en tabla, la URL de la PR. Y la
pregunta que toca de verdad: **cuáles abre como rama, y en qué orden**. Ninguna
se abre sola: la lista de arreglos es suya.

## Lo que hay que tener claro

- **Durante la auditoría no se arregla nada**, ni lo pequeño. Un «ya que estoy»
  en mitad de doce subagentes es un cambio sin rama, sin revisión y sin
  informe. Al informe, con coste S.
- **La evidencia es lo que la separa de una opinión.** «Parece que» va a
  sospechas; lo demás lleva fichero y línea, o comando y salida, y cualquiera
  lo reproduce sin haber estado en la sesión.
- **Las cifras llevan fecha**, en el informe y en cualquier doc al que se copien.
- **Diseño no es «reescríbelo como lo haría yo»**: una forma mejor solo entra
  con lo que cuesta, lo que compra y cuándo conviene —ahora, la próxima vez que
  se toque, o nunca—.
- **La segunda auditoría vale más que la primera**: es la que mide si lo que se
  abrió como rama se cerró de verdad. Por eso los identificadores no se reciclan.
