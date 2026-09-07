---
name: uniform-response-rationale-vs-built-predicate
description: A "we return a uniform response to avoid leaking X" rationale must be re-derived against the BUILT query — an explicit tenant predicate makes cross-tenant existence unobservable, collapsing the rationale to the caller's own state, which a sibling verb on the same endpoint may already disclose
metadata:
  type: feedback
---

When a handler returns a **deliberately uniform** response ("same 200 whether the row existed, was
cross-tenant-hidden, or was policy-filtered"), do not evaluate the *stated* information-flow rationale.
Re-derive it against the **query that was actually built**, and check the **sibling verb on the same
endpoint** for the same gate.

**Why:** on SELF-242's `DELETE /api/settings/planning-target`, the stated rationale was *"distinguishing
those would leak cross-tenant existence / step-up state."* But the handler pins
`.eq('users_id', user.id)` — the caller can only ever address its own rows, so a deleted/not-deleted
signal discloses **nothing but the caller's own state**. Cross-tenant existence was never observable.
And the POST handler *on the same file* already returns `403 step_up_required` on the identical aal2
gate, so the step-up half of the rationale contradicted its own sibling. What remained was real but
different: a **write the DB refused was reported to the caller as success** — `200 {ok:true}` while the
row survived, on a financial-settings surface. Not a bypass, so not a veto; a false confirmation plus a
justification that four unbuilt sibling tables were about to copy.

**Two mechanics that make this specific and recurring:**
- **A DELETE has no row payload**, so its tenant fence must be a *query predicate*, not a
  WITH-CHECK-observable field — and once that predicate exists, every "cross-tenant existence" argument
  about the response shape is void by construction.
- **A `USING`-clause refusal is a 0-row effect, not an error.** It never reaches an error-mapper, so a
  handler that maps errors carefully on one verb can silently report success on another. Check whether
  the error-mapping function is actually *reached* on each verb, not merely present in the file.

**⚠ The fix's own test can be blind to the fix.** When the remedy is "ask the DB for a count and report
it", the batteries that verify it **inject the count into the mock** — so they supply the very thing the
`{ count: 'exact' }` option exists to produce, and dropping that option leaves every test green. Ask, of
any outcome-reporting fix: *does a test fail if the handler stops REQUESTING the fact it reports?*
Whether that earns a merge condition depends on the failure's volume — here it fails **loud** (no option
→ `count` null → `deleted` permanently false → every unset shows "Not removed"), so it was a NOTE, not a
condition. **Say which, and why, so a non-blocking finding isn't read as an oversight.**

**A closure worth repeating:** the same review's remedy header was written by Backend in their own words
rather than from my draft, and came back **better** — it derived the POST/DELETE asymmetry from the
`USING`-silently-excludes vs `WITH CHECK`-raises mechanism instead of asserting it as a design choice.
**State the catch criterion and hand over the how; a mechanism the executing agent derives is inherited
as a reason by the next surface, where a precedent is only copied.**

**How to apply:** at any Lock-14 / settings write-path review, for each verb ask (1) what predicate pins
the tenant, (2) which DB gate can refuse *without erroring*, (3) does the sibling verb disclose the same
state anyway. If the answer to (3) is yes, the uniform-response rationale is inconsistent and must be
either fixed (report the outcome — `count: 'exact'` leaks nothing once the tenant is pinned) or
**re-stated correctly in the header**, because the wrong reason gets inherited. FLAG, not veto, when
reachability through the UI is nil but the direct API call reaches it — and say which. Related:
[[rls-delete-select-policy-conjunction-is-conditional]],
[[sec-lock-cross-check-catches-my-own-misreads]].

**⚠ AN aal2 BACKSTOP IN AN RLS POLICY IS A 0-ROW EFFECT, SO AN RPC-HELD `FOR UPDATE` LOCK TURNS
"step up" INTO "the row does not exist" (P3 / SELF-355, 2026-09-06).** `108`'s `authenticated`
SELECT+UPDATE policies carry the `025` aal2 clause; `112`'s first statement is
`SELECT … FOR UPDATE`, checked against both. A totp/passkey-enrolled caller on a below-aal2 JWT
therefore **finds zero rows**, the function raises `P0001`, and the route maps that to a 400 reading
*"the report may already be finalized, or no longer exists."* **The user's natural remedy —
regenerate, or assume data loss — is the wrong one**, and an MFA step-up nobody can discover is an
availability failure of the control.

**The second half, and it is the maintainer-facing one: the `42501 → 403` branch is DEAD on such a
route.** It is correct on **direct-table-write** Lock 14 paths (`settings/owner-id`,
`settings/tax-brackets` — verified, the latter uses `.insert(...)`), where an RLS `WITH CHECK`
failure genuinely raises `42501`. It cannot fire behind an RPC whose refusal is a lock that matched
nothing. A future reviewer asking *"does this route handle step-up?"* reads the branch and answers
yes.

**How to apply.** On any Lock 14 write path, first classify the transport: **direct write** (RLS
`WITH CHECK` → `42501`, mapper works) vs **RPC holding a `FOR UPDATE` lock** (policy refusal → 0
rows → the function's own raise; `42501` unreachable). Then ask **which distinguishable states
collapse into the single refusal**, and whether any of them has a *user remedy* the copy must name.
Non-disclosure and recoverability are not in tension here: widening the copy to name
re-verification as one possibility preserves the uniform response across cross-tenant / missing /
below-aal2 while restoring the remedy — no need to distinguish the cases. **Do not fix it with a
route-side pre-check**: that needs an enrollment read to know whether the backstop even applies, and
puts a second copy of the aal2 rule in app code.

**Disposition taken:** FLAG, routed, **not gated** — it fails closed, and the exact copy is a
PM/Frontend call rather than wording I should impose at a merge gate. Related:
[[an-rpc-held-for-update-lock-binds-only-rpc-callers]] and
[[a-red-whose-message-names-the-wrong-defect]] (a refusal whose message dictates the wrong repair).

**⚠ SHARPER, AND IT IS THE ONE THAT INVERTS A BOOKED FIX (P5 / SELF-357, 2026-09-06).** Asked to
grade the same pattern on a sibling route, I expected one of the two shapes I had already named —
*dead branch* or *mis-signalled copy*. The answer was **neither: the route had NO error mapper at
all.** Both form actions ended in
`if (rpcError || typeof x !== 'number') return fail(500, 'Something went wrong.')`, so a **live**
`42501` (the aal2 backstop on `113`'s INSERT `WITH CHECK`) surfaced as a **500** — wrong status
class, no recovery path, and an auth condition dumped into 5xx monitoring where a real server fault
becomes indistinguishable.

**The lesson is about the FIX, not the defect.** A family-level follow-up had already been booked as
*"widen the copy and comment the dead branch across the three routes."* **Neither half applies to a
route with no branch at all** — you cannot widen copy that does not exist. Shipped as written, that
follow-up would have **closed the item while leaving the worst of the three routes untouched.**

**How to apply. When a finding is generalised into a family fix, grade each member for the
PRESENCE of the thing being fixed before agreeing the fix covers it.** "Same pattern" claims travel
as *"these routes share a mechanism"*; the fix travels as *"edit this construct"* — and a member can
share the mechanism while **lacking the construct entirely**. Produce a per-member table with a
`fix needed` column whose cells are allowed to differ (*widen copy* · *add a mapper* · *nothing*),
never a single scoped sentence. Related: [[a-red-whose-message-names-the-wrong-defect]] (the
tempting repair disables the watcher) and
[[an-enumeration-and-its-watcher-both-stop-one-short]].

**Second-order, worth its own line: a blanket "remove the dead `42501` branch" would have deleted a
WORKING step-up 403** on the one action where `42501` is live. **Absent-vs-dead-vs-live is a
three-value property per ACTION, not per route** — one route can hold two actions with different
answers.
