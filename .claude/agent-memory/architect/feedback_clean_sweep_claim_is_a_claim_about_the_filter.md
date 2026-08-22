---
name: clean-sweep-claim-is-a-claim-about-the-filter
description: Never report "no occurrences remain" from a targeted grep — over-match case-insensitively and hand-filter, because the pattern you chose is the thing most likely to be wrong.
metadata:
  type: feedback
---

**A "clean sweep" result is a claim about your PATTERN, not about the tree.** Before reporting *"no X remains"*, re-run **over-matched and case-insensitive**, then hand-filter the hits. Report the filtered hits and why each is benign — never just the empty result.

**Why:** 2026-08-18, finalizing the GL-split ADR draft, I swept for open markers with a case-sensitive pattern hunting `F/CTO-PENDING` and reported *"no unfilled slot and no PROPOSED-pending marker remains."* Team-lead found a survivor by grepping bare `pending` case-insensitively and hand-filtering: a lowercase `F/CTO-pending` **inside the conditions-integration summary line** — six correct entries around it, so it read as verified by adjacency.

⚠ **It was the SECOND case-sensitivity miss in the same session.** The first was a lower-case `US equity` in the PRD that moved a rename-target count from 11 to 12 — I caught that one, wrote about it, and then committed the same class an hour later on my own text. **Catching a failure mode does not inoculate you against it; only changing the procedure does.**

⚠ **And it is the exact failure ADR-011 Decision 4's CHANGELOG already names — text I had quoted into that very draft:** *"A filtered grep is a claim about the filter, not about the tree."* Its own instance was found *"by grepping the bare label across branch-authored text rather than by visiting the sites the reviewer had enumerated — the reviewer's own filtered grep had missed the fourth."*

**How to apply:**
- Sweeping for stale markers, counts, or labels: **bare stem, `grep -in`, then read every hit.** Not the full phrase, not case-sensitive.
- **Expect benign hits and say so** — on the re-sweep above, five hits were all legitimate (claims of *absence*; a deliberate `Status: Proposed`; the seed-row NAME `EstTax-Pending` from `041`, which must never be swept; and a substring of *"F/CTO disposed"*). A sweep returning zero is more suspicious than one returning explained hits.
- ⚠ **The adjacent-reads-as-fixed position is where survivors live** — inside a summary line or list whose other entries are correct. Check those positions by hand even when the grep is clean.
- Same discipline as [[state-what-the-count-is-over]] and [[prove-derived-text-against-its-source]]: the instrument's scope is part of the claim.

Related: [[feedback_count_over_history_vs_live_definitions]] (its sibling: *case-insensitive grep, or `059` reads as empty*) · [[feedback_diff_filter_strips_comment_lines]]


---

**⚠ THE VARIANT THAT ACTUALLY BIT: OVER-MATCH FIRST, THEN NARROW WHEN WRITING IT UP.**

Measured 2026-08-21 (SELF-325). I swept for committed citations of a `temp/` design doc, over-
matched correctly, and **saw all of them**. Then, drafting the per-site table for a teammate, I
re-grepped with a tighter pattern (`temp/architect` + `the addendum`) and built the table from
*that*. A wrapped citation whose visible line carried only `architect-purchase-path-addendum.md`
matched neither term. **I told the teammate there were 10. There were 12.**

**The wide sweep had already caught them.** The loss happened at write-up, not at discovery —
which is why re-running the sweep would not have found it either: the sweep was fine.

**Rules that fall out:**
- **Build the deliverable FROM the wide output.** Never re-grep narrower to "clean up" a list;
  filter the wide result by hand instead. The narrowing step is invisible in the artifact.
- ⚠ **A handed-over list is received as a claim about the FILE, not about your filter.** A
  teammate executing your table has no way to see the pattern behind it. Say what the sweep was
  and invite re-derivation.
- **Verify the PROPERTY, not the WORKLIST.** *"No dangling citations remain"* (re-grep the files
  afterwards, over-matched) is the check worth making. *"Every tabulated item was handled"* is
  a claim about the table and is worth nothing if the table was short. The teammate here did the
  first and that is what closed it.

Related: [[feedback_failed_grep_looks_like_a_clean_result]] ·
[[feedback_state_what_the_count_is_over]]


---

**⚠ THE FORM THAT BIT TWICE IN ONE ARC: A GREP COUNT HANDED OVER AS A PER-SITE CLASSIFICATION.**

Both instances were mine, SELF-325, and a teammate caught each by reading the sites instead of
executing my list.

1. *"10 `temp/` citations across 4 files"* — there were **12**. A wrapped citation matched
   neither of my two patterns.
2. *"5 branch-locator sites to swap"* — **one** was a locator. The other four named the commit
   for **what it did** (*"8fa6526 superseded…"*, *"(8fa6526 corrected it)"*), not for where the
   branch stood. **A blanket swap would have turned four true sentences false.**

⚠ **The second is worse than the first because of where it sat: I wrote the don't-flatten rule
for the provenance sites IN THE SAME MESSAGE that handed over an unread bucket of five.** I said
*"eight matches, three dispositions, none flattened"* having classified three of the eight.
**Articulating the discipline is not applying it, and doing both in one breath feels identical
to doing it right.**

**The rule: `grep -c` answers "how many lines match." It does NOT answer "how many are the
thing I mean." A token can appear in at least three roles — a live pointer, a historical
statement about what a commit DID, and a dated provenance record — and only the first is ever
safe to rewrite.**

**How to apply:**
- **Never hand a teammate a COUNT as if it were a CLASSIFICATION.** If you have not read each
  site, say *"N matches, unclassified — read each before acting."* That costs one clause and
  transfers the check honestly.
- **Read every match in full sentence context before proposing any rewrite.** The tell is the
  verb: a site that says a sha *did* something is history; a site that says a state *is*
  something is a pointer.
- ⚠ **Expect the teammate to be right when they push back on your count.** Twice, from two
  different people, on one branch.

Related: [[feedback_state_what_the_count_is_over]] ·
[[feedback_failed_grep_looks_like_a_clean_result]]
