---
name: hazard-mechanism-vs-reachability
description: A hazard has two independently-falsifiable halves — MECHANISM and REACHABILITY — and verifying the mechanism is the habit that lets an unreachable hazard through; an accepted overclaim then invites embellishment, and its retraction fans out past the file that was corrected
metadata:
  type: feedback
---

**I accepted a fence on a threat that could not happen, and then I made the threat bigger.**
SELF-325 / `087`: the migration justified a new `auth.uid() IS NULL` guard by arguing that an
RLS-exempt no-JWT caller would otherwise mint GLOBAL (all-tenants-readable) `pfin.asset` rows. I
verified that carefully — `016:198` (`users_id uuid default auth.uid()`), `016:272`
(`asset_global_symbol_uniq … where users_id is null`), `016:283` (`asset_select … using (users_id is
null or …)`) — and returned ACCEPT. **Every one of those measurements was correct and the conclusion
was still false**, because the caller never reaches the asset INSERT: `003:93` reads
`users_id uuid not null default auth.uid()`, so statement (1) raises `23502` two statements earlier.
Architect caught it, measured it by removing the guard from a copy, and corrected the file. One grep
would have closed it and I never ran it.

**The rule, and it is ONE rule with two halves.** A hazard claim has a **MECHANISM** (*if control
X were reached, this is what would go wrong*) and a **REACHABILITY** (*can control X be reached in
that state at all*). They are independently falsifiable, and **verifying the mechanism is precisely
the habit that lets an unreachable hazard through** — the mechanism is the interesting half, it is
where the domain knowledge lives, and confirming it feels like having verified the claim. Same shape
as the POINTER-vs-CONTENT rule for citations ([[read-decisions-from-the-pr-branch-when-the-pr-edits-it]]):
checking one is the habit that lets the other through. **Both halves, every time.**

**How to apply, mechanically:** when a rationale says *"a caller reaching statement (N) would …"*,
trace statements 1..N−1 and ask what each one does in that same state. Cheapest form: grep the NOT
NULL / CHECK / policy on every column written before the one at risk. An argument about the last
write in a sequence is an argument about the whole sequence.

**The second failure is the one I would not have predicted: an accepted overclaim invites
EMBELLISHMENT.** Having accepted the premise, I volunteered a "consequence the rationale does not
name, **which strengthens it**" — that `asset_user_name_uniq` is `where users_id is not null`, so
those minted global rows would carry no name uniqueness either, allowing unbounded duplicates. Also
true as a mechanism, also unreachable, and I handed the overclaim **more weight than its author had
given it**. ⚠ **The tell: I was reasoning about a hazard downstream of writes I had not traced.**
Volunteering a strengthening to someone else's threat model is a signal to go back and check
reachability, not a sign of thoroughness — a reviewer who adds to a claim has stopped auditing it.

**Third: a retracted rationale FANS OUT past the file that gets corrected.** The fix commit corrected
the overclaim at **four** sites in the migration (posture block, body comment, RAISE string,
`comment on function`) and left **three** in the paired pgTAP battery — a block comment, and the
assertion messages of both new legs, one of which reproduced the retracted sentence word for word.
That message is what a future engineer reads **at the moment the leg reds**, so it would send them at
a threat that does not exist ([[a-red-whose-message-names-the-wrong-defect]]). This is ADR-011
Decision 4's own PR #476 bullet (1) — *a rationale inherited without its attached retraction* —
recurring one artifact over. **When clearing a retraction, negative-grep the retracted phrasing
across EVERY file in the branch, tests included, and say so: "my filter is a claim about my filter."**

**Fourth, the residual worth keeping — a guard can survive its own rationale's collapse.** I still
accepted the guard, on a smaller claim it actually earns: it fails **early and legibly** (a named
cause instead of a `23502` pointing at a column), and it **pins the requirement locally**, in the
function whose whole model is evaluate-as-the-caller, instead of borrowing it from a distant table's
NOT NULL. If that column ever loses NOT NULL, or statement order changes, the guard becomes the
fence. **Don't demand removal of a control whose justification was overstated — re-state what it is
worth and accept it at that size.** Related: [[enumeration-and-watcher-stop-one-short]] (never demote
a control to make its prose true).

**And check what the paired watcher now proves.** `(l1-10)` was `throws_like` pinned to the guard's
own message text, so removing the guard reds on the **message** (the `23502` doesn't match), not on a
write occurring — the correct instrument for a legibility guard, but relax it to a bare `throws_ok`
and it goes vacuous, because the call throws either way. Its companion `(l1-11)` counted orphan rows
and returns 0 with or without the guard: **non-detective, while its message read "fail-closed, no
partial write."** Under a corrected model, re-derive what each existing leg still detects — a leg
authored under the overclaim keeps passing and stops meaning what it says.

**The delivery note said this had been fixed and it had not.** The dispatch told me `(l1-11)` was
"documented as a non-detective companion rather than left looking like coverage"; searching the whole
file for `23502|not null|non-detect|defense in depth|changes the error|legib` found nothing
expressing it. Surface that as a discrepancy against the ref rather than absorbing it — see
[[review-the-delivery-note-against-the-ref]].

**The same rule, applied EARLY, is what turns a would-be fence-exceeded finding into a clarifying
amendment — and the load-bearing word was in a code comment.** V1.3 pre-flight D-7: Architect routed
me a possible ADR-011-Decision-19 breach on the strength of `asOf.ts`'s own header calling
SELF-238/240 "the FIRST **live** path" for a client-supplied `as_of`. MECHANISM was real (a validated
`as_of` factory + `.strict()` schema ship in `main`). REACHABILITY was not: `grep -rn
"userSuppliedAsOf" api/src` returns the factory, the schema module and two test files — **zero
routes** — and all four route loaders call `serverTodayAsOf()`. A shipped **capability** is not a
live path. ⚠ **When the finding hinges on one adjective, grep that adjective's referent before
anything else** — here "live" was the entire difference between "amend for clarity" and "a merged
milestone exceeded a ratified fence." And note where the false word lived: **in the source comment**,
which is where the next reader will find it, so the correction routes to the code owner, not only to
the ADR.

**⚠ THE INVERSE, AND IT IS THE ONE THAT SHIPS: A CAPABILITY ACCEPTED AS UNREACHABLE LATER ACQUIRES
ITS FIRST CALLER, AND THE ARTIFACT RECORDING THE ACCEPTANCE STILL SAYS IT HASN'T (P8 / SELF-360,
2026-09-06).** `api/src/lib/server/time/asOf.ts` carried a dated Sec disposition — *"CORRECTED (V1.3
pre-flight D-7, Sec bounded consult, HIGH confidence): no route wires a client-supplied `as_of`
anywhere in the tree … and `userSuppliedAsOf` has no caller outside its own schema module and its
tests."* The capability was accepted **because** it had no production caller. P8's loader became the
first one. **No exposure** — the argument passed was a DB-derived `row.data_as_of` — but the premise
of the acceptance was gone and the record still asserted it.

**How to catch it: a disposition that rests on ABSENCE needs a caller census re-run at every new
surface that touches the module.** `git grep -n <symbol> <ref> -- <src>` on **both** the pre-change
ref and the change ref, filtering tests, and compare. Absence is not a property you verify once.

**Second half, and it is the cheaper tell: the new caller JUSTIFIED ITSELF BY A CONVENTION THAT DID
NOT EXIST.** Its comment read *"the same factory every other 'already have a real DB date' call site
in this tree uses"* — measured, there were **zero** other call sites. **A "we already do this
everywhere" claim in a new file is a claim about the tree; grep it before accepting it**, because it
is exactly the sentence that makes a reviewer skip the check. Same family as
[[a-preference-reads-as-a-ruling-and-a-caveat-sets-the-axis]] (measure the SIBLING's convention
first).

**Third: a BRAND launders provenance the moment a differently-sourced value wears it.** The module
stated the brand *"fences the PROVENANCE of production dates."* Once a DB-derived date is passed
through `userSuppliedAsOf`, the type no longer discriminates, and a reviewer grepping *"does a
client as-of reach production?"* finds a hit named for the thing they fear and must read the
argument to clear it. **Preferred fix is a correctly-named second factory, not a comment** — a
comment restores the record, only the name restores the fence.

**⚠ Pattern across one wave, worth naming as a class: TWO recorded Sec dispositions were falsified
without their recording artifacts being touched** (ADR-068 D7's `service_role` supersession premise;
this one). **When a change makes a recorded Sec conclusion untrue, updating that record is part of
the change, not a follow-up.** Related: [[read-the-whole-cell-before-diagnosing-doc-drift]].

**⚠ THE SAME ERROR IN THE OPPOSITE DIRECTION — OVER-READING FRAGILITY (P10 / SELF-362, 2026-09-07,
twice in two turns).** This file's whole subject is *not* mistaking a capability for a live path.
The mirror-image failure costs the team just as much, and I committed it twice in one review:

- **NOTE-1.** I flagged a watcher's soundness as resting on "an unguarded ordering property" — that
  a future edit moving the read after the write would silently make it compare `54` against `54`.
  Seeing the full expression, the two reads are **arguments to the asserting call itself**
  (`is(_get('plan') - _get('curr_test'), 5, …)`), and Postgres evaluates arguments before invoking
  the function. **The ordering is guaranteed by evaluation semantics, not by line placement.**
- **Constraint 3.** I flagged "the first executable call to a pgTAP internal in the tree" and asked
  whether the dependency could be avoided. QA measured: pgTAP exposes **no** public accessor for
  those counters, and **`finish()` itself calls the same `_get()`** — so all 110 files already carry
  it transitively, and a rename would break the whole battery loudly, together. **The dependency was
  made explicit, not introduced.** My question invited a search for an alternative that does not exist.

**Both were the safe direction (wasted effort, not missed exposure) — which is exactly why they are
easy to keep making.** No one pushes back on a reviewer asking for more hardening.

**How to apply — before writing "fragile", "unguarded" or "first of its kind", ask:**
1. **What actually enforces it?** Language/engine semantics (argument evaluation, transaction
   boundaries, type systems) are *stronger* than placement conventions. Read the whole expression,
   not the line.
2. **Is the risk borne alone or in company?** A dependency shared with the framework's own public
   API fails loudly and collectively; a dependency unique to this call site fails quietly and
   alone. Only the second is worth hardening.
3. **Would the "safer" alternative exist?** Ask for it as a QUESTION ("can this be done without
   X?"), never as an implied requirement — I framed it as the latter and it read as a demand.

**And correct it in the same channel, promptly**: both corrections went back before the close-out
record was written, so the *corrected* forms are what landed. An over-read that reaches a permanent
record teaches the next reader to treat a robust property as fragile — see
[[supplied-verbatim-text-ships-unfiltered]] and
[[clearance-conditions-must-absorb-my-own-recommendations]].
