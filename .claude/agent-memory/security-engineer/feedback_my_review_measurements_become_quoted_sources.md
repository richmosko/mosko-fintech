---
name: my-review-measurements-become-quoted-sources
description: A measurement I publish in a review record gets quoted VERBATIM into migration headers and ADRs — so its COUNT and ENUMERATION must be as careful as its claim, because I am the upstream of the inherited-citation drift class I exist to catch.
metadata:
  type: feedback
---

**Rule: anything I state as an "independent measurement" in a PR review record will be quoted
back at me verbatim inside a later migration header or ADR. Hold the count and the enumeration
to the same standard as the finding.**

**Why:** on PR #480 / SELF-237 I wrote a ⭐ measurement: *"the price-pick kernel block,
extracted and whitespace-normalized from ALL SIX copies (019/049/050/056/059×2/076) → one
identical hash."* Three months of nothing, then `078`'s header quoted that sentence **byte-exact**
as its scope justification. On re-measure (2026-08-17) the enumeration listed **seven** items
while saying **six**, and the true count was **eight** — `056` carries **two** kernel blocks, not
one. The substantive claim (ONE hash) held, and held over all eight. **Right content, wrong
count — which is exactly the ADR-011 D4 CHANGELOG inherited-citation class, with me as the
source.** Architect did not drift; they cited me faithfully. No amount of care at their end
would have surfaced it.

**⚠ THE SEQUEL, which is the reusable half: my CORRECTION carried a NEW derived count error.**
The replacement text I authored read *"EIGHT blocks across **seven** files (019 / 049 / 050 /
056×2 / 059×2 / 076)"* — a parenthetical enumerating **six** files. Architect held it, applied my
own rule back at me, and was right (`6 files, 8 blocks, 1 hash`, re-measured). The eight and the
enumeration were **measured**; the "seven" was **typed**, sitting beside them borrowing their
authority. **A correction is not exempt from the rule it enforces — re-derive every integer in
the replacement text, not just the one being fixed.** Four artifacts in that chain carried a wrong
count before the property itself was ever in doubt.

**The root confusion, stated so it is recognisable next time: the original "six" was the right
number attached to the WRONG NOUN** — six *files*, not six *copies*. A count with no stated noun
invites exactly this. See [[state-what-the-count-is-over]] in the project index; this is that
failure inside my own text.

**Corollary — a hash DIGEST is a property of the pipeline, not of the code.** My digest and
Architect's differed (different whitespace normalization) while both returned
`count(distinct) = 1`. **Only the invariant is a fact.** Never commit a literal digest into an
artifact or a fence; assert `count(distinct md5(...)) = 1`. Two pipelines agreeing on the
invariant is a STRONGER result than either digest, and "reconciling" them would destroy the
independence for no gain.

**Third instance, and the fastest turnaround yet — SAME BRANCH, ~one hour (SELF-241 / PR #520).**
Not a count this time: a **QUOTATION ATTRIBUTED TO THE WRONG FILE.** In my F-1 finding I wrote
*"§2.2.2 also gates server-side on `> 0` ('covering the negative case too')"*. The phrase is real
and exact — but it lives in `nonre-allocation.ts`, the CLIENT mirror, describing the server gate.
The server file `nonReAllocation.ts` **never says it** (`grep` → no match, exit 1). Frontend
committed my sentence into a durable header comment as *"its own words"*, pointing a future
reader at a file that does not contain the words. **The substance was true; only the pointer was
wrong** — the POINTER/CONTENT split of the ADR-011 D4 inherited-citation class, arriving inside a
single review cycle instead of across months.

**Two things make this the sharpest version of the rule.** First, the two files differ by
CASE ALONE (`nonReAllocation.ts` vs `nonre-allocation.ts`) — a near-homograph pair where the eye
supplies the match, and the whole point of the mirror pattern is that they say similar things.
**Where a server module and its client mirror share a name modulo case, ALWAYS grep the phrase in
BOTH before attributing it to either.** Second, I had already run the Sec-Lock cross-check on the
ADRs — **and not on my own prose.** The cross-check is not a step reserved for other people's
text; the finding message itself is a citing artifact.

**Fourth instance — SELF-247 / PR #558: my un-scoped count got RE-HUNG on a narrower noun, and
the tempting repair destroys the claim.** My D-7 consult text read *"→ four loaders, all
`serverTodayAsOf()`"* — four was over **every** route loader under `api/src/routes`. Backend's
new module header quoted it as *"all four **§2.2** route loaders"*. §2.2 has **two**. The number
was right about the tree and wrong about §2.2, and a reader who "fixes" `four → two` silently
shrinks a tree-wide sweep into a §2.2-only one — the load-bearing half. **Repair by restoring the
scope, never by adjusting the integer.** Same file also cited a bare `` `nav-boundary.ts` `` while
**two** files carry that basename in different directories (`lib/` and `lib/server/queries/`);
both cited claims live in the `lib/` one. The case-twin lesson generalises: **PATH twins count
too — grep the basename repo-wide before attributing.**

**How to apply:**
- When publishing a measurement, state **the command** and let the number be derivable from it,
  or state the number and **re-derive it once before sending**. A hand-typed enumeration beside
  a machine-computed hash is the asymmetry that bites: nobody re-checks the list because the
  hash looks authoritative.
- **Count the occurrences, not the files — and say which you counted.** One file can hold N
  copies. `grep -l` answers "which files" and gets silently read as "how many".
- **Re-derive integers inside my own correction text**, then hand the corrected text over with
  standing authorisation to fix any residual discrepancy in place. A third round trip over a
  derived integer costs more than it protects.
- At any later review that quotes my own prior words, **re-run the measurement**, do not
  verify the transcription. A verbatim-quote check passes on a faithfully-copied error.
- When I find one, **name it in the same message as the findings**, supply commit-ready
  replacement text attributing the correction to me, and leave the original record unedited —
  the historical record is the provenance. See [[sec-lock-cross-check-catches-my-own-misreads]]
  and the ASSERTS-vs-NAMES distinction in ADR-011 D4.
- Corollary for **rulings**, not just measurements: my ruling (1) said *"ALL copies"* and the
  implementation delivered *"all LIVE copies"*. That reinterpretation was correct (applied
  migrations cannot be edited). **Say explicitly that I accept it**, or a future reader finds a
  gap between my words and the code and cannot tell which is authoritative.
