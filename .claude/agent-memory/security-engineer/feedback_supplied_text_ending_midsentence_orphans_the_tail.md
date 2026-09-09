---
name: supplied-text-ending-midsentence-orphans-the-tail
description: Commit-ready replacement text that ends mid-sentence orphans the target's surviving trailing clause — and when that tail is a CONTROL, applying my block literally DELETES a fence. Name the splice boundary on BOTH sides; state whether a fix's scope should EXPAND; never carry a formatting marker into a file where that marker is a reserved register.
metadata:
  type: feedback
---

**When supplying commit-ready replacement text for another agent to commit verbatim, name the
splice boundary on BOTH sides — what my block replaces AND what of the original survives after it,
with where that survivor reattaches. A replacement that ends mid-sentence orphans the target's
trailing clause onto my final sentence, and the resulting misparse is MY defect, not the
committer's.**

**Why:** worked instance, SELF-263 / ADR-062 Amendment 1 (2026-09-04). I supplied an F-1 replacement
clause correcting an authority attribution. Architect committed it byte-exact — and the original's
trailing parenthetical (*"(see `100`'s header for the named residual: … `Transfer`-class …)"*),
which documented a **different** residual, ended up hanging off my closing sentence about a ruling
living only in Linear. Every factual claim stayed true; a reader can no longer tell which residual
is named. Nothing in a verbatim check catches this, because the committer did exactly what I asked.

**How to apply:**

- **Quote the last few words of the surviving tail** in the hand-off, with an explicit instruction:
  *"the existing `(see …)` parenthetical reattaches after '…so `100` changes no `is_tax_payment`
  value.'"* One line, and it removes the whole failure class.
- **Prefer a replacement that ends at a sentence boundary.** If the target's clause I am correcting
  is mid-sentence, extend my block to swallow the rest of the sentence rather than butting against
  it.
- **Re-read my own landed text at the re-confirm, as prose, not as a diff.** The diff shows my
  insertion is correct; only reading the assembled paragraph shows the tail is now misattached.
- **Catch it in the same message as the clearance.** I found this while confirming GREEN and named
  it there with *"the defect is in text I supplied"* — naming my own error alongside a clean verdict
  costs nothing and is the norm that keeps the verdict trustworthy.

**The companion half — when the committer EXPANDS my fix's scope, evaluate the expansion, don't
default to the literal scope I named.** Same sitting: I flagged two locations carrying a false
attribution; Architect fixed **four**, and team-lead offered to narrow it back to my literal two.
The extra two carried the identical false claim in different words (*"Discharges … Decision 3's hard
precondition"*; *"The V1.4 inventory session is that enumeration"*). **My enumeration was
incomplete, and a literal-scope rollback would have left two live instances of the finding.**
Endorse the expansion explicitly and say why — an unstated endorsement reads as tolerated scope
creep, and the next agent narrows the one after it. Grep the whole file for the *claim*, not for the
sentences I happened to quote.

⚠⚠ **THE SEVERE FORM — the orphaned tail is a CONTROL, so applying my block literally REMOVES A
FENCE.** PR #674 / ADR-019 amendment, round-2 re-confirm 2026-09-09. My F6 "commit-ready
replacement" for the C4 paragraph stopped at *"…is recoverable."* and silently dropped the
paragraph's closing **`Number retained; nothing may cite C4 as a rule.`** Committed literally — the
way I ask for supplied text to be applied — my precision fix would have **deleted the C4 citation
fence** while reading as a tightening. Architect caught it and re-appended. The E1 lesson upgrades
this class from "misattached prose" to "silent control deletion": **before handing over a
replacement, ask what the target paragraph's LAST sentence does — if it is normative, my block must
carry it or explicitly instruct that it survives.** Non-prose paragraphs (condition texts, fences,
allowlists) are where the tail is load-bearing.

**Sibling failure, same sitting, same root (E2) — a formatting marker is content when the file
reserves that register.** My F4 block was supplied as a Markdown blockquote (`> `). In that
amendment the blockquote is the **reserved register for reconstructed condition text**, so my
caveat *about* the reconstruction would have rendered as though it were part of what Sec wrote —
the exact confusion the amendment exists to prevent. Architect demoted it to a plain paragraph and
was right. **Before supplying text: read what the target file's blockquote / bold / ⚠ / code-fence
conventions MEAN there, and match the register of the thing I am writing, not the register that
looks emphatic.** Endorse the committer's formatting correction explicitly — it is a real catch.

**Common root of both:** I was supplying *fragments* while asking for *verbatim application*. A
verbatim-application request obliges me to hand over a **complete, self-contained replacement
unit** — full paragraph boundaries on both sides, in the target's own register.

Related: [[supplied-verbatim-text-ships-unfiltered]],
[[enumeration-and-watcher-stop-one-short]], [[a-stated-invariant-stronger-than-the-contract]],
[[off-tree-fcto-rulings-live-in-linear]], [[my-review-measurements-become-quoted-sources]].
