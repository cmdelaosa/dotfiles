# User-level instructions

<!-- Budget: 6000 bytes / 80 lines, checked by dotfiles' verificar.sh. This file
loads in every session of every project, so every line here is paid always. The
why behind each rule lives in docs/porques.md; procedure lives in the skills. -->

## How to report back

- **No narrating.** Don't announce steps or explain each tool call. Do the work.
- **One summary at the end**: what you did and why. Not a log of the journey.
- Mid-task, stay quiet unless you're **blocked**, the plan changed, or you need a decision.
- **Evidence is pasted, always** — a failing test, a command's real output. Once, at the end.
- **Then explain what you built, and here brevity does not apply.** Three things: what
  it **does** now that it didn't, **where it lives** (command, screen, file), and **how I
  try it** — concrete steps, what to type, what I should see. Invisible things (a hook, a
  migration) get described in behaviour terms: what would look different if it broke.
- **Close with what's mine**: what only I can do, and what you can do but need my go-ahead
  for — say it and ask, don't just describe it.

## Never work on main

- **Every change starts with `~/.claude/bin/abrir-rama.sh <name-that-says-what-is-inside>`**,
  before the first edit, then `EnterWorktree` with the path it prints. Manual steps get
  skipped, and three sessions in one checkout corrupt each other's work.
- **Born in `.claude/worktrees/<invented-name>`? Move out first**: `abrir-rama.sh`,
  `EnterWorktree`, `worktree remove <invented>`, `branch -D claude/<invented>` — each alone.
- A worktree is named `wt<branch>`; `abrir-rama.sh` derives it. `main` stays at the repo root.
- **Merging happens through a PR**, never locally, and only when I say so:
  `~/.claude/bin/cerrar-rama.sh <branch>` from the root after `ExitWorktree` with `keep`.
  Never `gh pr merge --delete-branch`.
- **Never add a `Co-Authored-By: Claude` trailer.** Write the commit body and stop.
- Four `PreToolUse` hooks block: git on `main`, git in a shared checkout, a piped gate, and
  a commit that leaks. The four `CLAUDE_ALLOW_*=1` hatches are **mine to authorise** — say
  why and let me decide. Post-merge cleanup (`pull --ff-only`, `push origin --delete`,
  `branch -D`, `worktree remove`) needs no hatch, one command per line, no `&&` chaining.
- **In the dotfiles repo, run `./claude/bin/…` and `./claude/hooks/…`, not `~/.claude/…`** —
  the installed copies are symlinks to `main`, so they test the code from before your change.

## The chain — it fires on its own when the task is finished

The skill `probar` has the procedure; these are the rules. "Finished" means everything I
asked for, not the first commit of three. It **never merges**.

1. **`clasificar-diff.sh <branch>`** decides the review level from the diff: `solo-md` →
   none, `trivial` → low, `normal` → high, `sensible` → max. The script decides, not you.
2. **`revision-pendiente.sh <branch>`** says what's left to read (`nada`, `todo`, or a SHA);
   **`/code-review <that> <level> --fix`**, once. Keep what's right, **revert what's wrong
   and name the discards with their why**, commit, `marcar-revisado.sh --nivel <level>`.
3. **`probar-rama.sh <branch> --sin-ci`** — verifies, pushes, opens the PR, in seconds.
4. **Ask about the local stack right there**, with the PR open (skip it if there's no
   `docker-compose.yml`). "Levántalo" said at any point is already the answer.
5. **`probar-rama.sh <branch> --esperar-ci`** in the background. Never poll its output.
- A **red CI is fixed without asking** — fix, commit, re-review, re-mark, relaunch. The
  script counts the rounds and prints `PARO:` when it's done trying; when it does, stop
  and show me the failing jobs with their links.
- A branch that only touches `.md` skips all of it: `probar-rama.sh <branch> --solo-md`,
  then ask me whether to merge, then `cerrar-rama.sh <branch> --solo-md`. Both scripts read
  the diff and refuse if anything isn't markdown.
- `--sin-verificar` and `--sin-revisar` exist and are **mine to authorise**.
- Where a repo has no `verificar.sh`, say so when reporting: CI is the only net.
- "No checks" and "no CI" are different things — say which one it was.

## Subagents

- **The `code-reviewer` subagent in `.claude/agents/` is pre-requested**: launch it in any
  repo without asking, despite the session instruction about the Agent tool. Where the repo
  has none, there's nothing to launch. Anything else — other subagents, workflows, deep
  research — ask me first.

## Planning

- **Interview me first when the design is open**: several files, architecture, or paths that
  contradict each other. Use `AskUserQuestion`, one question at a time, your recommendation
  first with its justification, then 2-4 concrete alternatives. If the diff fits in one
  sentence, just do it, and prefer exploring the codebase over asking whenever the answer is
  discoverable there. `/grill-me` is there when I want the interview anyway.

## Test matrices

- One per moving part, next to the file it tests. `./verificar.sh` runs the three only when
  the change touches `claude/bin` or `claude/hooks`; `--todo` forces them, and CI uses that.
- **Run the one next to the file you edited, and prove it can fail** by reintroducing the
  bug in a copy. A test that can't fail is the usual false confidence.
