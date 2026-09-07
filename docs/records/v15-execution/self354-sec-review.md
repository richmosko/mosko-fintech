# SELF-354 (P2) — Sec courtesy-read verdict · GREEN at `901e5c6` · 2026-09-06

Verbatim from Security (sec-c), measured against `main` @ `0ffab75`. Team-lead cross-check against the tree (the loader passes `p_target_month` and `p_data_as_of` from the resolved row; the query is scoped to `final`/`draft`; `owner_header_at_generation` is in the select list; the two `{@html` hits in the view are comments forbidding it) recorded at execution log E87.

---

P2 / SELF-354 is **GREEN at `901e5c6`**, measured against `main` @ `0ffab75`. **CLEAR TO MERGE from Sec's side: YES, no conditions.** Nothing found touches a mandatory anchor, so this stays a courtesy read.

**md5 `83b8f4eaad5c23a91ff82fd0cbf20d88`** — the nine blobs of `910148c..901e5c6` concatenated in `git diff --name-only` order, read via `git show 901e5c6:<path>`. That is what this verdict covers.

## 1. Summary

I took my own `--stat`, classified all nine paths, and graded every anchor the brief names. The read path is clean on RT-25 in a stronger form than required, the final/draft split is correct, and the absent-envelope rendering avoids the zero-substitution trap by using an explicit null test rather than a falsy one. Three notes, none of which gates; two are doc-accuracy observations rather than defects.

## 2. Paths changed — my own classification, all nine

**Server surface (ARCH §4.1), 1 new:** `api/src/routes/reports/monthly/[target_month]/+page.server.ts` (+136) — the loader; the security-load-bearing file.
**Shared module (P2/P3), 1 new:** `api/src/lib/monthly-report.ts` (+317) — types and the payload-shape contract. No I/O.
**Render, 1 new + 1 modified:** `MonthlyReportView.svelte` (+452) · `TaxDecompositionTable.svelte` (+16/−3).
**Route + nav, 1 new + 1 modified:** `[target_month]/+page.svelte` (+36) · `api/src/routes/+layout.svelte` (+14).
**Fixtures + tests, 3 new:** `api/src/lib/fixtures/monthly-report.ts` (+327) · `MonthlyReportView.ssr.test.ts` (+250) · `load.server.test.ts` (+316).
**No migration, no workflow, no Dockerfile, no `secrets-manifest.yml`, no `DECISIONS.md`.** No "X only" scope assumed. `git merge-tree --write-tree --name-only origin/main 901e5c6` → CLEAN. This diff adds **zero** `SUPABASE_SERVICE_ROLE_KEY` references, so the RT-26 allowlist is untouched and no ADR-016 D1 amendment is owed.

## 3. Broken

None.

## 4. Bubble up

**⚠ The `{@html}` sweep needs its result stated carefully, because a naive count reads as a finding.** `grep -c "@html"` returns 2 in `MonthlyReportView.svelte` and 1 in `monthly-report.ts`. **All three are comments forbidding it** — the component header (*"no `<input>`/`[contenteditable]`/`{@html}` anywhere in this file"*), a CSS comment (*"never `{@html}`, never markdown"*), and the shared module's field map (*"escaped once by Svelte's default interpolation (INV-1) … never `{@html}`"*). **Zero actual `{@html}` directives in the whole diff.** Commentary renders as `{sub.text ?? ''}` with line breaks via `white-space: pre-wrap` — CSS, not markup. GREEN, and I am spelling out the measurement because the count alone would have been a false positive.

**RT-25 — GREEN, and stronger than the brief requires.** The client's only input is the route param, regex-gated to `^\d{4}-(0[1-9]|1[0-2])$` and normalized to `YYYY-MM-01`; a malformed value is a 400, never a guess. ⚠ **The RPC then receives neither of the client's values:** `fn_render_monthly_report` is called with `p_target_month: row.target_month` **and** `p_data_as_of: row.data_as_of` — both read off the resolved DB row. So even the month is DB-derived, not just the as-of. The client-parsed month reaches only the `.eq('target_month', …)` filter. There is no path by which a caller-supplied as-of reaches the composition.

**Final/draft split — GREEN.** `final` reads `rendered_payload` back verbatim and never composes; a `final` row with a NULL payload is a hard 500 rather than a fail-soft degrade, which is right — `108`'s CHECK forbids that state, so reaching it is a contract violation, not a transient. `draft` composes live through the RPC. `superseded` is excluded from the query entirely (`.in('generation_status', ['final','draft'])`), matching R10 A-8.

**Cross-tenant posture — GREEN.** The query carries no `.eq('users_id')` and relies on RLS, which is the correct posture here (an explicit id filter would void the cross-tenant-existence argument rather than strengthen it). `fn_render_monthly_report` is `SECURITY INVOKER`, so the composition is RLS-scoped to the caller too. **A month belonging to another tenant returns no rows and yields the same 404 as a month that does not exist — no existence oracle.** Error copy is generic throughout; no constraint name or DB message reaches the client.

**Absent envelopes — GREEN, and the trap was avoided rather than missed.** `{#if point.nav_inflation_adjusted === null}` renders `—` in a `.cell-unavailable` span. ⚠ **That is an explicit null test, not a falsy one** — a genuine `0` therefore renders as `$0.00` and is not silently reported as unavailable, which is precisely the failure a `{#if !point.nav_inflation_adjusted}` would have shipped invisibly. I found **no `?? 0`, no `|| 0`, no `Number(...)` coercion** anywhere in the render path; the only `??` is a string default on commentary. The component header states the rule explicitly (*"never `?? 0`, never currency-formatted, never silently dropped"*) and the code matches it.

**Forward-only header — GREEN.** The loader selects `owner_header_at_generation` off the report row; it does **not** read `pfin.owner_identification` live. A header edited in P7 after generation therefore cannot retroactively change an existing report. That is the control, and it is present in the select list rather than inferred.

**`TaxDecompositionTable` modification — GREEN, and I checked the direction.** It converts hardcoded copy into an optional `capitalGainsUnavailableCopy` prop whose **default is byte-identical to the removed string**, so the live `/taxes/decomposition` call site is behaviourally unchanged; the value renders through `{…}` interpolation, so even a hostile override would be escaped. A prop default that silently changes an existing surface is the usual hazard here and this is not one.

**My own supplied text — re-read at the re-confirm, as I owe.** ADR-068 Decision 7's correction landed at #645: `main` now contains *"THE DUAL-ROLE PROOF OBLIGATION SURVIVES THE CORRECTION"* (1 occurrence) and **zero** occurrences of the struck premise. The four `108` legs keep their stated rationale. Discharged.

**NOTE-1 — the loader's own header asserts a review status that contradicts the routing.** It reads *"P2 is Sec joint-review MANDATORY — team-lead's own dispatch."* The brief's ROUTING line and this dispatch both say **P2 is a courtesy read** (P3/P4/P6/P7 are the mandatory four). No practical consequence — I reviewed it either way — but it is a provenance claim in a file header that will be read later as fact. One-word fix whenever that header is next touched. **No action required now.**

**NOTE-2 — `108.owner_header_at_generation` carries no not-blank CHECK.** It is bare `text` (`108` L551), unlike `106`'s source column, which forbids `''` outright. The renderer gates it with a bare truthy test (`{#if header.owner_header_at_generation}`), so `''` displays as unset — **visually identical to NULL, so there is no user-visible incorrectness today**, and `''` is unreachable while `106` is the only writer. I checked this specifically because it is the one bare-truthy test on a payload field in the file. It becomes worth revisiting only if a future writer populates the snapshot from something other than `106`. **No action.**

**NOTE-3 — the new sidebar link targets a route that does not exist yet.** `+layout.svelte` adds `/reports/monthly`, which is P5's listing route; expect a 404 until P5 lands. Disclosed in the comment, consistent with the existing "route now, build later" convention, and a 404 for an authenticated user is not a security concern. Recording it only so a 404 in the walk is not mistaken for a defect.

**Authorship, same class as P7 and noted rather than re-litigated.** `+page.server.ts` sits on Backend's ARCH §4.1 surface and was authored by Frontend under this ticket's dispatch, flagged in its own header. **No security finding arises from it**; the §4.1 consequence that matters is the RT-26 fence's audit scope growing by one file that references no service-role key. Backend has still not re-read it — your call, not a Sec gate.

**Verify-hook, read live from the ADR body at `main` @ `0ffab75`.** §10 catalogued-instance ledger: **count = 3**, RT-22 / RT-26 / RT-27, unchanged by this diff — nothing added, removed, reordered or renumbered; no layer attribution moves; the branch quotes no Lock text, so axis (iii) has nothing to grade. **No drift to surface.** The CI-fenced RT set remains a different set and I did not reconcile them.

**VERDICT — GREEN, courtesy. CLEAR TO MERGE: YES, no conditions.** ⚠ Re-run `git merge-tree --write-tree --name-only origin/main 901e5c6` in the same turn as the merge — my CLEAN read is scoped to `0ffab75`.
