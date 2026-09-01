---
name: prove-derived-text-against-its-source
description: Rebuild a regenerated block from its source plus named substitutions so fidelity is true by construction; and a period inside quotation marks claims the sentence ended there
metadata:
  type: feedback
---

Two mechanical techniques for text that must faithfully derive from a source —
regenerated catalog comments, and quotations inside ADRs and briefs.

## 1. RECONSTRUCT, don't edit toward

When regenerating a block from a source (e.g. a `comment on` re-issued from the
migration that first authored it), **rebuild it programmatically from the source plus
N named substitutions**, each asserted to match **exactly once** before applying.

> Because the file is rebuilt *from* the source rather than edited *toward* it,
> "byte-identical outside the substitution spans" is **true by construction**, not by
> inspection — **there is no third region to have missed.**

This is strictly stronger than a containment proof, and it has a second benefit:
**it needs no byte counts at all**, which removes a whole failure class (below).

**Why:** migration `068`, 2026-08-12. First pass used a containment proof citing
unchanged prefix/suffix byte counts. Sec independently measured **different numbers
and both were correct** — Sec counted the **rendered catalog string**, the file counted
**SQL source text including per-line quote wrappers**. Two scopes, one unlabelled
number, and the disagreement looked like an error in one of them.

- ⚠ **A count without its scope invites reconciliation of two things that were never
  the same measurement.** The best fix was not to label the scope but to **restructure
  the proof so no count was needed.**
- ⚠ **Character-level diffing is the wrong instrument here.** It fragmented two logical
  substitutions into 22 micro-regions by matching incidental substrings ("the ", "and ")
  inside replaced text. Technically accurate, useless — a region count characterises
  only what changed.

## 2. A period inside the quotation marks claims the sentence ended there

**Why:** Sec caught ADR-053 quoting `054` as *"…MUST set the GUC first."* where the
source reads *"…MUST set the GUC first, **in the same transaction**."* Every quoted word
was real, which is what makes this class survive a verbatim check — and the dropped
clause was the load-bearing one for that very ADR.

**How to apply:**
- **Terminal punctuation inside the marks is a completeness claim.** Partial quotation
  with no closing period is honest; the same words with a period are not.
- Checked against the two neighbouring quotes in the same passage: one genuinely ended
  where quoted, one was partial without a terminal period. **Both sound.** The
  discriminator separates them cleanly and is cheap enough for any verbatim sweep.
- ⚠ **Check the neighbours, not just the flagged line.** Fixing one instance of a class
  and leaving its sibling is this project's most repeated failure — see
  [[structural-fence-must-cover-the-same-class]].

## 3. ⚠ VERBATIM CARRY IS SAFE FOR CLAIMS AND UNSAFE FOR INDEXICALS

The techniques above make copied text **byte-faithful**. Byte-faithful is not
meaning-faithful: **a word whose referent is "this file" re-points when the bytes move,
with no edit and therefore no diff to review.**

**Why:** `072`, 2026-08-14 — mine, shipped. `071`'s header reads *"`p_users_id` was
struck for the FOURTH time in this family (049 R2 / 051 / 067 / **here**)"*, correct in
`071`. I built `072` by copying `071` and amending — the discipline that protected the
rest of that multi-KB comment — and **"here" silently became `072`**. The enumeration
now reads 049 / 051 / 067 / 072, **omits `071`**, and still claims "fourth". No runtime
effect; the catalog half needs a comment-only migration to correct.

**This is a new route into the copied-count failure, and worth distinguishing from the
usual one: the count did not go stale. The ENUMERATION moved, because it contained an
indexical.** Every prior instance of this class was a number that aged; this one never
aged and was wrong the instant it was copied.

**How to apply:**
- **Before carrying a block, grep it for indexicals** — *here*, *this file*, *this
  migration*, *above*, *below*, *the same PR*, *now*. Each is a reference resolved by
  location, and copying changes the location.
- Prefer text that names its referent: *"struck at `071`"* survives any copy; *"struck
  here"* does not.
- The house form, agreed with PM and now their AC vocabulary too: **an ordinal is a
  claim that goes stale; an enumeration of instances stays checkable; an indexical is
  worst, because it re-points without an edit.**

⚠ **A re-pointed indexical is INVISIBLE IN THE DIFF — that is the whole difficulty, and
it means the diff is the wrong instrument for finding one.** Second live instance, `085`
(2026-08-19): `084`'s `user_taxonomy` catalog comment ends *"…falsified by `041` on the
INSERT half, corrected here."* The correction was made at **`083`** (the comment-only
supersession migration); `084` carried the word forward verbatim and re-pointed it to
`084`. I caught it only because I was about to harden it — my `085` re-emission had
"corrected at `084`" in it, and I checked which migration actually made the correction
before shipping. **The old→new diff showed that span as UNCHANGED both times.** So:
**grep the carried span for indexicals as a separate pass; never expect the diff to
surface one.** Fix visibly — `085` states the drift rather than repairing it quietly,
because a silent repair of a re-pointed word is indistinguishable from having introduced
one.

## 4. ⚠ A QUOTED FIGURE IS ADOPTED, NOT MERELY TRANSMITTED

Section 3 says verbatim carry is unsafe for indexicals. It is unsafe for **figures**
too, and for a different reason: an indexical breaks when the *bytes* move; a figure
breaks when the *world* was never as the source described it.

**Why:** `078`, 2026-08-17 — mine, and it survived my own review. Sec's PR #480
joint-review record measured the price-pick kernel across *"ALL SIX copies
(019/049/050/056/059×2/076)"*. I quoted it **byte-exactly with correct attribution**,
so every fidelity check I ran passed. Sec re-measured at the joint review and found
their own figure wrong — `056` carries **two** kernel blocks, not one, so the truth is
**eight blocks across six files**. My header carried a false number with a flawless
citation.

> **A verbatim check can only prove you copied the words. It cannot prove the words
> were true.** Attribution transfers *provenance*, never *correctness* — the moment you
> put someone's number in your artifact, it is asserted in your voice too.

**The symmetric half, from the same review:** Sec's correction then said *"EIGHT blocks
across SEVEN files"* against its own six-file enumeration. I measured before committing,
held the edit, and it was re-issued. **Both directions of the discipline fired in one
review**, which is the argument for it — the reviewer catching my inherited figure, and
me catching the reviewer's derived one.

**How to apply:**
- **Any number you quote, measure.** Cheap here: extract each kernel block from
  `(select ep.price` to `limit 1)` and count per file. One command settled all of it.
- ⚠ **A count and its own enumeration must be checked against each other** — that alone
  caught Sec's second error, since *"seven files (a/b/c/d/e/f)"* is self-refuting
  without any knowledge of the domain.
- **State what the figure is over.** Both errors were scope collapses: *copies* vs
  *files*, and later *migration text* vs *live catalog definitions*. See
  [[count-over-history-vs-live-definitions]] and [[state-what-the-count-is-over]].
- Do **not** silently fix a reviewer's verbatim text. Measure, hold, report the one word
  — then commit what they re-issue.
- ⚠ **The same rule covers a reviewer's REMEDIATION, and the routing is the part that is
  easy to get wrong.** Confirmed 2026-08-30 (SELF-344): Sec's fix for a wrong file-pointer
  was a literal token swap; I saw that it would leave two referents for the same notation
  in adjacent sentences and proposed a better wording. Raising it was right — **but the
  variant goes to SEC for concurrence, not to team-lead, and not into the commit.** The
  reviewer owns their finding's remediation end to end (the SELF-252 lesson: nobody
  'helpfully' rewords a reviewer's remediation). Surface the concern, name the variant,
  execute whichever the reviewer answers.
- Corollary that makes it worth raising at all: a reviewer triages findings
  **independently**, so a neighbour they correctly cleared can still be made ambiguous by
  the fix landing beside it. That interaction is invisible from the reviewer's seat and
  visible from the author's — which is why holding it is a real contribution and
  silently acting on it is not.

⚠ **The third thing verbatim carry is unsafe for: text naming a PROCEDURE that has since
been BANNED.** At `083` I re-emitted `009`'s catalog comment with one anchored span
corrected; the untouched remainder described the seeding mechanism as the CLI reset
subcommand, banned outright since the 2026-08-14 wipe. **The repo's own mechanical guard
refused the commit** — and it was right: the live catalog was naming a forbidden
procedure. A claim can stay true while the *action it names* becomes prohibited, so a
fidelity check passes and the text is still wrong to ship. **Before re-emitting any
carried span, re-read it for named procedures, not just for claims and figures.**
⚠ And when you then explain the fix, **describe the banned phrase — do not quote it**:
prose written *about* a grep-shaped fence is the densest concentration of the tokens that
fence hunts, and quoting it trips the guard a second time.

## 5. ⚠ A PROVENANCE LABEL ADDED LATER IS ALWAYS ABOUT AN EARLIER REF

Sections 3 and 4 cover text that becomes false when copied. This is text that is false
**the moment it is written**, and it looks like diligence.

**Why:** `085`'s battery, 2026-08-19. QA pasted a raw TAP tail into the file as evidence,
unlabelled. A later commit corrected two sentences in that same file; QA then authored a
`REF <sha> / CONSUMER <tool>` label for the tail — naming the **pre-correction** sha,
because that is the run they had. Committing it would have put provenance for a run that
never exercised those bytes **into** the corrected file: byte-accurate label, wrong
subject. I caught it by re-md5'ing their file against the committed blob.

**The deeper trap, and it is why the fix is not "just use the new sha":** a label naming
the current sha must live in a commit **beyond** it. So it can only be made true by a
caveat explaining its own provenance — a TAP tail carrying an epistemology footnote.
**Evidence that has to argue for itself is weaker than evidence with no label at all.**
Team-lead's ruling, and it moved me off my own lean.

**How to apply.**
- **Label evidence in the SAME commit that produces it**, or accept it unlabelled and put
  the ref and consumer somewhere outside the tree (a PR body) where being *about* another
  ref is the normal case.
- If a late label is genuinely wanted, it needs three clauses, and the third is the one
  that matters: **REF** (the sha the run exercised) · **CONSUMER** (the tool and image tag)
  · **a note that the annotation postdates the run it describes.**
- **Book it as a NEXT-TOUCH rider, never as its own commit.** Moving a reviewed ref for
  redundant evidence prices wrong — the ADR-058 two-word rider is the precedent that
  landed cleanly by this route.
- ⚠ **Re-measure a delivered file at COMMIT time, not at copy time.** Two teammates
  revised deliveries in place after I had verified them; only a re-`md5` at commit caught
  it. See [[verify-the-bytes-you-commit]].

Related: [[watcher-not-fence-for-by-construction-properties]] · [[diff-filter-strips-comment-lines]] · [[scope-the-invariant-before-writing-it]] · [[cited-precedent-transmits-its-retracted-half]] · [[count-over-history-vs-live-definitions]]
