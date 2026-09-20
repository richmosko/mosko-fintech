---
name: a-described-control-is-not-a-built-one
description: A BACKLOG AC, an ADR paragraph, or MY OWN REVIEW BRIEF describing a fence, a REVOKE, or a watcher reads exactly like the thing existing. Grep the tree for the artifact, not the prose — especially in the PR that lands the behaviour the control is meant to guard.
metadata:
  type: feedback
---

**Grep for the ARTIFACT, never for the paragraph that describes it — and do it hardest in the PR that lands the
behaviour, because that is the PR where the control is most likely to be described instead of built.**

**Why:** the G3 sweep PR applied a `set role` / `reset role` convention across **114 migration files** and its
BACKLOG AC described the CI fence *correctly*, folding in my own comment-stripping and exact-count conditions —
so reading the AC felt like reading a merged fence. Measured: **zero files under `scripts/ci/`, zero workflow
changes.** The same PR's AC named the engine backstop `revoke create on schema pfin from migrator;`, which was
**executed nowhere**, and its battery carried no `has_schema_privilege(...,'CREATE')` leg. Three controls I had
conditioned on, all present as prose and absent as code, in the one PR that made them load-bearing.

**How to apply:**
- Two greps, always: `git diff --name-only <base> <head> | grep -E 'scripts/ci|\.github/workflows'` for the
  fence, and a comment-stripped grep for the literal statement (`revoke ...`, the assertion) in the migration or
  test diff. **Prose hits and code hits must be counted separately** — see
  [[prosrc-presence-checks-are-vacuous-because-the-comments-are-good]].
- **A well-written AC is the risk, not the mitigation.** The better the description, the more it substitutes for
  the artifact in a reviewer's memory. Treat an AC that folds your own conditions back at you as a prompt to
  measure, not as evidence they were met.
- State the finding as *"described, not built"* with the measurement, and keep it separate from a design
  objection — the fix is a commit, not a re-litigation, and saying so keeps it cheap.
- Related: [[assertion-with-no-watcher]], [[which-lane-does-the-watcher-observe]].
- ⚠ **The TASK BRIEF is itself a claim about the tree, and it is the carrier I am least likely to check.** PR #828 (2026-09-19) briefed me to grade that `db-shell.sh` *"re-validates it against a uuid regex before interpolating it into a remote command (the F4 class from #825)"*. Measured at `fb1fb7f4`: no regex, no guard, non-empty check only — the control named in the brief did not exist, and the brief's confident, specific, correctly-cited phrasing (right class, right prior PR, right sibling convention) is exactly what made it credible. An AC I read with suspicion; a brief I read as the definition of scope. **Grade every control the brief ASSERTS as present with the same grep I'd give one it asks me to add** — a brief that describes a control is handing me a finding, not a premise.
