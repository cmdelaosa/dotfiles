---
name: despliega
description: Despliega a producción una app del contrato cmdlo (hoy welzy) con cmdlo-infra/desplegar.sh. Usar cuando el usuario diga "despliega", "deploy", "sube a producción" o pida desplegar lo último de main.
---

# Despliega

El único camino de despliegue es el script. No improvises `ssh`, no edites
`.env.production` a mano, no uses nunca la etiqueta `main` ni `docker compose up`
directo en el servidor.

```bash
~/Projects/cmdlo-infra/desplegar.sh <app> [sha] [--simulacro] [--forzar]
```

## Qué app

- Si el directorio de trabajo es el repo de una app desplegable —tiene
  `ops/deploy/deploy.sh` y un `release.yml` que publica etiquetas `sha-`—, esa.
  Hoy la única es **welzy**.
- Si no se deduce, pregunta. **faro/erp no se despliega con esto**: publica
  versiones a mano (`publicar.sh`) y es otro diseño.

## Cómo lanzarlo

- Sin sha despliega el tip de main; con sha, ese commit.
- **Nunca añadas `--vuelta-atras` por tu cuenta.** Es lo que autoriza desplegar un
  commit que no desciende del que sirve, y volver atrás lo decide el usuario.
- Si el release aún se está construyendo el script espera (hasta 35 min): lánzalo
  con `run_in_background`, o con timeout de 600000 si el release ya está en verde.
- No hace falta `--simulacro` antes de cada despliegue (la red es el backup y el
  rollback de deploy.sh); úsalo si el usuario quiere ver qué pasaría.

## Cómo leer el resultado

- «ya sirve sha-…» → no hay nada que desplegar; dilo y para.
- «ME NIEGO: sha-… no desciende de lo que sirve» → el despliegue iría hacia atrás
  (o no se pudo probar que no). Enseña los dos shas y cuántos commits se
  perderían, y **pregunta**: si el usuario dice que sí, se repite con
  `--vuelta-atras`. Casi siempre significa que alguien desplegó algo más nuevo
  mientras tanto y lo que hay que hacer es lo contrario: desplegar el tip de main.
- Enseña al usuario el delta de commits que imprime el script, y cualquier línea
  que empiece por «OJO» (unidades systemd, claves nuevas del example): son pasos
  manuales que el despliegue no hace.
- Exit ≠ 0 → pega la salida entera. Si dice «Rolling … back», deploy.sh ya
  devolvió los contenedores anteriores; si lo roto fue la migración, esa salida
  incluye el comando de restauración exacto. **No lo ejecutes por tu cuenta**:
  restaurar la base de datos es decisión del usuario.
- Si aparece un enlace `cdn-cgi/access`, el certificado de Access caducó: pide al
  usuario correr `ssh ssh.cmdlo.com true` y completar el login del navegador, y
  reintenta.
