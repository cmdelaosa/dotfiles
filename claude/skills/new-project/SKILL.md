---
name: new-project
description: Scaffold the project harness into the current directory — lean CLAUDE.md, path-scoped rules, code-reviewer subagent, plan-mode gate, verify entrypoint and docs skeleton.
disable-model-invocation: true
argument-hint: "[project name]"
allowed-tools: Read, Write, Edit, Bash, Glob
---

Scaffold `~/.claude/templates/project/` into the current directory, then fill it in
from an interview. Never guess a placeholder — ask.

## 1. Refuse to clobber

Check for `CLAUDE.md`, `.claude/rules/` and `.claude/settings.json`. If any exists,
report exactly what is already there and stop. Continue only if the user says so,
and even then never overwrite an existing file.

## 2. Detect the stack

Look for `package.json`, `build.gradle.kts`, `build.gradle`, `pyproject.toml`,
`go.mod`, `Cargo.toml`. Read the scripts/tasks section — that is where the verify
command usually already exists under another name. If the directory is empty, ask.

## 3. Interview

One question at a time, via AskUserQuestion. Recommendation first with a short
justification, then 2-4 alternatives. Prefer reading the repo over asking.

Collect: `PROJECT_NAME`, `ONE_LINE_PURPOSE`, `STACK`, `LAYOUT`, `GOTCHAS`,
`VERIFY_CMD`, `DEV_CMD`, `TEST_ONE_CMD`.

Then ask one more: **is this long-lived or throwaway?**

| Answer | `MODEL` | `EFFORT` |
|---|---|---|
| Long-lived — real product, code I'll maintain | `opus` | `high` |
| Throwaway — script, spike, one afternoon | `sonnet` | `medium` |

## 4. Copy

Copy every file from `~/.claude/templates/project/` into the current directory,
preserving structure, including the dotfiles under `.claude/`. Skip any file that
already exists and report each skip.

`gitignore.snippet` is not copied — see step 8.

## 5. Substitute

Replace every `{{PLACEHOLDER}}` in the copied files. Then run:

```
grep -rn '{{' . --include='*.md' --include='*.json'
```

If anything matches, stop and report it. A shipped stub is worse than an error.

## 6. Verify entrypoint

If `VERIFY_CMD` doesn't exist yet, create it — an npm script, a Gradle task, a
Makefile target — chaining format, lint, typecheck and test for the detected stack.

It must print each step's real output, not just a pass/fail. The whole point is that
evidence can be shown rather than asserted.

## 7. Format hook

Pick `FORMAT_HOOK_CMD` for the stack:

| Stack | Command |
|---|---|
| TypeScript / JavaScript | `jq -r '.tool_input.file_path // empty' \| xargs -r npx prettier --write` |
| Python | `jq -r '.tool_input.file_path // empty' \| xargs -r ruff format` |
| Go | `jq -r '.tool_input.file_path // empty' \| xargs -r gofmt -w` |
| Rust | `jq -r '.tool_input.file_path // empty' \| xargs -r rustfmt` |

`// empty` is not optional. Plain `jq -r '.tool_input.file_path'` prints the literal
string `null` when the field is absent, `xargs -r` does not filter it, and the
formatter is then invoked on a file called `null`.

If the stack has no fast per-file formatter — Kotlin and Gradle included — **delete
the entire `hooks` block** from `.claude/settings.json`. `VERIFY_CMD` covers
formatting there. A hook that errors on every edit is worse than no hook.

## 8. Gitignore

Append the contents of `~/.claude/templates/project/gitignore.snippet` to the
project's `.gitignore`, skipping any line already present. Create the file if there
isn't one.

## 9. Report

At most five lines:

- What landed, and anything skipped because it already existed.
- Anything still `TODO` — usually `docs/ARCHITECTURE.md` and the first entry in `docs/DECISIONS.md`.
- That the new settings need a fresh session, and the first one will show a
  workspace-trust dialog listing the allow rules and hooks — it must be accepted or
  none of them apply.
- Suggest browsing `/plugin` for the code-intelligence plugin matching this
  language. It replaces grep-plus-read-several-files with one jump to a definition,
  and file reads are the biggest consumer of context.
