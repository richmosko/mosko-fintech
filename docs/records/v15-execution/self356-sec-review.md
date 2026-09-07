# SELF-356 (P4) — Sec joint-review verdict · GREEN at `f1d8283` · 2026-09-07

Verbatim from Security (sec-c), measured against `main` @ `b4ab24f`. Completes the aal2 per-action table (five actions across four route files) that specifies the close-out Frontend follow-up. Team-lead rulings recorded at execution log E98.

---

P4 / SELF-356 is **GREEN at `f1d8283`**, measured against `main` @ `b4ab24f`. **CLEAR TO MERGE from Sec's side: YES, no conditions.** The aal2 table's last row is completed below and the follow-up spec is now fully determined. Three notes, none gating.

**md5 `1168f44381d9d0ee3083ac85c22c8181`** — the sixteen blobs of `9e8388a..f1d8283` concatenated in `git diff --name-only` order, read via `git show f1d8283:<path>`.

## 1. Summary

I classified all sixteen paths and graded the one-way door over `115`. Both exit doors pass the disposition as an action-side literal that no client field can reach, nothing else in the diff writes `generation_status`, and the no-ledger prompt is informational by construction. The aal2 row measures as I predicted: `42501` is dead on finalize.

## 2. Paths changed — my own classification, all sixteen

**Server surface (ARCH §4.1), 2 modified + 1 new schema:** `routes/reports/monthly/+page.server.ts` (+122) — the **skip** door · `reports/monthly/[target_month]/commentary/+page.server.ts` (+109) — the **finalize** door · `lib/server/schemas/monthly-report-finalize.ts` (+39).
**Shared module, 1 modified:** `lib/monthly-report.ts` (+23) — `noLedgerDesignated`.
**Components, 3 new + 1 modified:** `NoLedgerDesignatedPrompt.svelte` (+59) · `PendingMonthlyReportItem.svelte` (+77) · `SkipFinalizeControl.svelte` (+103) · `MonthlyCommentaryEditor.svelte` (+109).
**Route page, 1 modified + 1 touched:** `reports/monthly/+page.svelte` (+22/−) · `commentary/+page.svelte` (+1).
**Tests, 6:** the three `.dom.test.ts`, `monthly-report.test.ts`, and the two `load.server.test.ts`.
**No migration, no workflow, no manifest, no `DECISIONS.md`.** No `SUPABASE_SERVICE_ROLE_KEY` added. `git merge-tree --write-tree --name-only origin/main f1d8283` → CLEAN. **Zero `@html` directives** — the one mention in `monthly-report.ts` L57 is the comment forbidding it, re-verified at **this** sha rather than carried from my P2/P5 reads.

**Head note:** PR #651's head is still `f1d8283`, so my verdict is at the PR head as it stands today. I will re-verify your predicate after the update-branch, as before.

## 3. Broken

None.

## 4. Bubble up

**✅ THE aal2 TABLE'S LAST ROW — measured, and it confirms the prediction.** `115`'s statement order is `for update` at **L433**, then `update pfin.monthly_report` L448, `insert into pfin.monthly_report_account_snapshot` L568, `update` L617. **The lock is first**, so a below-aal2 caller is refused there with zero rows and never reaches the `109` INSERT that could otherwise raise `42501`. Both P4 doors carry an identical `mapFinalizeError` (`42501`→403, `P0001`→400, default→500), duplicated in the two route files.

**The completed spec for the follow-up:**

| route · action | RPC | refusal shape | `42501` | mapping today | fix |
|---|---|---|---|---|---|
| P3 · save | `112` | zero rows → `P0001` | **dead** | `P0001`→400, copy omits step-up | widen copy · comment the dead branch |
| P5 · generate | `113` | empty lock → INSERT `WITH CHECK` | **LIVE** | **none → 500** | **add mapper, keep `42501`→403** |
| P5 · regenerate | `114` | zero rows → `P0001` | dead | **none → 500** | **add mapper** |
| **P4 · skip** | `115` | zero rows → `P0001` | **dead** | `P0001`→400, copy omits step-up | widen copy · comment the dead branch |
| **P4 · finalize** | `115` | zero rows → `P0001` | **dead** | `P0001`→400, copy omits step-up | widen copy · comment the dead branch |

**Five actions, not four** — the follow-up brief should say five, and P4's two doors carry **duplicate** mappers in two files, so the copy edit lands twice unless they are extracted. ⚠ **`generate` remains the only action where `42501` is live**; that branch must survive the change. Caveat restated: the `113`/`114`/`115` shapes are source reads of the migrations, not walked below-aal2 calls.

**GREEN — the disposition cannot come from the client on either door, and I checked this at the schema as well as the call site.** `skipFinalizeSchema` carries **only** `target_month`; `authoredFinalizeSchema` is `z.object({}).strict()` — **literally empty**, so no client field reaches the finalize door at all. The RPC calls pass the disposition as a hardcoded literal: `p_commentary_disposition: 'skipped'` (listing, L305) and `'authored'` (commentary, L311). There is no path by which a caller selects which door they came through.

**GREEN — nothing else flips status.** The only `generation_status` occurrences added by the diff are test fixtures; the `update()` calls are SvelteKit's `use:enhance` form refresh, not DB writes. `115` remains the sole writer of the transition.

**GREEN — the no-ledger prompt is informational by construction, not by convention.** `NoLedgerDesignatedPrompt.svelte` L6: *"this renders informationally beside the finalize affordances; it never disables them."* It gates nothing, so it cannot be a bypass — there is nothing to bypass.

**NOTE-1 — a cross-surface inconsistency with P8, and P8 has the better shape.** `noLedgerDesignated` degrades to **`false`** on a composition failure, in both routes (*"degrading noLedgerDesignated to false"*). That collapses "could not determine" into "no problem" — the exact pattern `StaleConstituentBadge`'s own header warns against (*"`false` would be silently indistinguishable from 'confirmed healthy'"*), and which P8 deliberately avoided by keeping `null` distinct. **Low impact here**: the prompt is informational and non-blocking, so the cost is an absent hint rather than a wrong control. But the two surfaces now handle the same "unknown" question with opposite disciplines, ten files apart. **No action required**; worth one line if either file is next touched.

**NOTE-2 — the listing loader now composes one full report per pending draft, per page load.** `Promise.all` over `draftRows` calling `fn_render_monthly_report` for each, purely to compute the no-ledger hint. Bounded by `108`'s one-live-draft-per-month index, so N = months with an open draft — small today, but **unbounded over time for a user who never finalizes**. It is RLS-scoped, so a tenant can only amplify against themselves; the residual is that one tenant's listing load can consume N compositions of DB CPU on a shared instance. You noted a per-pending-row cost note exists in the P10 file, so this is **disclosed rather than hidden** and I am not raising it as a defect — I am confirming the amplification factor is **N compositions per page load**, so whoever sizes it has the number rather than an impression.

**NOTE-3 — on the one-way door and the disabled-Finalize guard, stated precisely because "one-way" raises the stakes.** The brief's framing is right: the disabled button is UX and the DB refusal is the control. Posting the form directly with unsaved editor changes finalizes the draft with the **last saved** commentary and silently loses the unsaved edits. **That is not a security control failure** — no privilege is crossed and the tenant acts on their own row — and it is **recoverable**, since `114` supersedes a final and opens a new draft. The reason I am recording it anyway: the frozen artifact is still written, and the recovery leaves a `superseded` row behind, so the audit trail shows a report finalized with incomplete commentary. On any other surface I would not mention it; on a door described as one-way it is worth having on the record.

**Verify-hook, read live from the ADR body at `main` @ `b4ab24f`.** §10 catalogued-instance ledger: **count = 3**, RT-22 / RT-26 / RT-27, unchanged by this diff — nothing added, removed, reordered or renumbered; no layer attribution moves; no Lock text quoted, so axis (iii) has nothing to grade. **No drift to surface.** The CI-fenced RT set remains a different set and I did not reconcile them.

**VERDICT — GREEN. CLEAR TO MERGE: YES, no conditions.** The aal2 follow-up spec is complete at **five actions across four route files**, with `generate`'s live `42501` the one thing that must not be cleaned away. ⚠ Re-run `git merge-tree` in the same turn as the merge, and send me the post-update-branch head so I can re-verify the predicate — my CLEAN read is scoped to `b4ab24f`.
