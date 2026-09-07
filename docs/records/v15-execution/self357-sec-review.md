# SELF-357 (P5) — Sec courtesy-read verdict · GREEN at `81541ac`, the aal2 follow-up re-scoped · 2026-09-06

Verbatim from Security (sec-c), measured against `main` @ `8c2e058`. Team-lead ruling (merge; the aal2 follow-up re-scoped per-action from Sec's table and made a pre-condition of the V1.5 close-out, not a post-milestone item) recorded at execution log E93. Sec's view on the auth-admin user-deletion platform item is carried into the close-out batch entry verbatim.

---

P5 / SELF-357 is **GREEN at `81541ac`**, measured against `main` @ `8c2e058`. **CLEAR TO MERGE from Sec's side: YES.** But the aal2 pattern grade came back worse than P3's and **changes the booked follow-up's scope** — the single most important line in this report is that the follow-up as currently written will leave P5 unfixed while believing it covered it.

**md5 `bf7d7d67f121eba4dccb14fbd9026d30`** — the seventeen blobs of `b781c05..81541ac` concatenated in `git diff --name-only` order, read via `git show 81541ac:<path>`.

## 1. Summary

I verified your head claim independently, classified all seventeen paths, graded P5's own surface clean, and ran the standing aal2 pattern grade. P5's two form actions have **no error mapper at all** — every RPC failure, including a live `42501`, collapses to a 500. Nothing on P5's own surface is a defect; the finding is the missing mapper and what it means for the follow-up.

## 2. Paths changed — my own classification, all seventeen

**Server surface (ARCH §4.1), 1 new + 1 modified:** `routes/reports/monthly/+page.server.ts` (+211) — listing loader + the two form actions, the security-load-bearing file · `routes/+layout.server.ts` (+33/−?) — the pending-draft count.
**UI, 3 new + 1 modified:** `GenerateMonthlyReportControl.svelte` (+90) · `RegenerateReportControl.svelte` (+109) · `reports/monthly/+page.svelte` (+165) · `routes/+layout.svelte` (+36) — the pending badge.
**Tests, 5 new:** the two control `.dom.test.ts` (+91/+60) · `layout-pending-monthly-report-count.server.test.ts` (+83) · `reports/monthly/load.server.test.ts` (+242).
**Seven `+1`-line test edits** (`cash-flow`, `us-equity`, `per-account`, `holdings-section`, `page-headline-basis`, `page-staleness`, `taxes-decomposition`): each adds `pendingMonthlyReportCount: 0` to a shared layout-data fixture. **Inert** — I read one to classify rather than assuming from the line count.
**No migration, no workflow, no manifest, no `DECISIONS.md`.** No `SUPABASE_SERVICE_ROLE_KEY` added. `git merge-tree --write-tree --name-only origin/main 5bbae2a` → CLEAN.

**Your head claim — verified, not relayed.** `git diff --stat 81541ac 5bbae2a -- <the seventeen>` is **empty**; `git diff --name-only origin/main 5bbae2a` is **exactly seventeen**. The verdict carries to the PR head.

## 3. Broken

None.

## 4. Bubble up

**⚠ THE PATTERN GRADE — and the answer is neither of the two shapes you asked me to look for. P5's actions have NO error mapper.** Both `generate` and `regenerate` end with the identical three lines:

`if (rpcError || typeof reportId !== 'number') { return fail(500, { errors: { _form: ['Something went wrong. Please try again.'] } }); }`

Every RPC failure — `42501`, `P0001`, `23514`, anything — becomes a **500 with "Something went wrong."** So there is no dead `42501` branch to comment and no copy to widen; **there is nothing there.** Combined with last turn's measurement that `113`'s aal2 refusal raises a **live** `42501`, the concrete outcome is: **a below-aal2 user clicking Generate gets a 500.** Wrong status class (a client auth condition reported as a server fault), no recovery path, and it pushes an auth condition into 5xx monitoring where a real server fault would be indistinguishable. `114`'s `P0001` — "no final report for this month," genuinely reachable from a second tab or a stale page — is a 500 too.

**⚠ THE CONSEQUENCE FOR THE BOOKED FOLLOW-UP, which is why this is the headline.** It is scoped as *"the copy widening and the dead-branch comment get fixed once across the three routes."* **Neither half applies to P5.** You cannot widen copy on a branch that does not exist, and there is no dead branch to annotate. **If the follow-up ships as written, P5 is left exactly as it is by a change that believes it covered three routes** — the worst outcome, because the item then closes.

**The per-action table you asked for, so the scope is measured rather than assumed:**

| route · action | RPC | refusal shape | `42501` reachable? | mapping today | fix needed |
|---|---|---|---|---|---|
| P3 · save | `112` | zero rows → `P0001` | **no** (dead branch) | `P0001`→400, copy omits step-up | widen copy; comment the dead branch |
| P5 · generate | `113` | empty lock → INSERT → `WITH CHECK` | **YES — live** | **none → 500** | **add a mapper** |
| P5 · regenerate | `114` | zero rows → `P0001` | no | **none → 500** | **add a mapper** |
| P4 · finalize | `115` | zero rows | no *(predicted)* | to measure | to measure |

⚠ **Caveat, stated rather than left implicit:** the `113`/`114`/`115` refusal shapes are source reads of the migrations, not walked below-aal2 calls. The P4 row is a prediction I will settle at its dispatch. The P5 rows are read directly off the shipped action code and are not in doubt.

**Disposition — I am NOT gating, and here is the reasoning so you can overrule.** It fails closed; no write occurs and there is no exposure. The fix is a mapper copied from a shape that already exists three times on this tree (`settings/owner-id`, `settings/tax-brackets`, P3's `commentary`), so it is small — but it is *adding* code, not editing copy, which is why it belongs to the follow-up with a corrected scope rather than to a merge condition I impose on a courtesy read. **If you would rather hold #649 for it, that is defensible and I will not argue.** What I do ask for either way is that the follow-up be re-scoped before it is written.

**P5's own surface — GREEN on every anchor.**
- **RT-25 — confirmed in source, matching QA's `PGRST202` proof from the other direction.** Both calls pass exactly one parameter: `rpc('fn_open_monthly_report_draft', { p_target_month })` and `rpc('fn_regenerate_monthly_report', { p_target_month })`. No as-of is constructed, passed or derivable anywhere in the file.
- **The structural month picker on `generate` is a real control, not a formality.** `legalMonths` is recomputed server-side from `candidatesFor([], serverTodayAsOf())` and the posted month must be a member — so a tampered `target_month` is refused at the app layer before the RPC, independently of the DB.
- **Listing loader:** `.in('generation_status', ['final','draft'])` excludes `superseded` structurally rather than filtering after the fact; RLS-scoped with no `.eq('users_id')`, which is the correct posture.
- **Pending count:** `select('report_id', { count: 'exact', head: true })` filtered to `draft`, RLS-scoped, guarded by `if (user)`, and **fail-soft to 0** — an under-count, which is the safe direction (it cannot invent work or surface another tenant's).
- **A10 (SELF-366) in scope — closes correctly.** One live draft per month is surfaced as *copy, not an error*: `113` is idempotent, returns the existing draft's id, and the action redirects to the commentary editor. There is no error path to mis-signal. `final → superseded` runs through `114`. ✓
- **Zero `@html`** across all seventeen files. `typeof reportId !== 'number'` is a genuine return-shape check, not just a truthiness test.

**NOTE, no action — an asymmetry worth one line.** `generate` has the structural month picker; `regenerate` validates the regex and then accepts **any** month. Not a defect: `114` resolves the caller's own `final` row under RLS, so a foreign or nonexistent month refuses at the DB, which is the real fence. But the two actions sit ten lines apart with different app-layer postures, and that reads as an oversight to the next editor rather than as a decision.

**On the `DELETE /auth/v1/admin/users/{id}` platform item — my security view, and it is mostly a warning about the tempting fix.** Three points. **(1)** It fails safe, so there is no integrity concern — agreed. **(2)** But the consequence is that **deleting any real user is impossible**, which is a right-to-erasure and account-closure obligation, not only an ops annoyance; it belongs on the compliance side of the ledger rather than filed purely as a platform bug. **(3) ⚠ The obvious fix is the dangerous one.** Granting the auth admin role privileges on `pfin` to let the FK cascade run would hand a **non-tenant-bound role a cross-tenant write channel into financial data** — a privileged-context surface, ADR-011 D1 joint-review-mandatory, and **I would veto a blanket `GRANT … ON SCHEMA pfin` or table-level grants to that role.** Acceptable shapes are a scoped, audited erasure routine that deletes in the right order under a controlled identity, or FK/cascade adjustments that need no new grant at all. **Route the proposed fix to me before it is built**, not after — this is one where the wrong fix is much cheaper to write than the right one.

**Verify-hook, read live from the ADR body at `main` @ `8c2e058`.** §10 catalogued-instance ledger: **count = 3**, RT-22 / RT-26 / RT-27, unchanged by this diff — nothing added, removed, reordered or renumbered; no layer attribution moves; no Lock text quoted, so axis (iii) has nothing to grade. **No drift to surface.** The CI-fenced RT set remains a different set and I did not reconcile them.

**VERDICT — GREEN, courtesy. CLEAR TO MERGE: YES.** The FLAG is routed with a corrected follow-up scope, and the one thing I ask is that the follow-up be re-scoped from "widen copy across three routes" to a per-action fix list before it is written. ⚠ Re-run `git merge-tree` in the same turn as the merge — my CLEAN read is scoped to `8c2e058`.
