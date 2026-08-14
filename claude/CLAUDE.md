# User-level instructions

## How to report back — short, and at the end

- **No narrating.** Don't announce what you're about to do, don't describe each step as you take it, don't explain the reasoning behind every tool call. Just do the work.
- **One summary at the end**, easy to read: what you did, why, and nothing else. Not a log of the journey.
- **Close with what's mine to do.** Separate it clearly:
  - actions only I can take (dashboards, passwords, decisions),
  - actions you can take but need my go-ahead for — say so and ask, don't just describe them.
- Evidence still gets pasted (a failing test, a command's real output) — brevity never applies to proof. But paste it once, at the end, not step by step.
- Mid-task, stay quiet unless you're **blocked**, you hit something **that changes the plan**, or you need a **decision**. Then say it in a line or two, not a report.
- This overrides any default urge to be thorough in prose. Be thorough in the *work*, terse in the *telling*.

### And then explain what you built — this part is not terse

The rules above are about the *journey*, and they work. What they were missing is
the *result*: a summary of files touched tells me what you did, not what the thing
now does, and I'm the one who has to use it and try it.

- **Every time you finish, add a plain explanation of the functionality**, after
  the summary and before what's mine to do. Not what you touched — what it now
  **does** that it didn't before.
- **Three things, always**: what changed in behaviour, **where it lives** (the
  screen, the menu, the command, the endpoint, the file), and **how I try it** —
  the concrete steps, with the URL, what to type and what I should see. Write it
  for someone who didn't watch you build it, because by tomorrow that's me.
- **Brevity does not apply here**, same as it never applied to evidence. Terse
  about the journey, complete about the result. If the feature needs ten lines to
  be clear, take ten lines — what it must not have is filler.
- **If it isn't visible on screen** (a hook, a migration, a refactor), say it in
  behaviour terms anyway: what would look different, and how I'd notice if it
  broke.
- Applies **in every project**, not just the one where it came up *(2026-08-13)*.

## Branch, PR, merge — never work on main

- **Work never happens on `main`.** Every change — in any repo — starts with `~/.claude/bin/abrir-rama.sh <name-that-says-what-is-inside>`, which opens the branch *and* its worktree and prints the path to enter with `EnterWorktree`. Not a courtesy: on 2026-08-13 three sessions landed in welzy's root at once, one moved HEAD under another, a WIP ended up inside someone else's PR (`5b727d2`, now in main's history) and a `commit` went straight onto `main`. Nobody chose to skip the worktree; opening one was a manual step, and manual steps get skipped. **Do this before touching the first file**, not after the first edit.
- **Merging happens through a pull request, not locally.** Open it with `gh pr create`. The PR is where CI runs; a change that hasn't been judged by CI doesn't get merged.
- **Closing has two halves, and the second one is mine to trigger.** First `~/.claude/bin/probar-rama.sh <branch>`: it runs the branch's `verificar.sh`, refuses to push an unreviewed diff, pushes, opens the PR, waits for CI and — only on green — brings up that branch's own local stack (its own Compose project, its own port, a *copy* of my data volume) and notifies me. It **never merges**. Run it in the background; welzy's CI takes ~12 minutes. Then I look at it. If something needs changing, change it in the branch and run it again — that is the point: `main` gets one clean merge instead of three commits fixing what testing revealed.
- **Two things happen before the push, and the skill `probar` is where they live** *(2026-08-13)*:
  - **`verificar.sh` at the repo root** — the checks that are cheap here and cost a full CI round trip there. `probar-rama.sh` runs the **worktree's** copy and refuses to push if it fails. Keep it in seconds: welzy's is 4s (Compose, both overlays, the env-file parsing, the systemd rule and the `/api/v1` compatibility gate — the last two of which no `make` target ran), while `make test` is 4m37s and stays out. If a repo has no `verificar.sh`, it says so and carries on — say it too when you report, because then CI is the only net. `--sin-verificar` skips it and is mine to authorise.
  - **The diff gets reviewed before the PR exists, not after.** Run `/code-review <branch> --fix` over the branch's whole diff, read what it applied, keep what's right, commit it, and then `~/.claude/bin/marcar-revisado.sh <branch>`. The mark is HEAD's SHA, so **any commit after it invalidates the review** and the brake fires again — which is correct: that commit is code nobody read. `--sin-revisar` skips it and is also mine.
  - Both brakes sit before `git push` on purpose. A PR that opens with the reviewer's fixes already inside gets read once; one that grows three "fixing what the review said" commits gets read three times.
- **Only when I say so**, `~/.claude/bin/cerrar-rama.sh <branch>`, from the repo root after `ExitWorktree` with `action: "keep"`. It re-checks green, merges, deploys to production, tears down the branch's stack with its volumes, and removes worktree, local branch and remote branch — in that order, which is the only one that works. **Never `gh pr merge --delete-branch`**: it merges on GitHub and then fails locally when a worktree holds the branch or holds `main`, leaving the branch alive and saying nothing.
- **The production step is conditional — don't announce a deploy that isn't going to happen.** `cerrar-rama.sh` only calls `cmdlo-infra/desplegar.sh` when the repo carries the cmdlo contract: `ops/deploy/deploy.sh` **and** `.github/workflows/release.yml`. Today that is welzy and nothing else; everywhere else it says so and skips the step.
- **A green that predates the current `main` is not a green.** CI tests the *result of merging* the branch with `main` as it was then; if `main` moved afterwards, GitHub keeps showing green for a merge nobody tested. `cerrar-rama.sh` compares when the checks finished against when `origin/<main>` last moved and, if `main` won, merges `main` into the branch and waits for the new run. This only bites with several branches in flight — which is exactly what the worktree flow makes easy.
- Never `git commit`, `git merge` or `git push` while on `main`. A `PreToolUse` hook (`~/.claude/hooks/git-no-main.sh`) blocks all three. In every private repo it is still the *only* enforcement — GitHub branch protection needs Pro or a public repo — so `CLAUDE_ALLOW_MAIN=1` there removes the last barrier there is. **`dotfiles` is the exception since 2026-08-14**: it went public, and `main` now carries server-side protection — a PR is required, `verificar.sh` must pass, the branch must be up to date with `main`, force-pushes and deletion are refused, and **admins are included**, so the hatch no longer buys a direct push there. Undoing it is a deliberate visit to the repo settings, which is the point.
- **There is a second `PreToolUse` hook, and it blocks more verbs**: `~/.claude/hooks/git-una-sesion-por-checkout.sh` refuses `add`, `am`, `apply`, `checkout`, `cherry-pick`, `clean`, `commit`, `merge`, `mv`, `pull`, `rebase`, `reset`, `restore`, `revert`, `rm`, `stash` and `switch` when another live Claude session shares the same git root. Reading (`status`, `diff`, `log`, `worktree`) always passes. The remedy it prints is the worktree, so this only fires when the worktree rule was skipped. Its hatch is `CLAUDE_ALLOW_SHARED_CHECKOUT=1`, and it is mine to authorise too.
- **Neither hook sees inside the branch scripts.** A `PreToolUse` hook only reads the Bash line, so the `git push origin --delete`, `git branch -D` and `git pull --ff-only` that `cerrar-rama.sh` runs internally never reach it. The hooks protect what gets typed by hand; the scripts are trusted because they have a test matrix.
- **Cleaning up after a merge is not "touching main", and the hook lets it through — no hatch needed** *(2026-08-13)*: `git pull --ff-only`, `git push origin --delete <branch>`, `git branch -D <branch>`, `git worktree remove <path>`. Two conditions: the branch must not be `main`/`master`, and **each command runs on its own**, because the hook matches the whole command line — chaining with `&&`, `;` or `||` throws the exception away. A trailing pipe is fine (`| tail -2`) as long as `git` isn't named after it, and so is a **leading** `cd <path> &&`: it doesn't change what git does, and it is how the cleanup gets written from a directory that isn't the repo. That `cd` also decides *which* repo the hook judges — same as `git -C`, which wins when both appear. Asking for the hatch to delete an already-merged branch was spending it on the one thing that doesn't matter, and a hatch requested daily stops being read.
- The hook has an escape hatch, `CLAUDE_ALLOW_MAIN=1`. **Don't reach for it on your own** — if touching `main` directly looks necessary, say why and let me decide. It exists for real writes to `main`, not for the cleanup above.
- **There are three test matrices, one per moving part**: `probar-git-no-main.sh` and `probar-git-una-sesion.sh` next to their hooks, and `probar-ramas.sh` next to the branch scripts. In the dotfiles repo `./verificar.sh` runs all three plus a `/bin/bash -n` over every script, and that is what the push gate calls. Run the one you touched, and prove the tests can fail by reintroducing the bug in a copy. That is how the `--ff-only` hole was found: the old exception matched that substring *anywhere* in the command, so even `git commit -m "fix the --ff-only thing"` sailed straight through.
- **Run the matrix that sits next to the file you edited, not `~/.claude/…`.** All three default to the copy beside them, which in a worktree is the one you just changed; `~/.claude/hooks` and `~/.claude/bin` are symlinks to the repo *root*, i.e. to `main`. Until 2026-08-13 the hook matrix defaulted the other way and reported green for a file it had never read. `HOOK=<path>` still points it at the installed copy when what you want to check is the machine. **The same trap applies to running `probar-rama.sh` itself from a dotfiles branch** — `~/.claude/bin/probar-rama.sh` is `main`'s copy, so use `./claude/bin/probar-rama.sh`; the first run of the two new brakes opened a PR without either of them executing.
- **"No checks" has two causes and they are not the same.** The repo may have no PR CI at all, or it may have CI that this PR doesn't trigger — welzy's `paths-ignore` does exactly that with documentation-only PRs. `cerrar-rama.sh` tells them apart and refuses to merge either way; say which one it was when reporting. As of 2026-08-14 `dotfiles` has CI too — one job running the same `./verificar.sh` the push gate runs, on every PR with no `paths-ignore` — so a branch there now closes on its own like anywhere else.

## Worktrees — named after their branch, with a `wt` prefix

- **A worktree is named `wt<branch>`** — the branch name it holds, prefixed with
  `wt`. Branch `f9-importar-maestros` → worktree `wtf9-importar-maestros`.
  **Never** the random Docker-style name the harness invents
  (`focused-pascal-b3d58d`, `frosty-lamport-0953ed`): with four of those open at
  once there's no way to know which holds what without opening each one.
- **Don't build the name by hand** — `abrir-rama.sh` derives it from the branch,
  and refuses the harness's pattern outright.
- **When the session is *born* inside one of those, move out before touching
  anything** *(2026-08-13)*. It happens often: the app opens the session already
  in `.claude/worktrees/<invented-name>` on branch `claude/<invented-name>` —
  the same directory `abrir-rama.sh` uses, with the one name it rejects, except
  it never gets asked because branch and directory already exist. The recipe,
  in this order and with each git command on its own (the hook lets all three
  through):

      ~/.claude/bin/abrir-rama.sh <name-that-says-what-is-inside>
      EnterWorktree with the path it prints
      git -C <repo> worktree remove .claude/worktrees/<invented-name>
      git -C <repo> branch -D claude/<invented-name>

  Nothing is lost: that branch sits on the same commit as `main` with no work on
  top. What the old instruction said — «rename the branch first» — can't be done:
  renaming leaves the directory with the old name, which is worse than a random
  one, and the directory can't be moved from inside the session that lives in it.
- **Don't leave worktrees behind.** `cerrar-rama.sh` removes the worktree in the
  same breath as deleting the branch, and that is the point of it existing. The
  default state of a repo is **one worktree on `main`**, at the repo root.
- `main` belongs at the repo root, not in a scratch worktree. If `main` is
  checked out somewhere else, `gh pr merge` and `git checkout main` fail at the
  root with `'main' is already used by worktree at ...`.

## Git commits

- **Never add a `Co-Authored-By: Claude ...` (or any Claude/Anthropic co-author) trailer to commit messages.** Write the commit body and stop. This overrides the default commit-message template.

## Planning

- **Whenever we plan or design anything (in any project), interview me first** using the `grill-me` skill approach before settling on a plan. Ask questions **one at a time** via the AskUserQuestion tool: present your recommended answer first with a brief justification, then 2-4 concrete alternatives. Walk every branch of the decision tree, track decisions, and flag/revisit conflicts when a later answer invalidates an earlier one. Prefer exploring the codebase over asking when the answer is discoverable there.
