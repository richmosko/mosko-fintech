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

**⚠ A COUNT FANS OUT — fix the site you found and you have fixed one of three.** In `docs/SECURITY`
the SD-matrix total lives in **three** places: the table-of-contents entry, the `section-hint`, and
the body paragraph under it. I corrected the hint, reported done, and team-lead's grep found the other
two. I had flagged fan-out as the copying-not-reasoning tell in a CHANGELOG bullet **in the same
session**, then missed it in my own artifact. **Never fix a count at the site where you noticed it —
sweep the file with a negative grep for the OLD string and confirm zero hits.**

**Two supports that make a count fix defensible rather than a preference:**
1. **Derive the number from the file's OWN convention, and say so.** §4.5's parallel hint reads
   *"31 entries (RT-01 – RT-31; RT-07 reserved-vacant; 30 active)"* against a measured 31 rows — so
   the convention is *total = full label range including vacant*, and active + vacant = total. That
   makes SD 23 + 2 = 25, and shows the old "24 (22 active + 2 vacant)" against a 25-label range failed
   the file's own arithmetic. A sibling catalog is the cheapest convention oracle available.
2. **⚠ Do NOT sweep SCOPED HISTORICAL deltas with the totals.** *"+9 entries lock-added across the
   drilling cycle 2026-05-25 → 2026-05-26"* describes what happened on a date; it is not stale and a
   consistency sweep would destroy it. D4's CHANGELOG header records the forward version of this (*a
   scoped count cannot characterize an unscoped collection*); the converse is the one that bites a
   sweeper. Name these sites explicitly as **deliberately not touched**, and if one doesn't reconcile,
   say you did not verify it rather than fixing it inside an unrelated correction.

**⚠ FAN-OUT IS NOT ONLY FOR COUNTS — a CLASSIFICATION CLAIM fans out the same way, and the review
brief will enumerate fewer files than the claim lives in.** At the SELF-332 / ADR-061 review the brief
named two source files; the claim *"this render gate is LOAD-BEARING, not belt-and-suspenders"* lived in
**three** — the mirror lib header, its two JSDoc blocks, **and the consuming component's header**
(`UsEquityAllocationTable.svelte`), which was absent from the diffstat entirely. The commit that
retired the classification was literally titled *"finish the … reclassification"* and had not. The
stale copy still pointed the reader at the corrected file *"for why this gate is LOAD-BEARING"* — a
cross-reference that now resolves to the opposite statement, which is strictly worse than the original
divergence because it makes a safe removal look forbidden.

**How to apply:** when a change RETIRES a stated property of a control (load-bearing → redundant,
required → optional, fenced → unfenced), do not review the enumerated files — `git grep` the distinctive
phrase across the whole tree **including files not in the diff**, then follow every inbound
cross-reference *to* the corrected file and check what it says the reader will find there. Do not
inherit the brief's file list; a brief's scope is a hypothesis about where the claim lives. Verify the
claim was RETRACTED everywhere, not just RESTATED correctly once. This is the same shape as
[[hazard-mechanism-vs-reachability]]'s "a retraction fans out past the corrected file."

Related: [[measure-the-fence-regex-not-its-comment]] (a description claiming a property the artifact
lacks) and [[sec-lock-cross-check-catches-my-own-misreads]].
