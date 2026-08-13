---
name: feedback-run-ruff-before-python-handoff
description: A passing pytest suite says nothing about lint — the commit-hook's ruff check rejected a Python test file over an unused import that 28/28 green tests never touched. In the QA-authors/architect-commits handoff shape, a lint failure is invisible to QA until it bounces back from the committer. Run `ruff check` before every Python handoff, not just pytest.
metadata:
  type: feedback
---

Handed off a Python integration-test file to architect (holder) after getting
28/28 passing. Architect's commit was rejected by the repo's pre-commit hook:
`ruff check` flagged an unused `import sqlalchemy as sqla` — a leftover from
an earlier draft that called SQLAlchemy directly before the file was rewritten
to shell out via `subprocess`/`psql` instead. Pytest never touched that line,
so a fully green test run gave zero signal about it.

**Why this recurs structurally, not just as one mistake:** in the
QA-authors/architect-commits handoff shape, I never run `git commit` myself —
the pre-commit hook that would have caught this never runs in MY session at
all. The only place this class of failure surfaces is a bounce back from
whoever holds the branch, one full round trip after I believed the work was
done. Architect's framing: "you cannot discover this class of failure,
because you never commit."

**How to apply:** for every Python file handed to a non-authoring holder for
commit, run `ruff check <path>` (or `ruff check tests/` for the whole
directory, matching what the commit hook actually scopes to) BEFORE sending
the handoff — not just the test suite. `uv run ruff check <paths>` costs a
few seconds and closes the whole class: pytest and ruff observe different
properties of the same file (behavior vs. style/dead-code), and a suite
passing says nothing about the other axis. Same discipline as running the
test suite itself before claiming it's ready — an unrun check is not a
green check. [[feedback_full_text_not_path_pointer_to_non_authoring_role]]
covers the delivery-channel half of this same handoff shape; this is the
verification half.
