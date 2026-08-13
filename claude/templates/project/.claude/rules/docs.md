---
paths:
  - "docs/**"
  - "*.md"
  - "CLAUDE.md"
---

# Documentation

- `CLAUDE.md` stays under 80 lines. Anything that doesn't need to be in context every session belongs in a rule under `.claude/rules/` or in `docs/`.
- `docs/ARCHITECTURE.md`: the modules, what each one owns, how data flows between them. Update it in the same change that alters the structure.
- `docs/DECISIONS.md`: append-only. One entry per non-obvious choice — Date, Context, Decision, Consequences. Never edit or delete a past entry; supersede it with a new one.
- `docs/specs/`: the approved spec for each non-trivial piece of work, written before implementation starts.
- Don't document what the code already says. Document why it is this way.
- Personal settings that shouldn't be committed go in `.claude/settings.local.json`, which is gitignored.
