---
name: sec-lock-cross-check-catches-my-own-misreads
description: A quotation can be false against the plausible source and exact against the CITED one — read the source the text names, not the one you expect, before forwarding a drift finding
metadata:
  type: feedback
---

Before forwarding any paraphrase-drift finding, read **the source the text actually cites** — not the
source you assume it paraphrased. A quotation can be verbatim-false against the neighbouring artifact
and verbatim-exact against the cited one.

**Why:** reviewing migration `067`, I flagged its quotation `"consults no clock at all"` as added-words
drift, because migration `066`'s header reads *"it consults no clock"*. `067` attributed the phrase to
the **ADR-049 amendment**, not to `066` — and `DECISIONS.md` carries *"`period_was_due` therefore
consults no clock at all"* verbatim. My finding was wrong; the Sec-Lock cross-check caught it at the
boundary, before it went to team-lead. Forwarding it would have cost a round trip and, worse, would
have pushed a correct quotation toward being "fixed".

**The same shape, second instance:** grepping for a promised deliverable across the test files I already
knew about returned zero hits — the tests were in a NEW file added by the same commit. I was one step
from reporting a missing deliverable that was present. **A zero-hit grep is a claim about the SEARCH
SCOPE, not about the tree.** Before concluding "absent", re-run against the commit's own file list
(`git show --stat`) or the whole tree, never against the file set you had in mind.

**How to apply:** on every verbatim-vs-paraphrase axis check, flatten the cited file
(`sed 's/^--*//' | tr '\n' ' ' | tr -s ' '`) so SQL-comment and string-concatenation line wrapping
doesn't produce false negatives, then grep the quoted fragment in **the cited artifact first**. A zero
hit means "check the other candidate sources", not "drift found". Name my own error in the same
message as the findings, never in a follow-up. Related:
[[measure-the-fence-regex-not-its-comment]].
