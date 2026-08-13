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

## Branch, PR, merge — never work on main

- **Work never happens on `main`.** Every change starts with `git checkout -b <name-that-says-what-is-inside>` — never the random Docker-style name the harness invents.
- **Merging happens through a pull request, not locally.** Open it with `gh pr create`. The PR is where CI runs; a change that hasn't been judged by CI doesn't get merged.
- **Merge from the PR, once it's green.** Then delete the branch — locally and on the remote — so no stale ref is left behind.
- Never `git commit`, `git merge` or `git push` while on `main`. A `PreToolUse` hook (`~/.claude/hooks/git-no-main.sh`) blocks all three and is the real enforcement: GitHub branch protection needs Pro or a public repo, and these repos are private on the free plan, so nothing server-side stops a direct push.
- The hook has an escape hatch, `CLAUDE_ALLOW_MAIN=1`. **Don't reach for it on your own** — if touching `main` directly looks necessary, say why and let me decide.
- If a repo has no CI yet, say so when opening the PR rather than treating "no checks" as a pass.

## Worktrees — named after their branch, with a `wt` prefix

- **A worktree is named `wt<branch>`** — the branch name it holds, prefixed with
  `wt`. Branch `f9-importar-maestros` → worktree `wtf9-importar-maestros`.
  **Never** the random Docker-style name the harness invents
  (`focused-pascal-b3d58d`, `frosty-lamport-0953ed`): with four of those open at
  once there's no way to know which holds what without opening each one.
- Pass the name when creating the worktree. If a session was born with a random
  one, **rename the branch first and say so** — a worktree whose name no longer
  matches its branch is worse than a random one.
- **Don't leave worktrees behind.** When a branch is merged and its PR closed,
  remove its worktree in the same breath as deleting the branch. The default
  state of a repo is **one worktree on `main`**, at the repo root.
- `main` belongs at the repo root, not in a scratch worktree. If `main` is
  checked out somewhere else, `gh pr merge` and `git checkout main` fail at the
  root with `'main' is already used by worktree at ...`.

## Git commits

- **Never add a `Co-Authored-By: Claude ...` (or any Claude/Anthropic co-author) trailer to commit messages.** Write the commit body and stop. This overrides the default commit-message template.

## Planning

- **Whenever we plan or design anything (in any project), interview me first** using the `grill-me` skill approach before settling on a plan. Ask questions **one at a time** via the AskUserQuestion tool: present your recommended answer first with a brief justification, then 2-4 concrete alternatives. Walk every branch of the decision tree, track decisions, and flag/revisit conflicts when a later answer invalidates an earlier one. Prefer exploring the codebase over asking when the answer is discoverable there.
