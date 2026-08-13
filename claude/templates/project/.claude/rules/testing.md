---
paths:
  - "**/*.test.ts"
  - "**/*.test.tsx"
  - "**/*.spec.ts"
  - "**/*.spec.tsx"
  - "**/*Test.kt"
  - "**/*Tests.kt"
  - "**/test_*.py"
  - "**/*_test.py"
  - "**/*_test.go"
  - "tests/**"
  - "test/**"
---

# Testing

- Colocate tests with the code they test.
- Test the public API, not internals. A refactor that preserves behaviour must not break a test.
- One behaviour per test. The test name is the expected behaviour, written as a sentence.
- Fixing a bug starts with a failing test that reproduces it.
- Deterministic only: no real clock, no real network, no sleeps. Inject time and IO.
- Don't mock what you don't own. Wrap it in a thin adapter and mock the adapter.
- A test that needs a comment to explain what it asserts is testing too much.
