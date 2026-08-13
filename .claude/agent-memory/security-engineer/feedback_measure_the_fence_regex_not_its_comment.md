---
name: measure-the-fence-regex-not-its-comment
description: Run a fence/test regex against a written list of candidate evasion strings before accepting the coverage its own comment claims — comments over-claim and the over-claim retires the reader's suspicion
metadata:
  type: feedback
---

Never accept a fence's **description** of its own coverage. Write the candidate evasion strings to a
file and match the actual predicate against them. Cite the command and the miss list.

**Why:** at the SELF-218 / migration `067` joint-review, the paired battery's zone leg carried the
predicate `prosrc !~* 'date_trunc|interval|::\s*timestamp'` under a comment asserting it caught "the
parenthesis-free evasions `'today'::date` and `'now'::timestamp`". Measured against nine candidates,
it caught only `'now'::timestamp`. `'today'::date` matches nothing in that alternation — `::date` is
not `::timestamp`. Worse than a plain gap: a **false coverage claim inside a test description retires
the next reader's suspicion at the exact point suspicion was the control.** The same pass had
*replaced* a clock-token deny-list with the "stronger structural" regex rather than supplementing it,
so `current_date` / `now()` / `localtimestamp` — the three tokens the migration header explicitly
instructs future editors not to introduce — ended up with **no watcher at all**.

**Where this defect actually originates** (attribution recorded 2026-08-12 at Architect's own ask):
the control's **owner had a working leg and removed it on a reviewing role's recommendation**, which
was framed as *stronger* while in fact covering a **different class** — date arithmetic, not clock
reads. Nobody was careless; the owner deferred to a reviewer, and "stronger" was never tested against
the retired leg's own member list. **So watch cross-role recommendations that swap one control for
another**: ask what the new form covers that the old did not, and — the question that actually catches
it — what the OLD form covered that the new one does not. A strengthening subtracts nothing.

**The remediation shape that worked** (accepted at `4260c18`, same review): restore the retired leg
**alongside** the structural one rather than merging them; state in the leg's description that the two
are *corroborating, not substitutive*, with a concrete example the structural leg lets through
(`where x <= current_date` has no `date_trunc`/`interval`/`::timestamp`); record the token set's
**provenance as a union of named sources in the file header** so it cannot silently lose members
again; and pin a **negative control** — the legitimate literal the fence must NOT match. Ask for that
shape by name next time.

**How to apply:** whenever a review surface includes a grep/regex fence, a `prosrc` assertion, or a CI
token gate — build the candidate list first (include the parenthesis-free special literals
`'today'::date` / `date 'today'` / `'now'::date`, both spellings of the zone-aware type, and bare
`date ± integer` arithmetic), then `grep -E` the real predicate over it. Also ask whether the new form
**replaced** rather than **extended** an older fence: replacement is where coverage silently
disappears while the diff reads like a strengthening. Related: [[sec-lock-cross-check-catches-my-own-misreads]].
