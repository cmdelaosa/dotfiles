---
name: grill
description: Úsala antes de escribir código para una funcionalidad nueva cuando haya algo que suponer — un detalle que Carlos no dijo y que cambiaría el diseño. Se dispara con «grill me», «hazme un grill», o sola al empezar una funcionalidad con huecos. No se usa cuando el encargo es claro y directo y no hay nada que suponer.
---

# Grill

Antes de escribir una línea, pregunta.

## Cuándo

**Lo disparan las suposiciones, no el tamaño ni la etiqueta de «funcionalidad
nueva».** Si el encargo es claro y directo y no hay nada que suponer, no hay
grill: a trabajar. Si hay que elegir por él en algo que no dijo, sí lo hay, y
basta una pregunta para que lo haya.

## Cómo

1. Lee antes de preguntar. Una pregunta que se contesta leyendo el código es una
   pregunta perdida, y gastarle el turno en ella hace que deje de leer las demás.
2. Haz **solo las preguntas cuya respuesta cambiaría lo que vas a escribir**:
   qué pasa en el caso raro, cuál de dos comportamientos quiere, qué gana si
   chocan dos reglas, qué NO entra. Nada de preguntas de cortesía ni de
   confirmación de lo que ya dijo.
3. **Todas juntas y numeradas**, no de una en una. Cada una con tus opciones en
   una línea corta y con tu recomendación marcada, para que pueda contestarlas
   de un tirón con «1b, 2 sí, 3 la tuya».
4. Si en el camino descubres que una pregunta ya no importa, dilo y retírala.
5. No escribas código hasta que no quede ninguna.

## Si no hay quien conteste

Trabajando en la nube muchas veces Carlos no está delante. La salida **no** es
elegir por él en silencio:

- Haz todo lo que no dependa de la respuesta.
- Deja escrita **la pregunta y la suposición que tomaste** donde se entrega el
  trabajo: el mensaje, la PR, el traspaso.
- Para ahí en lo que sí dependa.

Una suposición escrita se corrige en un minuto; una callada se descubre en la
pantalla, y para entonces ya está construida encima.

## Después

Las respuestas no se quedan en el chat: van al sitio del proyecto que les
corresponda —el plan si es alcance, el registro de decisiones si es una decisión
no evidente, las reglas del producto si es una regla—. Un grill que no deja
rastro se repite dentro de un mes.
