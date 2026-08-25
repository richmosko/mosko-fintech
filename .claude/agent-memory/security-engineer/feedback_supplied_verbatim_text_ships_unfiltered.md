---
name: supplied-verbatim-text-ships-unfiltered
description: Commit-ready text I hand another pen-holder is committed byte-for-byte, so MY formatting errors ship — proofread a supplied block against the SURROUNDING FILE's convention, not just for correct content
metadata:
  type: feedback
---

**When I supply commit-ready text under the verbatim protocol, the receiving agent commits it
byte-for-byte — including my mistakes. Proofread the block against the conventions of the file it is
going INTO, not only for correct content.**

**Why:** at SELF-246 / `090_cashflow_target.sql` I supplied a 15-line header-comment replacement whose
second line read `-- FK-shaped reference column.` (one space) where that file's header convention —
and the very line I was replacing — uses `--   ` (three). Architect committed it exactly as written,
which was **correct behaviour**: verbatim commitment is the whole point, and the paraphrase-drift
failure class this role exists to catch is *worse* than a whitespace defect. So the branch now carries
a one-line indentation inconsistency that is **mine**, introduced by the mechanism designed to protect
my text. I did not block on it — a re-freeze of a reviewed sha to fix whitespace costs more than it
buys — but I named it in the same message as the GREEN rather than letting it surface later as
someone else's sloppiness.

**How to apply:** before handing over a commit-ready block, read the lines immediately above and below
the insertion point in the target file and match them — indentation, comment-prefix width, bullet
glyphs, wrap column, quote style. `git show <ref>:<path>` the neighbourhood; do not compose the block
from memory of the file's style. This costs one command and is the only proofread that will ever
happen: the receiving agent is under instruction NOT to fix it, and a reviewer diffing my text against
the commit will find them identical and call it clean.

**The general shape, worth more than the whitespace:** *a protocol that removes someone else's
discretion transfers the entire error budget to me.* Anywhere I say "commit this verbatim," I have also
said "there is no second reader." Corollary for the receiving end — **do not soften this into "commit
verbatim unless something looks off."** A pen-holder who silently corrects my formatting is one who
might silently correct my wording, and I would rather ship a bad space than lose the guarantee.

Related: [[clearance-conditions-must-absorb-my-own-recommendations]],
[[read-decisions-from-the-pr-branch-when-the-pr-edits-it]],
[[temp-handoff-path-is-per-worktree]].
