# SELF-360 (P8) — Sec courtesy-read verdict · GREEN at `9e8388a`, one FLAG routed · 2026-09-06

Verbatim from Security (sec-c), measured against `main` @ `b4ab24f`. Team-lead ruling (merge; the `userSuppliedAsOf` fix takes shape (a) inside the close-out Frontend PR alongside the aal2 fixes; the frozen-report two-account walk is a P10 pre-condition; the "recorded Sec dispositions falsified without touching the record" pattern goes to memory and the close-out report) recorded at execution log E97.

---

P8 / SELF-360 is **GREEN at `9e8388a`**, measured against `main` @ `b4ab24f`. **CLEAR TO MERGE from Sec's side: YES.** One FLAG routed, no exposure. The design work on the frozen-report branch is the best thing in this diff and is also the branch QA could not walk — flagged below.

**md5 `0b48eaf94483262e38ae17f8413bf73a`** — the six blobs of `81541ac..9e8388a` concatenated in `git diff --name-only` order, read via `git show 9e8388a:<path>`.

## 1. Summary

I verified your head predicate independently, classified all six paths, and graded the P8 anchors. The tri-state unknown handling and the frozen-report member set are both right. One finding: P8 becomes the **first production caller** of `userSuppliedAsOf`, which falsifies a recorded Sec disposition and a claim P8 makes about the tree.

## 2. Paths changed — my own classification, all six

**Server surface (ARCH §4.1), 1 modified:** `reports/monthly/[target_month]/+page.server.ts` (+168) — the staleness resolution; the load-bearing file.
**Components, 1 new + 1 modified:** `MonthlyReportStaleBanner.svelte` (+74) · `MonthlyReportView.svelte` (+117/−).
**Route page, 1 modified:** `[target_month]/+page.svelte` (+3). **Tests, 2 modified:** `MonthlyReportView.ssr.test.ts` (+139) · `load.server.test.ts` (+357).
**No migration, no workflow, no manifest, no `DECISIONS.md`.** No `SUPABASE_SERVICE_ROLE_KEY` added. `git merge-tree --write-tree --name-only origin/main 3ce70d9` → CLEAN.

**Your head predicate — verified.** `git diff --stat 9e8388a 3ce70d9 -- <the six>` is **empty**; `git diff --name-only origin/main 3ce70d9` is **exactly six**.

## 3. Broken

None.

## 4. Bubble up

**⚠ FLAG — P8 is the FIRST production caller of `userSuppliedAsOf`, and two artifacts now assert otherwise. No exposure; routed, not gating.** `+page.server.ts` L84 imports it and L222 calls `userSuppliedAsOf(row.data_as_of)`. Measured on both sides:

- **At `origin/main` @ `b4ab24f`**, every reference to `userSuppliedAsOf` outside `asOf.ts` is in a **test file** (`time/asOf.test.ts`, `schemas/asOf.test.ts`). **Zero production callers.**
- **At `9e8388a`**, exactly one production caller exists: P8's loader.

**What that falsifies:**

1. **`asOf.ts` L49–51 — a recorded Sec disposition.** It reads: *"CORRECTED (V1.3 pre-flight sitting D-7, Sec bounded consult, HIGH confidence, 2026-08-22): no route wires a client-supplied `as_of` anywhere in the tree … and `userSuppliedAsOf` has no caller outside its own schema module (`schemas/asOf.ts`) and its tests."* **That is now false.** The D-7 disposition — *"FIRST VALIDATED CAPABILITY, NOT a live path"* — was reached **because** the factory had no production caller. The premise is gone and the artifact recording it still asserts it.
2. **P8's own L217 — false when written.** It justifies the call as *"the same factory every other 'already have a real DB date' call site in this tree uses."* **There were no other call sites.** The convention appealed to has no members; P8 is establishing it, not following it.

**What it does NOT do — stated plainly so this is not read as bigger than it is.** The value passed is `row.data_as_of`: DB-derived, from the tenant's own report row under RLS. **No client-supplied as-of reaches anything, and RT-25 is intact.** The function only validates `YYYY-MM-DD` and returns the string. There is no exposure and nothing fails open.

**Why it still matters.** `asOf.ts` states the brand's purpose as *"the brand fences the PROVENANCE of production dates."* A DB-derived date now wears the user-supplied brand, so **the type no longer discriminates provenance** — the next reviewer grepping "does any client as-of reach production?" finds a production call site literally named `userSuppliedAsOf` and must read the argument to learn it is safe. That is the fence losing its ability to answer the question by name, which is the whole reason a brand exists.

**Fix, two shapes.** **(a) Preferred:** route DB-derived dates through a correctly-named factory (`storedAsOf` / `dbDerivedAsOf`) so `userSuppliedAsOf` stays genuinely caller-free and the brand keeps discriminating; correct `asOf.ts`'s comment to record that the client path remains unreached. **(b) Minimum:** keep the call, but correct **both** comments — `asOf.ts` must record the new production caller and why it is not a client path, and P8's L217 must drop the "every other call site" claim rather than leave a false convention citation in a server-surface file.

**⚠ Pattern, not incident — this is the second time in this chain.** ADR-068 D7 carried a stale premise about `service_role` supersession; now `asOf.ts` carries a stale reachability disposition. **Both were Sec-recorded conclusions that a later change falsified without the recording artifact being touched.** Worth a line in the close-out: when a change makes a recorded Sec disposition untrue, updating that record is part of the change, not a follow-up. I am not proposing a mechanism for it here.

**GREEN — the tri-state unknown handling, and it is a prior Sec catch still holding.** `StaleConstituentBadge` renders **three** visibly distinct states: `true` + non-empty list → the disclosure; **`null` → a separate, quieter "Staleness unknown" note**; `false` → zero-footprint. So a degraded staleness read is **visible, never silently rendered as healthy** — the SELF-220 round-2 catch, institutionalised in the component's own header (*"`false` would be silently indistinguishable from 'confirmed healthy'"*). `isStale`/`staleItems` are **required props with no default** (Sec F3(B)), so a caller that forgets fails at typecheck rather than at runtime as a silent clean. P8 feeds `is_stale: null` — not `false` — when the account set is unknown, which is the correct direction.

**GREEN — commentary and the owner header are never marked.** The owner header renders plainly at L167–168 with an explicit comment at L165 that no badge goes near it; commentary renders plainly at L318. No staleness affordance on either.

**GREEN — and worth commending: the frozen-report member set is taken from the SNAPSHOT, not from live accounts.** For a `final` row the banner's account set comes from `monthly_report_account_snapshot` (`109`) filtered to `monthly_report_id`, so the banner can only name accounts **the report actually covers**. Had it used live accounts, an old frozen report would name accounts added after generation — an information-consistency defect on a compliance artifact. This is the right call and it was not the obvious one.

**GREEN — markers derive from server reads.** All resolution happens in the loader (`loadStaleness`, `resolveStaleAccountIds`, `loadCashflowContributors`), all RLS-scoped, all fail-soft in the safe direction (unknown, not healthy). The view receives already-resolved values. **Zero `@html` directives** — the two mentions in `MonthlyReportView.svelte` are comments forbidding it, re-verified at `9e8388a` rather than carried over from my P2 read.

**⚠ NOTE — QA's disclosed gap lands on the branch with the most design content.** The walk did not exercise **a final (frozen) report**, which is exactly the `109`-snapshot branch I commended above; nor the multi-account list join. So the branch whose correctness I am most confident about **on reading** is the one with no behavioural observer. **Not gating** — the reasoning is sound and the code is short — but a two-account fixture with one finalized report would close both gaps in one walk, and it is worth having before P10 rather than never.

**NOTE — "no new data path" is not quite accurate.** P8 adds a **new direct read of `monthly_report_account_snapshot` (`109`)** plus an account-name read, alongside three reuses (`loadStaleness`, `resolveStaleAccountIds`, `loadCashflowContributors`). All RLS-scoped, all the tenant's own rows, so **no security consequence** — but the surface characterisation in the brief should say "no new write path", since a reader checking "did P8 touch the data surface?" against that phrasing would conclude wrongly.

**Verify-hook, read live from the ADR body at `main` @ `b4ab24f`.** §10 catalogued-instance ledger: **count = 3**, RT-22 / RT-26 / RT-27, unchanged by this diff — nothing added, removed, reordered or renumbered; no layer attribution moves; no Lock text quoted, so axis (iii) has nothing to grade. **No drift to surface.** The CI-fenced RT set remains a different set and I did not reconcile them.

**VERDICT — GREEN, courtesy. CLEAR TO MERGE: YES.** The `userSuppliedAsOf` FLAG is routed to Frontend; I'd take shape (a) but (b) is acceptable. ⚠ Re-run `git merge-tree` in the same turn as the merge — my CLEAN read is scoped to `b4ab24f`.
