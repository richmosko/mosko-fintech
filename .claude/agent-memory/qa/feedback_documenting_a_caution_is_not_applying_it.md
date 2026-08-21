---
name: feedback-documenting-a-caution-is-not-applying-it
description: authored DESIGN.md §16 (reused-scratch-DB masks id-order bugs) then ran the next suite-level claim against the exact reused DB the caution warns about, three hours later
metadata:
  type: feedback
---

Wrote a standing caution into `supabase/tests/rls/DESIGN.md` (§16, SELF-330): a REUSED scratch
database hides id-order-sensitive bugs because its sequences are already advanced past the
boundaries that trigger them — build fresh before trusting a suite-level green on that class of
assertion. Then, ~3 hours later in the same session, ran the X3 RED/GREEN demonstration against
`scratch330` — the exact reused instrument the caution names — without re-deriving whether it
applied. Architect caught it (harmlessly, since their own fresh-DB sweep covered the claim
regardless) and named the gap precisely: "the caution is three hours old and already easy to walk
past."

**Why this matters, beyond the specific incident:** recording a caution creates the FEELING of
having internalized it — the rule now exists, is searchable, will catch the NEXT person who reads
it — which is exactly why it is easy to not apply to your own very next action. The caution and its
application are two different acts, and writing the first does not perform the second.

**How to apply:** immediately after documenting any standing caution ("watch out for X"), the very
next time X's precondition appears in your own work in the SAME session, explicitly check it against
the caution just written — do not rely on having-written-it to have changed your instincts yet. For
this specific caution: before citing a scratch DB result as a suite-level claim (not a single
targeted repro), ask "was this DB just rebuilt fresh, or has it been through prior runs?" — if the
latter, either rebuild fresh or scope the claim to what a reused DB can actually prove (a targeted,
single-mechanism repro is fine; "N/N green, no regressions" is not, without a fresh build backing
it).

Related: [[feedback_scratch_db_perf_seed_must_be_rolled_back]] (a different reused-scratch-DB
contamination mode, same root cause — treating a scratch DB as stateless when it is not) and the
general discipline in `feedback_verify_causal_mechanism_before_stating` — a claim's INSTRUMENT
needs the same scrutiny as the claim itself, including when the instrument's limits are ones you
personally just wrote down.
