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
