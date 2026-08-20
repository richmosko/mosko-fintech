---
name: no-fk-on-column-is-not-no-fk-in-lineage
description: A deliberately FK-less snapshot column still inherits fencing from the live row it snapshots — re-targeting an FK anywhere upstream can reject the fixture before the FK-less table's own logic ever runs
metadata:
  type: reference
---

When re-targeting an FK, the blast radius includes tables that **carry no FK at all**.

`pfin.account_trans_annotation_history.sub_cat_id` (`031`) is a plain `bigint`
snapshot with **no foreign key by design** — audit-truthful if the referenced row is
later deleted. Reading that column, the correct conclusion is *"nothing here to
re-target."* **That conclusion is wrong**, and it is wrong in the direction that
produces a green test proving nothing.

**Why:** the history row is written *from* a live `023` annotation, and `023`'s
`sub_cat_id` **is** fenced. Re-target that FK and the fixture INSERT that seeds the
live row is rejected **before any snapshot logic runs** — so the file either fails for
a reason that looks unrelated, or (after a naive fixture repair) passes without ever
exercising what it claims to.

**How to apply.** When an FK moves, sweep **one hop upstream of every FK-less column
that mirrors it**, not just the columns declared against the moved target. The
question is not *"does this column have a constraint"* but *"what has to succeed for a
row to arrive in this column at all."* Audit-class and snapshot tables are where this
bites, because their FK-lessness is deliberate and therefore reads as settled.

⚠ **Anticipating the risk is not the same as anticipating the mechanism.** This file
was flagged in advance as the likeliest to go green while proving nothing — the
prediction was right and the stated reason (a mechanical column-drop touching no id
assertion) was not the actual trap. A correct warning attached to the wrong mechanism
still lets the real one through if whoever acts on it only checks what you named.

Found by QA at the `084` GL split. Related: [[reserved-id-range-needs-a-maxvalue]] ·
[[consequence-list-inherits-its-authors-instrument]] · [[an-assertion-with-no-watcher]]
