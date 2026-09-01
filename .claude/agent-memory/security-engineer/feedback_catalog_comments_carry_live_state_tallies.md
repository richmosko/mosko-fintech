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

**⚠ A CORRECTION'S OWN SWEEP CLAIM IS A CLAIM ABOUT THE GREP'S ENCODING, NOT ABOUT THE TREE — and the
HTML doc artifacts are where that bites.** ADR-011 D19 Amendment Edit 1 corrected the as-of predicate to
a half-open bound and closed with a Sweep asserting the defective form *"appears in no migration, no
application source and no other document."* The sweep pattern was `grep -rn 'created_at <= \$1'`, which
**cannot match `created_at &lt;= $1`** — so three ratified sites survived it: `docs/SECURITY/index.html`
(the RT-25 catalog row's own acceptance text, plus the SD-00 storage row) and `docs/ARCH/index.html`'s
Lock-15 trade-off entry. Found at the SELF-253 review, ~6 days later, on the surface that is the
predicate's FIRST LIVE INSTANCE. The confirming negative: `git grep 'created_at &lt; ('` over `docs/`
returned **nothing** — no doc anywhere carried the corrected form.

**Why it matters more than ordinary doc drift:** the stale copy sat in the RT catalog's *acceptance
criteria*, which is what QA authors a battery FROM. D19 Edit 1 itself records that no value assertion
catches this defect — so a battery written from the catalog would have asserted the wrong bound and gone
green over the bug. A stale predicate in an RT row is a stale TEST SPEC, not a stale comment.

**How to apply:** any sweep over `docs/**` must run the pattern in BOTH encodings — raw and
HTML-entity (`<` / `&lt;`, `>` / `&gt;`, `&` / `&amp;`) — because `docs/PRD`, `docs/ARCH` and
`docs/SECURITY` are HTML and every comparison operator in them is escaped. Then run the **positive**
grep for the CORRECTED form and confirm it appears where you expect; a sweep that only greps the old
string cannot distinguish "fixed everywhere" from "never present in a form I could see." Same family as
[[my-review-measurements-become-quoted-sources]]'s case-twin lesson: grep both spellings, not one.

**⚠ A NEW ENDPOINT COPIES THE PREVIOUS ENDPOINT'S HEADER, so a superseded ledger description travels
into files that have nothing to do with the ledger.** At the SELF-252 review, `+server.ts`'s header read
*"RT-26's 3-surface allowlist (webhook / exchange / remove) is untouched by this endpoint"* — inherited
byte-identical from `planning-target/+server.ts`. Measured: `scripts/ci/rt26-allowlist.txt` holds ONE
non-comment entry (`api/src/lib/server/supabase-admin.ts`); ADR-016 Decision 4 pruned entries 1–3 as
fail-open standing pre-authorizations. **The operative clause was TRUE and only the parenthetical
description was false**, which is why it reads safe: the sentence's own claim verifies, so a reviewer
checking the claim never checks the noun phrase it hangs on. **How to apply:** on any endpoint whose
header cites a fence, registry, or allowlist by SHAPE, `grep -v '^\s*#'` the registry file itself in the
same turn — and expect the sibling endpoint on `main` to carry the identical sentence (fix the branch
instance as a condition; route the landed one separately, never sweep it inside a feature PR).

⚠ **AUTHORED ≠ SERVED: a `DROP FUNCTION` destroys the earlier `comment on`, so "N migrations carry the
text" and "N live catalog comments" are DIFFERENT POPULATIONS.** SELF-344/ADR-065: three migrations
(`071`/`072`/`073`) carry `comment on function` text stating the NAV month-anchor rule, but `072` does
`drop function if exists` + `create function` — and `DROP` takes the comment with it — so `071`'s text
never reaches the catalog a reader queries. **Two live, three authored, both true, and reconciling them
would delete a real distinction.** Second instance of the two-scoped-figures shape after §10-catalogued
vs CI-fenced. **How to apply: when counting where a rule "lives," ask whether any migration in the chain
DROPPED the object — `create or replace` PRESERVES comments, `DROP`+`CREATE` does not.** State both
figures with their scopes rather than picking one; a point-in-time figure scoped "before this migration"
belongs in an ADR and needs no watcher.
