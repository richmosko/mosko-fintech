---
name: fence-reachability-is-a-property-of-the-caller
description: An upstream owner-scoped read can collapse a downstream cross-tenant fence into a no-op — reachability belongs to the calling body, not to the fence
metadata:
  type: reference
---

**A tenant fence's reachability is a property of the BODY THAT CALLS IT, not of the fence.**

Measured at `088` (SELF-325). I asserted that D3 `#7` (`fn_account_trans_security_asset`:
*global OR owned by the **account's** tenant*) was behaviourally reachable, because unlike
`087` — which mints its asset, so `#7` cannot fail — `088` accepts a caller-supplied
`asset_id`. **False.** `088` reads the account under `account_select`, which is owner-only
(`users_id = auth.uid()`), so any caller past that read **is** the account's tenant. That makes
`#7`'s predicate **identical** to `016`'s `asset_select` (*global OR owned by the **caller***),
which the body's own guard reads under. The guard always rejects first; `#7` never fires.

⚠ **The general shape: an upstream OWNER-SCOPED read silently collapses a downstream
MATCHED-TENANT fence, because it forces `caller == row-owner` and the two predicates become
coincident.** The fence is not removed and still greps; it simply cannot fire on that path.
Say **DORMANT, not dead**, and name what would revive it — here, widening the read to
`wr_access` or un-dorming `pfin.account_users`. A present-tense "unreachable" goes stale; a
named revival condition does not.

**Two lessons worth more than the fact:**

1. ⚠ **I had already found the other half and filed it as unrelated.** One turn earlier I'd
   noted that `088`'s account read is owner-scoped while `account_trans_insert` keys on the
   wr_access-JOIN, and recorded it as a "stricter than the write policy" curiosity. *That read
   is what collapses the fence.* **Two correct observations, made separately, that only
   contradict each other when placed side by side — neither reading found it; QA's measurement
   did.** When holding a note about a body's scoping, check it against every claim already made
   about that same body.
2. **The false claim had FOUR asserting sites**, not the two I'd have revisited from memory —
   the extras were a CONTRACT block and the `comment on` literal. Grep the CLAIM; never revisit
   the places you remember writing it. ⚠ Retain the block that **names** the retraction to
   refute it — naming is not asserting (ADR-011 D4's own distinction).

⚠ **A commit message has no supersession mechanism.** `ad7f2a1`'s subject carried the
overclaim and could not be rewritten (teammates were standing on the ref). The correcting
commit's message must name the message it corrects.

Related: [[feedback_inversion_test_the_rationale_not_the_presence]] ·
[[feedback_verifying_a_measurement_is_not_verifying_a_claim]] ·
[[feedback_a_ref_handed_over_is_not_yours_to_advance]]
