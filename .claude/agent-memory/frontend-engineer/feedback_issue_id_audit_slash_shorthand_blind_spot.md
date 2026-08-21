---
name: issue-id-audit-slash-shorthand-blind-spot
description: A bare `self-[0-9]+` grep for a pre-push issue-ID audit misses slash-shorthand lists like "SELF-239/241/330" — only the first ID carries the prefix.
metadata:
  type: feedback
---

Before reporting a pre-push Linear-ID audit as complete, grep with
`self-[0-9]+(/[0-9]+)*` (or equivalent), not a bare `self-[0-9]+`. A prose
shorthand like "prior work (SELF-239/241/330)" only attaches the `self-`
prefix to the first number — a naive pattern silently drops every ID after
the first slash.

**Why:** Caught live on SELF-243's pre-push audit (2026-08-20): a bare
`self-[0-9]+` grep across six commit messages reported SELF-330 (5×) and
SELF-239 (1×) but missed SELF-241 entirely — it only existed inside a
"SELF-239/241/330" shorthand in one commit body. Team-lead's whole point of
the audit is to catch a live (not-yet-Done) issue ID that would silently
auto-close on merge; an undercounted audit reports false confidence on
exactly the thing it exists to catch.

**How to apply:** Any time an audit's job is "find every issue-ID reference"
(pre-push ID audits, PR-body ID sweeps, doc-reference sweeps), run the
shorthand-aware pattern first, not as a fallback. If a first pass already
ran with the naive pattern, re-run before reporting — don't report a count
that was produced by a pattern known to have this blind spot. Related
discipline: [[feedback_relay_from_the_tree_not_the_report]]-style — verify
the sweep itself, not just its output, the same way a scope-less count needs
re-checking (mosko's own user-memory: "state what the count is over").
