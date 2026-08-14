<!-- Keep this file under 80 lines. Detail belongs in .claude/rules/ or docs/. -->

# {{PROJECT_NAME}}

{{ONE_LINE_PURPOSE}}

## Commands

| Command | What it does |
|---|---|
| `./verificar.sh` | format + lint + typecheck + test (`{{VERIFY_CMD}}`). Must pass, with its output shown, before any work is called done — and before any push. |
| `{{DEV_CMD}}` | run locally |
| `{{TEST_ONE_CMD}}` | run a single test file |

## Stack

{{STACK}}

## Layout

{{LAYOUT}}

## Branches and pull requests

- **Nothing lands on `main` directly.** Start every change with
  `git checkout -b <name-that-says-what-is-inside>`.
- **Merge through a pull request** (`gh pr create`). The PR is where CI runs, and
  a change CI hasn't judged doesn't get merged. Merge from the PR once it's green,
  then delete the branch locally and on the remote.
- **Before the push, in this order: `./verificar.sh`, then the review.** Green
  first, because reviewing code that fails the lint spends the review twice. Then
  `/code-review <branch> --fix` — or the `code-reviewer` subagent — over the
  branch's whole diff, apply what's right, and commit it. The PR opens with the
  review's fixes already inside; one that grows three "fixing what the review
  said" commits has to be read three times.
- A `PreToolUse` hook blocks `commit`, `merge` and `push` while on `main`. It is
  the actual enforcement: GitHub branch protection needs a paid plan or a public
  repo. Its escape hatch, `CLAUDE_ALLOW_MAIN=1`, is mine to authorise, not yours.

## Workflow

- Plan first. Present the plan and wait for my approval before writing code.
- For anything non-trivial, interview me one question at a time — your recommendation first with a short justification, then 2-4 alternatives — and write the agreed spec to `docs/specs/<name>.md` before implementing. Small, unambiguous fixes skip this.
- Never report work as done without running `./verificar.sh` and pasting its output. Don't assert that checks passed.
- Before calling a feature finished, have the `code-reviewer` subagent review the diff in a fresh context, then fix what it finds. Use `/code-review` for large or risky changes.
- Don't widen scope. Name adjacent problems you spot; don't fix them unasked.
- Match the surrounding code's style over any general preference.

## Working agreement

- `/clear` between unrelated tasks.
- If I've corrected the same thing twice, stop and `/clear` rather than correcting a third time. A fresh session with a better prompt beats a long one full of failed attempts.
- Start long implementations in a fresh session against the written spec.
- Add a skill only once I've typed the same instructions twice. Add a hook only for what must happen every single time.

## Compact instructions

When compacting, preserve: the list of modified files, the most recent `./verificar.sh` output, and any decision recorded in `docs/DECISIONS.md` this session.

## Gotchas

{{GOTCHAS}}
