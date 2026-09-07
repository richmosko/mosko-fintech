# V1.5 close-out follow-up (PR #653: aal2 refusal mappers + `storedAsOf`) — Sec joint-review verdict · GREEN at `7d359c4` · 2026-09-07

Verbatim from Security (sec-c), measured against `main` @ `df7d015`. Discharges the FLAGs at `self355-sec-review.md` (P3), `self357-sec-review.md` (P5), `self356-sec-review.md` (P4) and `self360-sec-review.md` (P8). Team-lead ruling recorded at execution log E109. ⚠ The reachability classification (`42501` live on generate, dead on the other four) remains Sec's source read of `112`–`115`; no MFA-enrolled fixture exists on the dev DB, so it is a classification, not a measurement — stated here so it is never cited as proven.

---

PR #653 is **GREEN at `7d359c4`**, measured against `main` @ `df7d015`. **CLEAR TO MERGE from Sec's side: YES, no conditions.** All three judgment calls accepted. One honest limit and one error of my own named below.

**md5 `23e926215bd1268c9403927032a146a7`** — the ten blobs of `df7d015..7d359c4` concatenated in `git diff --name-only` order, read via `git show 7d359c4:<path>`.

## 1. Summary

I graded this against the tree rather than against my own spec, checked the one thing that would have made the follow-up fail its own purpose, and verified the redirect footgun in every affected action rather than the one you sampled. Both halves land as specified: five actions covered, and the asOf fix is shape (a) with a non-vacuous census leg.

## 2. Paths changed — my own classification, all ten

**New shared module, 1:** `lib/server/monthly-report-write-error.ts` (+71).
**Server surfaces (ARCH §4.1), 3 modified:** `reports/monthly/+page.server.ts` (+79/−) — generate · regenerate · skip · `[target_month]/commentary/+page.server.ts` (+58/−) — save · finalize · `[target_month]/+page.server.ts` (+12/−) — the P8 `storedAsOf` switch.
**Factory + its tests, 2 modified:** `lib/server/time/asOf.ts` (+70/−) · `asOf.test.ts` (+63/−).
**Components, 2 modified:** `MonthlyCommentaryEditor.svelte` · `PendingMonthlyReportItem.svelte` — **one line each**, pure type widening `boolean` → `boolean | null` (Optional C).
**Tests, 2 modified:** the two `load.server.test.ts`.
**No migration, no workflow, no manifest, no `DECISIONS.md`.** `git merge-tree --write-tree --name-only origin/main 7d359c4` → CLEAN. §10 ledger read live at `df7d015`: **count = 3**, RT-22/26/27, unchanged; no attribution moves; no Lock text quoted. No drift to surface.

## 3. Broken

None.

## 4. Bubble up

**✅ THE CHECK THAT MATTERED MOST — the follow-up does NOT miss a route.** The shared mapper deliberately excludes P3 (correctly: `112` raises an extra `23514` the other four don't), which is exactly the shape in which a family fix silently drops a member. **I verified P3's local `mapSaveError` separately**: `commentary/+page.server.ts` L213–219 carries the dead-branch comment with the right reasoning, and L229–237 carries the widened `P0001` copy naming re-verification. **All five actions from the table are covered.** This was the specific failure I warned about at the P5 read, and it did not happen.

**✅ The redirect footgun is avoided in all FOUR redirect-throwing actions — I checked each, not the one you sampled.** In both route files the only `try`/`catch` blocks are in the **loaders** (`+page.server.ts` L177/192; commentary L137/139, L146/149, L168/183 — all before the actions). Every `throw redirect` sits after the `if (rpcError)` branch and outside any try: generate L250, regenerate L278, skip L320, finalize L323. A committed write can never be reported as a failure.

**✅ The `42501` branch has a strike-proof watcher.** `load.server.test.ts` carries *"42501 (step-up required) → 403 — the LIVE case among these four write actions"*, injecting `{ code: '42501' }` and asserting `res.status === 403`, with a comment stating the test goes red if the branch is dropped. **That is the watcher for the one thing I said must not be cleaned away**, and it is a real one rather than a note.

**✅ My table is transcribed accurately.** I compared the mapper's header table against my own row by row — the four rows, their refusal shapes, and the "generate is the only live one" attribution all match. No paraphrase drift, and the reasoning for keeping the dead branch (a future direct write on 114/115 would need it in place) is sound rather than decorative.

**✅ The asOf half is shape (a), and the census leg is genuinely non-vacuous — I graded it hard.** `storedAsOf` added; P8's loader switched (`storedAsOf(row.data_as_of)`); the D-7 comment re-corrected with a dated pointer; and the module header now states *why* the separation exists — so the "has this server ever validated an actual client-supplied as_of in production" question stays answerable by grepping one factory's callers. That is the provenance argument, restored by name rather than by comment. On the leg itself: it carries a **precondition** (`expect(files.length).toBeGreaterThan(100)`) that guards against a moved directory or changed extension passing everything vacuously; it **strips comments before matching**, so a mention is not a caller; `EXEMPT` is **two enumerated paths, not a pattern**; the regex is word-boundary anchored; and the failure message names the right repair. **The decisive test: it would have caught P8.** It runs under `npm run test` in `web-tests.yml`, so it has a real trigger rather than being an assertion with no watcher.

**⚠ THE HONEST LIMIT, stated prominently because no walk was possible.** The strike leg proves the **mapper's behaviour given a `42501`** — it injects the code. It does **not** prove that a below-aal2 caller **produces** one on `113`. The reachability column of the table (`42501` live on generate, dead on the other four) remains **my source read of `112`–`115`'s statement order**, unverified against a running below-aal2 session. That is the same evidence base you and I have been working from throughout, and I am not asking to hold the merge for it — but **the follow-up should not be recorded as having *proven* the reachability classification.** If an MFA-enrolled fixture ever exists on the dev DB, one probe per action settles it; until then this is a well-reasoned classification, not a measurement.

**⚠ MY OWN ERROR, named here rather than in a follow-up.** I initially suspected the refactor had **dropped** the `typeof reportId !== 'number'` return-shape guard from `generate` and `regenerate`, because my grep surfaced only `if (rpcError)` on those lines where P5 had a combined condition. Reading the blocks: the check was **split into two** — the mapper for the RPC error, then a separate `if (typeof reportId !== 'number')` → 500. That is **better** than the original combined form, not a regression. Nothing was dropped. A filtered grep is a claim about the filter, and I nearly reported a regression off one.

**The three judgment calls — I accept all three.**
- **`storedAsOf` as the name: accept.** It is parallel in shape to `serverTodayAsOf`/`userSuppliedAsOf`, it says what the value is rather than where it is used, and it is precisely the name that makes the grep question answerable — which is the entire point of shape (a). I have no better suggestion.
- **`logContext` as a second parameter: accept.** Without it the shared mapper's default-branch `console.error` would name no action, degrading incident triage — a real loss for a mapper serving four call sites. **Verified: all four call sites pass hardcoded string literals** (`'reports/monthly generate'`, `regenerate`, `skip`, `'reports/monthly/commentary finalize'`). ⚠ **One standing constraint worth a line in that file's header:** the value is interpolated into a `console.error` template, so it must **stay a literal** — a caller-derived value there would be a log-injection vector. Not a change I require now; a sentence so the next caller does not reach for a variable.
- **Optional C's footprint: accept, and it is smaller than the count suggests.** The two component changes are **one line each**, pure type widenings `boolean` → `boolean | null`. Proportionate to the tri-state it restores, and it closes the cross-surface inconsistency with P8 I noted at the P4 read.

**NOTE, no action.** The cast tally in `asOf.ts` moved 3 → 4 and is now accurate ("three production, one test-only"). It is a live-state count in a comment, it just went stale once and was corrected, and it will go stale again at the next factory. The file's own framing ("all below, enumerable on purpose") makes it self-checking, so I am **not** asking for a change — but by ADR-011 Decision 4's own *"can a reader derive it by looking?"* test the count is derivable, and a derivable count stated in prose can only ever be wrong. Half a line if that header is next touched.

**VERDICT — GREEN. CLEAR TO MERGE: YES, no conditions.** The aal2/asOf follow-up discharges both flags at their specified shapes, covers all five actions, and leaves the one live branch watched. ⚠ Re-run `git merge-tree` in the same turn as the merge — my CLEAN read is scoped to `df7d015`.
