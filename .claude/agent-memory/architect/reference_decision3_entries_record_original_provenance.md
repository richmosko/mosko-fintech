---
name: decision3-entries-record-original-provenance
description: ADR-011 Decision 3's numbered instance entries are never updated — re-targets live in later amendments below them, so reading an entry alone gives a stale FK target
metadata:
  type: reference
---

**ADR-011 Decision 3's numbered instance entries record ORIGINAL LOCKING PROVENANCE and are
never edited. A re-target is filed as a LATER AMENDMENT further down the same Decision.**

Measured 2026-08-21, by walking into it while authoring `088`. The entry for **#10** still
reads `pfin.account_trans_annotation.sub_cat_id -> pfin.user_taxonomy`. **False since `084` /
ADR-058**, whose *RE-TARGET resolution* moved **#10 and #13** to `pfin.posting_prototype(id)`
when the GL split moved the posting rows out. `084` also re-issued `030`'s Trade-constraint
trigger, which now reads `posting_prototype`.

⚠ **Reading the entry alone yields the stale target and feels like diligence** — you cited the
canonical source, by name-anchor, live. It is still wrong.

⇒ **Cite an instance only after reading its entry AND every amendment below it.** A re-target
amends an entry's **body**; it never changes the **class** and never changes the **label**
(that rule is itself stated in the re-target resolution).

This is the inherited-citation drift Decision 4's own attribution CHANGELOG names: *"read that
decision's AMENDMENTS in the same pass, not only its body, because a retraction attached to a
decision does not travel with citations of it."* ⚠ I had quoted that rule to two teammates on
the same branch where I violated it.

⚠ **Same shape as `038` vs `040`** — a later migration re-issues a function or an FK and the
earlier text still greps cleanly. **Grep-finds-it is not evidence it is live.**

**Mitigating detail worth knowing:** `084` caps `user_taxonomy`'s identity at 999999999 and
mints `posting_prototype` from 1000000000, with an abort guard proving no id resolves in both.
So an id fetched from the wrong table **fails closed** rather than silently matching the wrong
row — the disjointness is a real fence, not a convention.

Related: [[feedback_cited_precedent_transmits_its_retracted_half]] ·
[[feedback_mirror_a_function_from_the_catalog_not_the_file]] ·
[[reference_fence_reachability_is_a_property_of_the_caller]]
