---
paths:
  - "src/**"
  - "app/**"
  - "lib/**"
  - "backend/**"
  - "frontend/**"
---

# Code style

Written for a codebase that has to be navigated without reading all of it.

## Structure

- Package by feature, not by layer. Everything one feature needs lives in one folder.
- One exported concern per file. The filename says what it is.
- ~300 lines is the signal to split a file, not a rule to obey blindly.
- No barrel or index re-export files that hide where code actually lives.

## Naming

- Say the thing. `accountBalanceInEur`, not `bal`. No abbreviations outside loop counters.
- A name that reads as a sentence at the call site beats a short one.

## Boundaries

- Explicit types on every public function, API handler and persistence row. Infer freely inside a function body.
- No implicit setup: nothing mutates global state at import time, no side effects on import.
- Push IO to the edges. Business logic takes data and returns data.

## Errors

- Fail loudly, with the context needed to debug: what was attempted, with what input.
- Never swallow an error to keep a signature tidy.

## Hygiene

- No dead code and no commented-out code. Git remembers.
- No `TODO` without a linked issue.
- Comments explain *why*. If a comment explains *what*, rename things instead.
