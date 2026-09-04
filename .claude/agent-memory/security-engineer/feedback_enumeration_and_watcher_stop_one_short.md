---
name: enumeration-and-watcher-stop-one-short
description: The "stops one item short" family — a per-column D3 enumeration that skipped the SIBLING DEFAULT table's FK, a battery asserting a required clause on polwithcheck but never polqual, a diff-scoped sweep of a claim whose origin was the merged ADR body, and a count published from a `| head -N`-truncated diff. Never put a count and a truncating pipe in the same turn.
metadata:
  type: feedback
---

**When an author says a check was performed "per column rather than asserted in one line", enumerate the columns yourself — and include the SIBLING table.** When a clause is required on BOTH the read and the write policy, grep the battery for BOTH `polqual` and `polwithcheck`; a leg on one side is not coverage of the other.

**Why:** at the GL-split merge-gate both of my findings had the identical shape — a correct, careful, explicitly-invited check that stopped one item short.

- `084`'s header made the per-column Decision-3 disposition its selling point and even wrote *"'No new FK-shaped column' would have been FALSE as a bare sentence — `tax_character` is one — and a reviewer checking it against the DDL would have found the discrepancy and been right to."* It then asserted *"`posting_prototype_default` carries neither a `users_id` nor any FK at all"* — and `posting_prototype_default.tax_character` **is** an FK. The sentence propagated into canonical **ADR-011 Decision 3** and into the `041` battery header before anyone read the DDL. **The tell:** the new table was described as mirroring `taxonomy_default`'s posture, but `taxonomy_default.tax_character` is a **CHECK, not an FK** — so the "mirror" was actually a strengthening, and the false sentence was inherited from the wrong model.
- The `084` battery asserted the `025` aal2 backstop on `posting_prototype_insert`'s `polwithcheck` and never on `posting_prototype_select`'s `polqual` — while the migration's own header argued, correctly, that **the read side is the half an author skips** (`009` shipped `user_taxonomy_select` unclaused; `025` added it later by ALTER POLICY). The control was present; only the watcher was one-sided.

**My own scope was one short too, and that is the third instance.** I swept only text *introduced by the PR* and reported "three false sites". Architect's wider sweep found **two more in the ADR's own merged body** — which is where the claim originated and where the future implementer actually reads it. **When a PR introduces a false statement, the claim usually came from somewhere; sweep the canonical body, not just the diff.** A diff-scoped sweep is a claim about the diff, not about the tree.

**The fourth instance, and it is the cheapest to prevent: `| head -N` on a diff, then an enumeration
published as complete (SELF-330).** I ran `git diff main...HEAD -- <two files> | head -120`, read
what came back, and reported that a stale claim sat on **four** surfaces. It sat on five. The fifth
was in the second of the two files I had asked for — **inside the diff I ran**, below the cut my own
pipe made. Team-lead's report was generous ("Sec did not miss it — the fifth was not in what you were
reading"); that was factually wrong and I said so, because accepting an exoneration for an error I
did make would leave the habit in place.

**The habit to change is mechanical, not attentional.** A truncating pipe (`head`, `sed -n '1,Np'`,
`| head -20` on a grep) is a *filter*, and its output cannot support a *complete-enumeration* claim —
but nothing in the output says so, which is precisely why the claim gets made. Either (a) drop the
truncation when the next statement will be a count, (b) count first with a non-truncating instrument
(`git grep -c <claim-string> <ref> -- <paths>`) and read the truncated diff only for context, or
(c) publish the number with its scope attached ("four in the first 120 lines of that diff"), which
makes it self-refuting and therefore harmless. ⚠ **A count and a truncating pipe must not appear in
the same turn** unless (c) applies.

**The corollary that made the miss consequential:** the fifth surface carried a hazard the other four
did not — an **attributed verbatim quote whose source had since been reworded**. Byte-perfect,
correctly attributed, and misrepresenting; it passes every verbatim check, and the attribution is
what makes the stale version read as authoritative. **When reviewing comments that quote a teammate
with attribution, re-read the SOURCE sentence as it stands now, not just the quotation's fidelity.**
Prefer prose over an attributed quote in a comment for exactly this reason — a quote's correctness
has an external dependency that nothing watches. Same family as
[[sound-quote-false-gloss-drift]] (in the shared index) and
[[my-review-measurements-become-quoted-sources]].

**How to apply:**
- On any new table, read the CREATE TABLE and list every `references` clause **including on the global/default sibling table**, then compare that list against the prose disposition. Do not accept "carries no FK" for a table whose column set is described as mirroring one that does.
- When reporting "N sites carry this false claim", say **what the sweep was scoped to** (diff vs whole tree) — an unscoped count reads as complete. Then sweep the merged canonical body before naming a number.
- After the fix, re-measure the claim string. Expect hits to *remain*: merged ADR body text is **annotated, never rewritten**, and a correction QUOTES the false statement. Classify each hit **asserting vs naming** (D4's PR #74/#368 discipline) and say explicitly that the remaining hits must NOT be "cleaned up" — otherwise the next consistency sweep deletes the annotations.
- When a table's model table is OLDER, ask whether the new one diverged upward. A strengthening described as a mirror is still a false description, and the fix is to correct the prose — **never demote the new control to make the sentence true.** Say that explicitly, or a later consistency sweep will demote it.
- For any clause required on both sides of RLS, grep the battery for the **policy name** and count the legs: one hit means one side is unwatched. State the catch criterion as "RED if `<policy>`'s USING does not carry X", and remember the `plan()` bump.
- A false statement whose *disposition* is still correct is a FLAG, not a veto — but it must be fixed **in the PR that introduces it**, because it lands in ADR text that later reviewers are instructed to read live.

---

⚠ **UPSTREAM VARIANT — grep DRAFTED ACs for bare instance NUMBERS, because that is where a retired
label re-enters the tree.** At the V1.4 pre-flight, two drafted ACs instructed a matched-tenant
fence *"per ADR-011 Decision 3 … (4th instance)"* and *"(5th instance)"*. Both were the retired
Wave-5 operational grain, and the family had long since been reconciled past them.

- **Reusing a DROPPED label is worse than inventing one.** `#5` was DDL-realized and then removed,
  and the DROP resolution says in terms that it is *"retired-in-place, NOT renumbered or reused."*
  A migration built from that AC stamps `#5` into a live `comment on function`, so the next
  reviewer obeying the read-the-decision-live discipline finds a canonical label attached to a
  column the canon records as deleted — the enumeration's own integrity check reports a
  **resurrection**. An invented label reads as a mistake; a resurrected one reads as canon.
- **Where to look:** the number is almost never in the migration at authoring time — it is
  transcribed from an issue, a backlog entry, or a seam memo drafted against an older grain.
  Review the AC, not just the DDL, and require the AC to say *"the next canonical label, allocated
  at the migration"* and **name no number**. Do not name one myself either.
- **The fold-in rule is the other half:** the label is allocated and folded into the canonical
  enumeration **in the PR that DDL-realizes it**, never at a later reconciliation — a migration
  asserting a label whose canon does not yet contain it is a forward reference to a document it
  does not control.
- **A drafted fence can also be UNFALSIFIABLE.** In the same pass one AC instructed a
  matched-tenant trigger on a child table whose FK **is** its only tenant anchor — nothing to
  compare, so the fence cannot fail. Check that a proposed fence has two facts that can disagree
  before agreeing it is owed; a leg that cannot fail entering a canonical enumeration is worse
  than no leg.

⚠ **ASYMMETRIC-LEG variant: a LATE CORRECTIVE TERM lands on the leg the author was exercising, and
only that one.** At SELF-262 the payload had two structurally parallel legs (an "ordinary" schedule
and an "LT CG" schedule) assembled through one LEFT-JOIN code path. A control the migration header
spent eight lines on — *"the payload says so"* when a present-but-empty schedule suppresses a
fallback — needed an extra `_empty_no_fallback` disjunct to cover the no-fallback case, because the
primary flag could only be set when a fallback was found. **The disjunct existed for the ordinary leg
and had no counterpart on the other**, so the second leg silently reported the negation of the truth.
Nothing in the header, the ADR or the design memo distinguished the legs — the code did.
**Tells:** a `coalesce(x, false)` on one leg and `coalesce(x, false) or y` on its twin; a header
paragraph whose subject is "per schedule type" over a payload assembled leg-by-leg; a "one code path,
no second branch" claim (`104` made one) sitting above two separately-written `jsonb_build_object`
blocks. **Prove it as a BOUNDARY PAIR one step apart, never by argument** — I put the two legs in the
identical state (delete every bracket row, no prior year) and got `true` / `false`. That is a finding
a reader cannot dispute and it doubles as the QA leg's fixture. Same family as the one-short shape
above: the enumeration was complete, the CORRECTION was not.

Related: [[a-grep-over-comments-measures-intent-not-data]] · [[verify-the-stated-correctness-mechanism]] · [[measure-the-fence-regex-not-its-comment]] · [[replacement-control-name-the-losing-side]] · [[pm-draft-ac-vs-schema]] · [[corrupt-the-control-canary-boundary-tie]] · [[zero-value-sentinel-flips-meaning]]
Related: [[a-grep-over-comments-measures-intent-not-data]] · [[verify-the-stated-correctness-mechanism]] · [[measure-the-fence-regex-not-its-comment]] · [[replacement-control-name-the-losing-side]] · [[pm-draft-ac-vs-schema]]

---

⚠ **DOWNSTREAM VARIANT — when a label is FINALLY allocated, grep the bare label across the whole
canon before believing the fold-in's own completeness claim.** At SELF-259 the D3 fold-in allocated
`#18` and its consequence bullet asserted *"**Both forward pointers are re-pointed to #19 in the
same edit**, because a pointer that survives its own allocation is the next instance's version of
the #16 slip."* `grep -n -- "#18" DECISIONS.md` returned **three** live sites, not two: the third
was in **ADR-042 Decision 5**, phrased differently (*"…and add a Decision-3 instance (`account_id →
account` a second time, **as #18**)"*) and therefore invisible to a grep for the *"next … still
takes"* sentence shape.

- **The tell is the self-congratulating bullet.** A fold-in that explains at length how it avoided a
  named past failure is asserting a countable fact about the tree. Count it. The bullet that
  celebrates closing the #16 slip was itself the instance of it.
- **A forward pointer does not have one canonical phrasing.** Grep the **bare label**, never the
  sentence template. The site that gets missed is always the one worded differently.
- **The fix shape is DROP THE NUMERAL, not re-point it.** Re-pointing `#18 → #19` recreates the same
  trap one allocation later; dropping it (Path B, D4's own PR #368 discharge — *"numeral dropped so
  it cannot re-stale"*) ends the class. Recommend the drop.
- **Landed migrations carrying the stale label are NOT in scope.** They are dated records, the same
  treatment the `[[SLOT-SEC]]` pin gets. Say the non-objection out loud, or the next sweep edits
  history.
- **Why this one bites hardest:** reusing an allocated label is the duplicate-label form of the
  resurrection hazard above — a future author obeying read-the-decision-live lands on the stale
  pointer and takes a number that is already taken. The discipline that exists to catch stale
  labels is what delivers them.

---

⚠ **SECURITY-DOC VARIANT — the SD matrix and the RT catalog are TWO registers describing the SAME
surface inside one file. A drift correction in one is not a correction.** At SELF-259 I reported
RT-24's acceptance text superseded on four counts and scoped the finding to that row. `SD-04`'s
exposure cell carried the same pre-build schema, and it is the cell a **schema-side** reader lands
on first. I had grepped `RT-24` and read that row; I never grepped the **column names**.

- **The grep that would have caught it is over the SUBJECT, not the label.** `grep -n RT-24` finds
  the row I already knew about. `grep -n lower_bound` / `tax_bracket_row` / `marginal_rate` finds
  every register asserting the same design. **When correcting drift, sweep the identifiers the
  drift is ABOUT, never the id of the artifact you were sent to fix.**
- **The SD cell was the more dangerous of the two, and the reason generalizes: its defect was an
  OMISSION.** Its child-column list left out the child's own `users_id` — the grain-(C) ruling that
  is the sole reason D3 instance `#18` exists. A wrong name is caught by the first person who runs
  the DDL; a **missing column in a prose column-list looks complete**, and building from it would
  have silently deleted a canonical family member. Diff a documented column list against
  `CREATE TABLE` **in both directions** — present-but-wrong *and* absent-but-required.
- **It also carried a false composite** (`BEFORE INSERT/UPDATE trigger enforcing strictly-increasing
  <column>`): a BEFORE INSERT OR UPDATE trigger genuinely is on that table, but it is the
  matched-tenant fence, not the set check. Two real things wrongly paired — which is exactly why it
  passed every spot-check. **On any table with more than one trigger, bind each stated trigger to
  its OWN job before accepting the sentence.**
- **After correcting, expect the old terms to still grep-hit** — they live inside the dated
  provenance comment that quotes the superseded wording. Classify those hits **naming, not
  asserting**, and say so in the comment, or the next consistency sweep deletes the annotation.

**How to apply:** before reporting a doc-drift finding as scoped, run one grep over the *subject's*
identifiers across the whole artifact and report the site list, not the site. And when a brief hands
me one row to fix, the fix is the claim, not the row — widen it, then surface the widening to the
caller as a scope change rather than shipping it quietly.

---

⚠ **DEFERRED-LABEL VARIANT — a label ALREADY ALLOCATED for an UNREALIZED surface gets a fresh
ordinal when that surface finally builds. Before agreeing a new label is owed, grep the family for
the COLUMN, not for the ordinal.** At the V1.5 pre-flight both `monthly_report` A-items drafted
*"Decision 3 family — 6th instance"* / *"7th instance"*. ADR-011 D3 already holds two labels for
exactly those two columns, carrying status **UNREALIZED — V1.3+** — canonically locked, DDL-deferred.
The surfaces **realize** existing labels; they add none.

- **The three variants now on record are three directions on one axis.** UPSTREAM = a RETIRED label
  re-enters. DOWNSTREAM = an ALLOCATED label is re-used one allocation later. DEFERRED = an
  ALLOCATED-BUT-UNBUILT label is DUPLICATED at build. All three produce two labels for one column;
  only the third is invisible to a grep of the ordinal, because the draft's number is not the
  canonical one and so matches nothing anywhere.
- **The mechanical check is the same in every direction and it is not a grep of the number:** read
  D3's entries for the **target column name**. The entries name their columns, so the column is the
  key. An ordinal is a claim; a column name is a fact.
- **A deferred label carries a SECOND failure mode the other two do not: the surface can build
  WITHOUT the column and nothing notices.** The same draft omitted the INTEGER[] column its
  allocated label fences, with no disposition recorded. That converts a *DDL-deferred* instance into
  a permanently invisible one — the table then exists, so nothing downstream ever surfaces the gap
  again. **When a wave realizes a table holding deferred instances, enumerate those instances
  against the drafted column list and require an explicit disposition for each absence (build /
  retire-by-amendment / re-defer).** Before calling the absence an omission, ask what a discharge
  would have looked like — here, one AC sentence citing the superseding ADR. There was none, which
  is what made it a finding rather than a judgement call.
- **Watch for the fence named on the TENANT ANCHOR.** The same draft put its matched-tenant trigger
  on `users_id` — the table's own anchor, nothing to compare against. That is the unfalsifiable-fence
  tell from the UPSTREAM bullet, arriving by a different route: the author knew a D3 fence was owed,
  could not find the FK-shaped column (because it had been dropped from the schema), and attached
  the fence to the nearest id-shaped column.

Related: [[triage-a-multileg-bypass-leg-by-leg]] · [[read-decisions-from-the-pr-branch-when-the-pr-edits-it]]
