---
name: a-preference-reads-as-a-ruling-and-a-caveat-sets-the-axis
description: A stated Sec preference is executed as a ruling, and a caveat attached to an option fixes the axis everyone reasons on afterwards — measure the adjacent convention before doing either, and refuse a rationale request whose premise is false
metadata:
  type: feedback
---

Three failure modes in how my advisory output gets consumed. All three fired on one
wire-format question (SELF-325 `assetId`, 2026-08-21).

**1. A stated preference is executed as a ruling.** I offered A/B/C and said explicitly
that B was acceptable. Downstream it was recorded as *"Sec's ruling overruled Architect's,"*
Frontend built twice on the earlier choice and reverted. **The preference order is the
operative output; the "any of these clears" sentence is not read.** If I genuinely do not
care, say *"any of these clears — take the one consistent with existing convention"* and
give **no ordering**. If I do care, I must have measured enough to defend the ordering.

**2. Never state a preference on a CONVENTION-SHAPED question without measuring the
adjacent convention.** The same file already carried a deliberate, opposite choice for a
sibling field (`sourceId` as a decimal string). I had not read it. A preference issued
into an unmeasured convention is how a "fix" becomes a churn.

**3. ⚠ A CAVEAT ATTACHED TO AN OPTION FIXES THE AXIS everyone reasons on afterwards.**
I attached *"`Number()` is lossy above 2^53"* to option A. True in isolation, and **the
wrong axis** — it made "why does `assetId` tolerate the 2^53 exposure `sourceId` avoids?"
look like a question with an answer, and that mis-frame propagated into two other people's
work as a request I was then asked to satisfy. **Before attaching a caveat, ask whether it
is the OPERATIVE axis or merely a true fact.** A true fact on the wrong axis is a frame,
and frames get inherited.

**The corollary, and it is the reusable half: a request to supply a rationale can
PRESUPPOSE a discriminator that does not exist. Refusing the premise is the answer.**
Asked for "the one-line reason `assetId` tolerates what `sourceId` avoids," I measured
instead: `sourceId` is a native JS **`bigint`** (`admit(): Promise<{ sourceId: bigint }>`)
and `JSON.stringify` **throws** on a bigint, so `String()` is **forced by the language**,
not chosen for precision; `assetId` is declared **`number`** by `resolveSecurityId`'s own
signature, so its string-on-the-wire form was **the driver leaking a bigint past a
number-typed boundary — a type lie, not a convention.** The real discriminator is the
**in-worker representation**; neither site makes a precision claim. Writing the requested
line would have **fabricated a distinction to fill a template**, and an invented rationale
is cited later as if it were reasoned.

**4. A GAP ENUMERATION FORWARDED VERBATIM BECOMES A CEILING.** Same branch: I listed the
properties `089` had no watcher for — "INVOKER / search_path / ACLs / no-rank-CASE /
cardinality" — as a *description of what was unwatched at that ref*. It was relayed
verbatim (correctly) and was about to be built as a **checklist**: five legs authored,
done. Verbatim relay is right; **saying whether the list is a FLOOR or a SPEC is on me**,
and an unlabelled list defaults to a spec.

Worse, the list itself was wrong in a way I had just criticised elsewhere: **every item on
it was a POSTURE assertion, and none was a BEHAVIOUR assertion.** `prosecdef = false` does
not prove tenant isolation for an `authenticated`-granted RPC taking a caller-supplied
`bigint[]`. I had flagged exactly this substitution in `088`'s own `#7` disposition —
structural-trigger-bound is not behaviourally-rejects — and then made it in my own
enumeration one exchange later. **Apply the rule mechanically to my own output, not only to
the artifact under review.**

**How to apply:**
- Label every list I hand over: **floor or spec.** Unlabelled reads as spec.
- Before handing over a list of properties-to-assert, sort it into POSTURE vs BEHAVIOUR and
  check the behaviour column is non-empty. A list of catalog assertions watches the
  catalog, not the fence.
- Convention-shaped question ⇒ grep the sibling fields in the SAME file before ruling or
  preferring. Cite what the existing comment already says — often it states the real
  reason and nobody re-read it.
- When a teammate asks for "the rationale for X vs Y," treat the asked-for axis as a
  hypothesis, not a given. Measure both sides. If the axis is wrong, say so and supply the
  right one — do not fill the template.
- Once churn has already happened, decide on the MERITS, not on symmetry: here the
  precedent genuinely did not transfer, so "do not revert again" was correct. Say which.

Related: [[feedback_clearance_conditions_must_absorb_my_own_recommendations]] ·
[[feedback_verify_the_stated_correctness_mechanism]] ·
[[feedback_sec_lock_cross_check_catches_my_own_misreads]]
