---
name: with-check-is-a-policy-not-a-check-constraint
description: An RLS WITH CHECK clause and a table CHECK constraint are different objects — WITH CHECK subqueries freely and SURVIVES session_replication_role=replica; conflating them produced a false warrant Sec refused
metadata:
  type: reference
---

**`CHECK constraint` ≠ `WITH CHECK`.** A table CHECK constraint cannot subquery. An RLS
`WITH CHECK` is a **policy clause**: it subqueries freely, and because policies are not triggers it
**survives `session_replication_role = replica`** (measured — a `WITH CHECK` refused a forged
`users_id` INSERT with the GUC in force, control leg refusing it without).

**Why this bit:** ADR-011 Decision 3's opening sentence sanctions **two** realization forms —
*"DB-level WITH CHECK constraint (single columns) or BEFORE INSERT/UPDATE trigger (array elements
PostgreSQL can't express declaratively)"* — and names **WITH CHECK first, for single columns**. I
argued every D3 fence *must* be a trigger because "a matched-tenant test must read the referenced
row and a CHECK cannot subquery." True of a table CHECK, **irrelevant to a WITH CHECK**, so the
warrant established nothing — and it failed hardest exactly where I'd added it, since a future
single-column instance in D3's own preferred form would NOT be inert under the GUC and the text
would have told its reader the opposite.

⚠ **The measured fact is dated, not a law.** Every DDL-realized D3 fence *is* a BEFORE ROW trigger
as of 2026-09-03 — but that is an inventory, so **re-survey each new instance** rather than reading
it as a family property. The durable form hands the reader the **discriminator** (which realization
form is this instance?) instead of a conclusion.

⚠ **Method blindness worth remembering:** both of my enumeration passes searched trigger
*functions*, so a policy-realized instance would have been invisible to either. A search can only
falsify within the object class it looks at.

**And the citation half.** The sentence I used as the warrant — *"Decision 3 permits a trigger where
PG cannot express the constraint declaratively"* — **exists verbatim in the repo, but in ADR-025's
`012` discussion, not in Decision 3.** Right content, wrong pointer: it would pass a verbatim check
and fail an attribution check. That ADR-025 passage makes the same CHECK-vs-WITH-CHECK conflation
and still stands on `main` — inherited, not invented, and booked rather than fixed.

**Sharper form of the both-halves citation rule, from Sec's correction of their own diagnosis:**
*"substance-first reading caught it, but only by accident of the substance being wrong too — had
ADR-025's claim been correct, I would have passed a mis-attributed quote."* So **"is this verbatim?"
must mean "verbatim FROM THE SOURCE I NAMED"**, not "verbatim from anywhere in the repo". A quote can
be verbatim-somewhere and still mis-attributed, and that form survives every byte-comparison check.

**A pure-insertion diff is a verification instrument, not tidiness.** Sec required the amendment to
land as `N insertions, 0 deletions` so *"the protected structures were not touched"* is checkable in
one command instead of by inspection — and then ruled a related correction OUT of the same PR
because folding it would introduce deletions and destroy that property. Cheaper in PR count, worse
in verifiability; verifiability won. **When a reviewer imposes a diff shape, treat it as a control
and do not spend it on convenience.**

Related: [[feedback_false_composite_citation]] · [[feedback_cited_precedent_transmits_its_retracted_half]] ·
[[feedback_failed_grep_looks_like_a_clean_result]].
