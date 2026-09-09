---
name: a-quotation-that-rejoins-wrapped-lines-is-an-unmarked-elision
description: Quoting a source that wraps across comment lines silently strips the newline and its `#`/`--` prefix — the same class as dropping a word. Verify a quote by rejoining, and mark the rejoin.
metadata:
  type: feedback
---

**A quotation that NORMALISES its source is an unmarked elision, whether it drops
words or joins lines.** Both make the quote unfindable in the file it claims to
come from, and both survive every eyeball check.

**Why:** measured 2026-09-09 on `workers/provider-sync/.env.example`. Sec's
ADR-019 review F3 correctly caught `116`'s header quoting a parenthetical with a
clause dropped — but **Sec's own commit-ready replacement was not byte-exact
either**, because the source wraps that parenthetical across two `#` comment
lines. The corrected string occurs **0** times contiguously in the file and once
only after rejoining. Pasting the fix as given would have swapped one silent
normalisation for another, one level down. And I had **re-armed the identical
defect myself** in the same branch two commits earlier — the pull toward an
inline quote is strong precisely where the source is a wrapped comment.

**How to apply:**

1. **Verify a quote by rejoining, not by reading.** Never `grep` the quoted
   string raw and conclude from a zero hit; normalise first, then count both
   forms:

       python3 -c "import re,io;s=io.open(P).read();j=re.sub(r'\n#\s*',' ',s);print(s.count(Q),j.count(Q))"

   (`\n--\s*` for SQL headers, `\n#\s*` for shell/env files.)
2. **The zero-after-rejoin count is the real test.** If the *old* form is absent
   even after rejoining, the elision was genuine and not a wrap artifact — that
   converts a reviewer's reading into a measurement, in either direction.
3. **Prefer DESCRIBING a wrapped source to quoting it.** *"its DB-login-role pin,
   whose parenthetical names Sec conditions C1/C3"* carries the same information
   and cannot be wrong. Quote whole **and mark the rejoin** only where the exact
   words are load-bearing.
4. **Keep the wrong form exactly once, as a dated record of what it read** — that
   is a report of a bad quotation, not a fresh one ([[feedback_sound_quote_false_gloss_drift]]).

Related: [[feedback_brief_drift_catch_verbatim_source_cross_check]],
[[feedback_verifying_a_measurement_is_not_verifying_a_claim]],
[[feedback_rule_and_example_share_the_authors_frame]].
