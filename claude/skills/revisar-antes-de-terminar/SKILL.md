---
name: revisar-antes-de-terminar
description: Úsala antes de dar por terminado cualquier cambio de código — antes de abrir la PR, de decir «listo» o de pedir que se fusione. Hace que el diff lo lea un agente que no lo escribió. Se dispara con «revisa esto», «¿está listo?», o sola al acabar una funcionalidad o un arreglo.
---

# La revisión, antes de dar nada por terminado

**El diff lo lee alguien que no lo escribió. Siempre.** Quien lo escribió ya
sabe qué quería decir y lee eso, no lo que puso.

## Una sola vez, y al nivel que pida el cambio

No dos. Leer la misma PR entera con dos cadenas distintas a esfuerzo máximo,
toque veinte líneas o dos mil, es pagar el doble por el mismo hallazgo.

Y el nivel lo pide el cambio: una hoja no merece lo que merece una ruta
delicada. **Si no hay forma de saber en qué tramo estás, no te fíes: al nivel
más alto.**

## Quién la hace

En este orden, el primero que exista:

1. La cadena de revisión del proyecto, si la tiene.
2. El subagente revisor del repositorio (`.claude/agents/code-reviewer.md` o
   equivalente).
3. Un subagente en contexto limpio al que le pasas el diff y el objetivo
   declarado.

**Una sesión en la nube solo tiene lo que está commiteado en el repositorio**,
así que ahí la 1 casi nunca existe. Eso no convierte la revisión en opcional:
baja al 2 o al 3.

## Qué se le pide

El diff (`git diff` más `git diff --cached`, o contra la rama base) **contra el
objetivo declarado**, buscando lo que los tests y el compilador no ven: lógica
equivocada, casos límite sin tratar (vacío, nulo, frontera, concurrente, ya
existe), condiciones de carrera, fallos silenciosos, errores que se tragan el
contexto para depurar, y alcance que ha crecido más allá de la tarea.

Más los invariantes del repositorio, que están en su `CLAUDE.md` y son los que
salen caros y callados.

Para cada hallazgo: fichero, línea, por qué está mal y el arreglo concreto. Lo
estilístico, marcado como opcional. Si está limpio, una línea. **Que no se
invente trabajo.**

## Después

Los arreglos van en su propio commit (`fix: arreglos de la revisión`), y al
entregar se dice **quién revisó y qué encontró**. Una revisión que no se cuenta
es indistinguible de no haberla hecho.
