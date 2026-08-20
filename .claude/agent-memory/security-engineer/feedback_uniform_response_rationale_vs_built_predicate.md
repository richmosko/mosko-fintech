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
