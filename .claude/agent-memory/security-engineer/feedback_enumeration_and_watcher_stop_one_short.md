---
name: enumeration-and-watcher-stop-one-short
description: Both findings in the GL-split joint-review were "stops one item short" — a per-column D3 enumeration that skipped the SIBLING DEFAULT table's copy of the column, and a structural battery that asserted a required clause on polwithcheck but not polqual. Check the last item and the second side.
metadata:
  type: feedback
---

**When an author says a check was performed "per column rather than asserted in one line", enumerate the columns yourself — and include the SIBLING table.** When a clause is required on BOTH the read and the write policy, grep the battery for BOTH `polqual` and `polwithcheck`; a leg on one side is not coverage of the other.

**Why:** at the GL-split merge-gate both of my findings had the identical shape — a correct, careful, explicitly-invited check that stopped one item short.

- `084`'s header made the per-column Decision-3 disposition its selling point and even wrote *"'No new FK-shaped column' would have been FALSE as a bare sentence — `tax_character` is one — and a reviewer checking it against the DDL would have found the discrepancy and been right to."* It then asserted *"`posting_prototype_default` carries neither a `users_id` nor any FK at all"* — and `posting_prototype_default.tax_character` **is** an FK. The sentence propagated into canonical **ADR-011 Decision 3** and into the `041` battery header before anyone read the DDL. **The tell:** the new table was described as mirroring `taxonomy_default`'s posture, but `taxonomy_default.tax_character` is a **CHECK, not an FK** — so the "mirror" was actually a strengthening, and the false sentence was inherited from the wrong model.
- The `084` battery asserted the `025` aal2 backstop on `posting_prototype_insert`'s `polwithcheck` and never on `posting_prototype_select`'s `polqual` — while the migration's own header argued, correctly, that **the read side is the half an author skips** (`009` shipped `user_taxonomy_select` unclaused; `025` added it later by ALTER POLICY). The control was present; only the watcher was one-sided.

**My own scope was one short too, and that is the third instance.** I swept only text *introduced by the PR* and reported "three false sites". Architect's wider sweep found **two more in the ADR's own merged body** — which is where the claim originated and where the future implementer actually reads it. **When a PR introduces a false statement, the claim usually came from somewhere; sweep the canonical body, not just the diff.** A diff-scoped sweep is a claim about the diff, not about the tree.

**How to apply:**
- On any new table, read the CREATE TABLE and list every `references` clause **including on the global/default sibling table**, then compare that list against the prose disposition. Do not accept "carries no FK" for a table whose column set is described as mirroring one that does.
- When reporting "N sites carry this false claim", say **what the sweep was scoped to** (diff vs whole tree) — an unscoped count reads as complete. Then sweep the merged canonical body before naming a number.
- After the fix, re-measure the claim string. Expect hits to *remain*: merged ADR body text is **annotated, never rewritten**, and a correction QUOTES the false statement. Classify each hit **asserting vs naming** (D4's PR #74/#368 discipline) and say explicitly that the remaining hits must NOT be "cleaned up" — otherwise the next consistency sweep deletes the annotations.
- When a table's model table is OLDER, ask whether the new one diverged upward. A strengthening described as a mirror is still a false description, and the fix is to correct the prose — **never demote the new control to make the sentence true.** Say that explicitly, or a later consistency sweep will demote it.
- For any clause required on both sides of RLS, grep the battery for the **policy name** and count the legs: one hit means one side is unwatched. State the catch criterion as "RED if `<policy>`'s USING does not carry X", and remember the `plan()` bump.
- A false statement whose *disposition* is still correct is a FLAG, not a veto — but it must be fixed **in the PR that introduces it**, because it lands in ADR text that later reviewers are instructed to read live.

Related: [[a-grep-over-comments-measures-intent-not-data]] · [[verify-the-stated-correctness-mechanism]] · [[measure-the-fence-regex-not-its-comment]] · [[replacement-control-name-the-losing-side]]
