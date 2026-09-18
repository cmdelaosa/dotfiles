---
name: commits-a-mi-nombre
description: Úsala antes del primer commit de cualquier sesión, y siempre al trabajar en un contenedor remoto o en Claude Code en la web. Asegura que los commits salen a nombre de Carlos (cmdelaosa), sin firmar y sin trailers, y que la rama no es main y tiene un nombre que dice qué hay dentro.
---

# Los commits salen a mi nombre

## El autor

Autor y committer, siempre: `cmdelaosa <cmdelaosa@gmail.com>`.

**En un contenedor remoto `git config` NO basta.** El contenedor exporta
`GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`, `GIT_COMMITTER_NAME` y
`GIT_COMMITTER_EMAIL`, y una variable de entorno gana a la configuración. Hay
que poner las cuatro:

```bash
git config commit.gpgsign false   # una vez por repositorio, esto sí persiste

GIT_AUTHOR_NAME=cmdelaosa GIT_AUTHOR_EMAIL=cmdelaosa@gmail.com \
GIT_COMMITTER_NAME=cmdelaosa GIT_COMMITTER_EMAIL=cmdelaosa@gmail.com \
git commit -m "..."
```

**Las cuatro variables van delante de cada commit, una por una.** No vale
exportarlas al principio: en una sesión de agente el estado del shell no
persiste entre órdenes, así que el `export` se pierde por el camino y el commit
siguiente vuelve a salir como Claude.

La firma se apaga porque el contenedor trae una clave que no es suya y GitHub
marcaría «Unverified».

**Y se comprueba después del primer commit:**

```bash
git log -1 --format='%an <%ae>'
```

Esto no es ceremonia. **El caso malo no da error**: sale un commit perfecto con
el autor equivocado, y se descubre cuando ya está empujado. Si salió mal, se
arregla en el sitio, con las cuatro variables delante:

```bash
GIT_AUTHOR_NAME=cmdelaosa GIT_AUTHOR_EMAIL=cmdelaosa@gmail.com \
GIT_COMMITTER_NAME=cmdelaosa GIT_COMMITTER_EMAIL=cmdelaosa@gmail.com \
git commit --amend --no-edit --reset-author
```

## El mensaje

Conventional Commits, en español, ultra-incrementales. **Sin `Co-Authored-By` y
sin líneas de sesión**: los commits van a su nombre, no a nombre de quien los
tecleó.

## La rama

Nunca `main` —compruébalo con `git branch --show-current` antes del primer
commit, porque en un contenedor no hay hook que lo impida—, y con un nombre que
diga qué hay dentro (`f47-ficha-de-verdad`), nunca el aleatorio que inventa el
harness (`claude/project-thread-zkk6k5`, `exciting-mayer-19e2d6`). Si la sesión
nació con uno aleatorio, se renombra con `git branch -m` **antes de empujarla**,
para no dejar detrás una referencia remota que luego haya que borrar.

## Lo que no se puede

Si la PR la abre la app de GitHub de Claude, GitHub la firma como `claude[bot]`
y no hay ajuste que lo cambie. Los commits sí salen a su nombre; la autoría de
la PR, no.
