# SELF-355 (P3) — Sec joint-review verdict · GREEN at `b781c05`, one FLAG routed · 2026-09-06

Verbatim from Security (sec-c), measured against `main` @ `a4b5800`. Team-lead ruling on the FLAG (merge; the aal2 copy fix is a family-level follow-up across the RPC-held write paths, not a P3-only patch) recorded at execution log E90.

---

P3 / SELF-355 is **GREEN at `b781c05`**, measured against `main` @ `a4b5800`. **CLEAR TO MERGE from Sec's side: YES.** One real FLAG is routed and does **not** block — I considered AMBER and explain below why I chose not to gate on it, so you can overrule.

**md5 `b1580242f891fcb9b0b80378e4fdb29b`** — the eleven blobs of `6a8eadd..b781c05` concatenated in `git diff --name-only` order, read via `git show b781c05:<path>`. That is what this verdict covers.

## 1. Summary

I verified your head-vs-frozen-sha claim independently before relying on it, classified all eleven paths, and graded every anchor the brief names plus the `''`-vs-NULL question you flagged. The write path is sound: the pick list excludes every privileged field, the 4000 bound counts code points on both sides, and the GUC is never referenced. One finding — the aal2 step-up refusal reaches the user as "the report may not exist."

## 2. Paths changed — my own classification, all eleven

**Server surface (ARCH §4.1), 1 new + 1 modified:** `reports/monthly/[target_month]/commentary/+page.server.ts` (+224) — the loader + save action, the security-load-bearing file · `reports/monthly/[target_month]/+page.server.ts` (+18/−11) — **pure extraction**, verified: the removed local `TARGET_MONTH_RE` and `parseTargetMonth` are byte-identical to the shared versions now imported, so P2's input gate is unchanged.
**Server schema, 1 new:** `$lib/server/schemas/monthly-commentary.ts` (+76).
**Shared module, 1 modified:** `$lib/monthly-report.ts` (+36) — the extracted `parseTargetMonth` + `CommentaryValues`.
**Client mirrors, 2 new:** `$lib/schemas/monthly-commentary.ts` (+38) · `$lib/validation/monthlyCommentary.ts` (+55).
**Components, 1 new + 1 modified:** `MonthlyCommentaryEditor.svelte` (+412) · `TextAreaField.svelte` (+6) — an optional `disabled` prop defaulting to `false`, so every prior call site is behaviourally unchanged.
**Route page, 1 new:** `commentary/+page.svelte` (+48). **Tests, 2 new:** `MonthlyCommentaryEditor.dom.test.ts` (+246) · `commentary/load.server.test.ts` (+375).
**No migration, no workflow, no manifest, no `DECISIONS.md`.** No `SUPABASE_SERVICE_ROLE_KEY` added; RT-26 allowlist untouched, no ADR-016 D1 amendment owed. `git merge-tree --write-tree --name-only origin/main 3381278` → CLEAN.

**Your head-vs-frozen claim — verified, not relayed.** `git diff --stat b781c05 3381278 -- <the eleven>` is **empty**, and `git diff --name-only origin/main 3381278` is **exactly those eleven**. My verdict at `b781c05` carries to the PR head.

## 3. Broken

None.

## 4. Bubble up

**⚠ FLAG — the aal2 step-up refusal reaches the user as "the report may already be finalized, or no longer exists," with a 400 and no step-up path. Fails closed; routed, not gating.** `108`'s `authenticated` SELECT and UPDATE policies carry the `025` aal2 backstop clause, and `112`'s first statement is a `SELECT … FOR UPDATE` checked against both. So a **totp/passkey-enrolled caller on a below-aal2 JWT finds zero rows to lock** — `112` then raises `P0001`, which `mapSaveError` maps to a **400** with the missing-or-finalized copy. Two consequences:

- **The user is told the wrong thing and has no recovery.** Their natural response — regenerate the report, or conclude data was lost — is wrong; the actual remedy is re-verifying the session. An MFA step-up the user cannot discover is an availability failure of the control.
- **The `42501 → 403` branch is dead code on this route.** It was correctly copied from the direct-write Lock 14 convention (`settings/owner-id`, `settings/tax-brackets` — I checked, tax-brackets uses `.insert(...)`, a direct table write where `42501` genuinely fires). **P3 is the first Lock 14 write path whose refusal is an RPC-held `FOR UPDATE` lock, where the aal2 backstop is a 0-row effect the error mapper never sees.** So this is a genuine divergence in mechanism, not an inherited family item — but the branch will read to the next maintainer as "step-up is handled here."

**Recommended fix, and it is one sentence of copy, not a redesign:** widen the `P0001` message to name the third possibility — *"…the report may already be finalized, no longer exist, or your session may need re-verification — try signing in again."* That preserves the non-disclosure the current copy earns (still uniform across cross-tenant, missing and below-aal2) while giving the recovery path, and it needs no way to distinguish the cases. Add a one-line comment on the `42501` branch recording that it cannot fire here. **A route-side pre-check is the wrong fix** — it would need an enrollment read to know whether the backstop even applies, and would put a second copy of the aal2 rule in app code.

**Why I am NOT gating on it, stated so you can overrule.** It fails closed — no write occurs, no exposure. The fix has real design content (exact user copy, and whether PM wants step-up surfaced at all on this route), which belongs to Frontend/PM rather than to me imposing wording at a merge gate. If you would rather hold the merge for the copy change, that is a reasonable call and I will not argue it.

**Your specific question — `''` vs NULL — answered against the DDL, not the comments. It is inert on both counts.**
- **`108`'s CHECKs:** the commentary constraints are **length-only** — `monthly_report_commentary_cash_len` is `check (commentary_cash is null or length(commentary_cash) <= 4000)`, and the same shape for the other three. **There is no not-blank CHECK** (unlike `106`'s owner-header column). `''` passes trivially. No interaction.
- **P4 "never-authored" semantics:** that signal is carried by `commentary_disposition`, a **separate** column with a three-value vocab (`null` / `'authored'` / `'skipped'`), and `108`'s status CHECK requires it non-null for `final`/`superseded`. **The text columns carry no attestation meaning**, so writing `''` into untouched sections does not overload a sentinel. `112` sets `commentary_disposition = 'authored'` on every successful call including the all-blank one, with the right reasoning — four empty strings are a legitimate authored state, and `'skipped'` is P4's affordance, not writable here. The one-way `null →` transition is intended: `null` means the author has done neither, and that stops being true on first save.
- **The residual I probed for and did not find:** a never-visited draft (NULL columns, NULL disposition) is distinguishable from a saved-all-blank draft (`''` columns, `'authored'`). And although P2 renders NULL and `''` identically (`{sub.text ?? ''}`), the attestation discriminator is preserved in the column, so the frozen artifact's compliance signal is not degraded. **No finding.**

**4000-code-point bound — GREEN, and the direction is the opposite of P7's, correctly.** The server schema uses `Array.from(s).length <= 4000`, which counts **code points**, matching `108`'s `length()` exactly. Its header states why `.length` would be wrong here: 3,996 ASCII + 4 astral characters is 4,000 code points (DB-legal) but 4,004 UTF-16 units, which a `.length` bound would wrongly refuse. ⚠ Worth noting explicitly because it is the inverse of P7, where UTF-16 counting was fine precisely because it was **stricter** than the DB. Both files reasoned correctly for their own case; a copy-paste of either rule into the other would have been wrong. `112` deliberately adds **no second bound**, so app and DB are one equality rather than three facts that can disagree.

**Mass assignment — GREEN, graded on the pick list rather than on `.strict()`.** The action hand-builds its parse input from four `form.get(...)` calls, so `.strict()` cannot fire; per the family convention the **pick list is the fence**, and it contains exactly the four commentary fields — **no `users_id`, no `target_month`, no `report_id`, no `generation_status`, no `commentary_disposition`.** `target_month` comes from the route param through the shared regex gate; the tenant is resolved by `112`'s RLS-scoped lock with no tenant parameter anywhere.

**The audit-source GUC — GREEN, and this is the C3 fence's premise.** `set_config` and `app.report_generation_source` appear **zero** times across all eleven files. The route cannot set the provenance GUC, so `113`/`114`/`115` remain its only setters and `111`'s `'cron'` derivation is unreachable from this surface.

**Refusal on a `final` report — GREEN.** `112`'s lock predicate includes `generation_status = 'draft'`, so a final row is never among the lockable rows and the illegal statement is never constructed; the refusal surfaces as `P0001` → 400 with generic copy. The `108` immutability trigger remains the fence for direct-PostgREST writes — two controls, disjoint callers, neither redundant. **No constraint or function name reaches the client** on any branch; the `P0001` collapse of "no report" and "not a draft" is non-disclosure by construction, and I re-derived it against the built predicate: there is no `.eq('users_id')` anywhere, so the uniform-response argument is genuine rather than voided.

**No markdown, no `{@html}` — GREEN.** Zero `@html` directives across all eleven files; the single textual mention is the pre-existing comment in `monthly-report.ts` that I already graded at P2, unchanged by this diff.

**NOTE, no action — a small divergence from P7's convention.** The action coerces with `String(form.get('cash') ?? '')`, so a multipart post carrying a `File` in a commentary field stringifies to `"[object File]"` and is **saved as commentary**. P7 used the better shape (`typeof raw === 'string' ? raw : null`). No security impact — it is the user's own text, escaped on render, length-bounded — but it is garbage-in where P7 refuses, and the two Lock 14 paths now differ. Worth one line if the file is next touched.

**Authorship — same class as P2/P7, and I discharge the re-read.** `commentary/+page.server.ts` and `$lib/server/schemas/monthly-commentary.ts` sit on Backend's ARCH §4.1 surface, authored by Frontend under dispatch and flagged in their own headers as owing a Backend/Sec re-read at the RT-11 joint review. **This is that re-read; I have no objection to the authorship and no security finding arising from it.** Backend still has not read them — your call, not a Sec gate.

**Verify-hook, read live from the ADR body at `main` @ `a4b5800`.** §10 catalogued-instance ledger: **count = 3**, RT-22 / RT-26 / RT-27, unchanged by this diff — nothing added, removed, reordered or renumbered; no layer attribution moves; the branch quotes no Lock text, so axis (iii) has nothing to grade. **No drift to surface.** The CI-fenced RT set remains a different set and I did not reconcile them.

**VERDICT — GREEN. CLEAR TO MERGE: YES**, with the aal2 copy FLAG routed to Frontend/PM as follow-up. ⚠ Re-run `git merge-tree --write-tree --name-only origin/main <head>` in the same turn as the merge — my CLEAN read is scoped to `a4b5800`.
