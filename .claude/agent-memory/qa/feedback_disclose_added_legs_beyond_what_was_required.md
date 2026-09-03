---
name: disclose-added-legs-beyond-what-was-required
description: Sec confirmed (SELF-257 AC11, ab14ca8) that flagging a leg I added beyond the required fix (AC7-3, the FK's ON DELETE RESTRICT direction) in the hand-off summary — rather than letting it appear silently inside the diff — was the right call, and verified it rather than waving it through on the strength of the rest.
metadata:
  type: feedback
---

Landing Sec's AC11 AMBER verdict, the two required edits didn't cover the FK's OTHER
live direction (ON DELETE RESTRICT) — I added a new leg (AC7-3) proving it, beyond what
was asked, because it was cheap and closed an obvious adjacent gap (the block now says
the FK is "not dead," and AC7-3 is the only thing that actually shows that). When
reporting the diff to Sec, I explicitly called it out as "a leg I added beyond what was
required" rather than folding it silently into the "both required edits are complete"
framing.

Sec's response confirmed this was the right instinct in exactly these words: "You added
a leg I did not require, so I verified it rather than accepting it on the strength of
the rest... Disclosing an added leg in your summary rather than letting it appear in the
diff is the behaviour I want — a new leg at sign-off scope is new surface for vacuity,
and I'd rather be told to look at it than find it."

**Why:** a diff-only sign-off (Sec explicitly scoped their AC11 signature to
`b138bf1..ab14ca8`, not a re-review of the whole file) is a trust boundary — every line
inside that diff is implicitly claimed to be either the required fix or a disclosed
extra. An undisclosed extra inside a "just the required fix" diff would be the exact
kind of silent scope-creep a diff-only reviewer is structurally unable to catch by
skimming, since they're primed to expect only the two named changes.

**How to apply:** any time a hand-off diff contains something beyond what was explicitly
asked for — even a small, clearly-beneficial addition — name it as an addition in the
accompanying message, don't let the reviewer discover it by reading the diff cold. This
generalizes past Sec sign-offs: the same applies to team-lead reports, PR descriptions,
and any other diff-scoped review.

Related: [[feedback_adding_vs_qualifying_verification_asymmetry]] — the same "the
unflagged part is where the risk hides" shape, one layer removed (there: a qualifier
added to a claim; here: a leg added to a diff).
