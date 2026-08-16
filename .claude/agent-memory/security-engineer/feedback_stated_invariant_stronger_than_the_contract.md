---
name: stated-invariant-stronger-than-the-contract
description: A doc/comment that states a one-way contract as a biconditional ("NULL together", "exactly where") points a future corrector at the wrong column — check every stated invariant against the guard clauses in the same file.
metadata:
  type: feedback
---

When a surface documents a derived column, read every stated invariant about it against
the file's OWN guard clauses. The recurring defect is an invariant written **stronger than
the contract**: the contract is a one-way implication (`dollar NULL ⇒ percent NULL`) and
the prose renders it as a biconditional — *"NULL together on every row"*, *"NULL **exactly
where** X is NULL"*, *"neither can appear without the other"*.

**Why:** caught on `072_fn_nav_delta_panel_real_percent.sql` (2026-08-14). The CONTRACT
block was correct; the QA-pairing block twelve lines later and the **live catalog comment**
both overstated it to a biconditional — while the same file's own item 14 and the battery's
`(REALBASE0)` / `(NEG1P)` legs mandate the opposite (dollar present, percent NULL on a
non-positive base). The damage is not untidiness: the false invariant **names the wrong
column as the one to change.** Widening the test to match it REDs a correct function;
"fixing" the function to match it NULLs a sound financial figure. It also survives review
because each half reads fine in isolation and the two halves are never read together.

**⚠ The miss I made on this exact defect — the general case, not a slip.** I cleared a third
site as *"correct (one-way)"* because I read the gloss AFTER the colon and stopped. The
sentence was `It rides the dollar column exactly: NULL on every row where X is NULL, so no
row can carry a percent without…` — post-colon is genuinely one-way and genuinely correct,
so the sentence **defines itself correctly and reads as sound.** But the pre-colon summary
phrase is what a reader carries away, it was falsified by the adjacent line, and **a
colon-gloss does not repair a false headline** — it just means the two halves disagree and
the shorter half wins in recall. Architect caught it. **Apply the predicate to the SUMMARY
SPAN, not only to the defining span**; the qualifier is where the falsifiable content lives.

**How to apply:**
- Grep the surface for biconditional vocabulary — `exactly where`, `NULL together`,
  `neither ... without`, `if and only if` — then find the guard that breaks it. There is
  usually one, in the same file, within 20 lines.
- **A teammate's sweep bound phrased as a list of known phrasings is the weak form** — it
  can only find defects already worded like the ones already found. Re-derive it with a
  concept-level predicate (`exactly|only when|iff|both null|neither|precisely|coextens|
  mirrors|in lockstep|tracks|rides|whenever|always null|identical`) and hand-filter the
  unrelated senses. Same lesson as [[measure-the-fence-regex-not-its-comment]].
- **Prefer a same-character-count replacement** in wrapped fixed-width `--` blocks
  (`exactly` → `ONE-WAY` is 7-for-7): the diff becomes one token on one line and cannot
  disturb the wrap. Check where the phrase wraps before proposing wording.
- **Say which correct-looking sites must NOT be swept**, in writing. A correctly-scoped
  invariant (`across A's full five-row panel`) sitting beside two fixed ones is the next
  thing a tidier removes.
- Check the **catalog comment separately from the header.** The comment is a live DB object;
  the header is a file. They drift independently and the comment is the one consumers read.
- **Severity turns on vehicle cost, not on runtime effect.** Zero runtime effect, but in an
  applied-history file (`NNN IS LEFT UNEDITED — it is applied history`) the fix is one word
  pre-merge and a whole comment-amendment migration post-merge (the `068` precedent). That
  inversion is what makes it AMBER-with-a-blocking-condition rather than a recorded note.
  Same reasoning as [[block-when-the-vehicle-cost-inverts]].
- Supply commit-ready replacement text; Architect holds the pen on migrations.
