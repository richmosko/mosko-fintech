---
name: catalog-comments-carry-live-state-tallies
description: On any migration that re-issues a `comment on`, grep the RENDERED comment for ledger tallies — a preserved span re-asserts stale counts as live state, even when the containment proof is perfect
metadata:
  type: feedback
---

When a migration re-issues a `comment on`, verify the **rendered** comment text separately from the
change region. A byte-perfect containment proof says nothing about whether the *preserved* span is still
true — and a catalog comment reads as **live state**, not as dated provenance.

**Why:** at the SELF-217 / migration `068` review, the regenerate-and-diff containment claim was correct
(I independently measured one contiguous replaced region), but the untouched suffix carried
`Decision-3 family stays 15 labeled / 12 DDL-realized` — true when `054` shipped, stale by the time `068`
re-issued it. Worse, `068`'s header recorded the correct live figure as dated provenance and asserted it
was *"NOT restated in the comment below"*, which the comment falsified. `067`'s header states the rule
this violates: *a ledger-impact claim belongs in a migration header, which is a dated artifact, not in a
catalog comment, which reads as LIVE STATE.*

**How to apply:** render the comment (unescape `''`, join the string concatenation) and grep it for
tally-shaped phrases — `stays N`, `N labeled`, `allowlist`, `ledger`, `family`. Do this **in addition
to** the containment check, never instead of it. Preferred remediation is **removal of the tally, not
correction of it** — correcting re-arms the identical trap at the next ledger move on a surface with no
watcher; the derive-by-looking test says a derived surface carries no tally. The containment proof
supports two replaced regions as easily as one, so removal costs nothing methodologically.

**The remediation that worked** (`b728ad6`, same review): strike the tally **and leave a named guard in
its place** — the replacement text says a count copied into a catalog comment is a maintenance
obligation the copy will not honour, and points at the canonical anchors. Removal alone leaves the next
author free to re-add one; naming the drift class is what survives a sweep (ADR-011 D4's CHANGELOG makes
exactly this ASSERTS-vs-NAMES distinction). Ask for the guard, not just the deletion. Also: when the
struck text sits near the end, a longest-common-prefix/suffix measurement collapses everything between
the two edits into one false "region" — use a real opcode diff and cluster the micro-regions.

**Extends past `comment on` to any COMPOSITION MANIFEST in a test-file header.** A seam-only battery
that composes sibling batteries lists them with their plan counts (`049 (plan 33) · 051 (plan 34) …`)
alongside the §10 and DEFINER-allowlist tallies. Same class, same fix — and it is cheap to falsify:
`grep -n "select plan(" <each cited file>` and compare. On `self228_v1_1_close_gate.sql` (PR #464) five
of six matched and one read `plan 43+` against an actual `plan(40)`; the ledger tallies in the same
comment block happened to be accurate, which is exactly how a tally-carrying surface reads safe right up
until it isn't. Prefer dropping the counts (derive-by-looking) over correcting them.

Related: [[measure-the-fence-regex-not-its-comment]] (a description claiming a property the artifact
lacks) and [[sec-lock-cross-check-catches-my-own-misreads]].
