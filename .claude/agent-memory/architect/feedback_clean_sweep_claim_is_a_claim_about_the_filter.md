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
