---
name: gl-taxonomy-split-ratified
description: The 2026-08-18 F/CTO-ratified asymmetric split of user_taxonomy — the ENTIRE ADR-058 build order is COMPLETE (rename #502/#503, split #507/084, element #510/085; Sec GREEN throughout). Read ADR-058 and the migrations live; this memory is only the pointer.
metadata:
  type: project
---

⚠ **THIS FILE HAS NOW BEEN SILENTLY REVERTED TWICE by a cleanup pass, both times back to a "no DDL yet" claim that was already false.** First instance is recorded below in the split-arc note; second instance was 2026-08-20, when the element-arc Architect's pre-shutdown correction was discarded and this is its reinstatement. **If you find this file claiming the DDL does not exist, do not trust it — grep `supabase/migrations/` for `084` and `085` and correct it again.** The `MEMORY.md` index line was reverted with it, both times.

**ADR-058 authored into `DECISIONS.md` at PR #499 (2026-08-19). THE WHOLE BUILD ORDER HAS SHIPPED:** rename at **#502/#503** (`082`), split at **#507** (`084` — `pfin.posting_prototype` + `posting_prototype_default` live, ids preserved via the offset+maxvalue pair, D3 `#10`/`#13` re-targeted labels-kept), and `element` at **#510** (`085`). ADR-058 Status = **Accepted**, with **Amendment 1 (3 items)**. Sec GREEN on every one. **Read the ADR and the migrations live — do not reason from this file.**

**What `085` did.** `element text NOT NULL`, **no DEFAULT**, named CHECK `in ('asset','liability')`, on **BOTH** `pfin.user_taxonomy` and `pfin.taxonomy_default` (Sec **F4** — provisioning is a column-listed copy, so a default set that cannot hold an element provisions rows that cannot either, and that path is fail-soft, therefore **silent**). Backfill is Cat-grain and total: `cat = 'Liabilities' → 'liability'`, else `'asset'`. **D3 `#10`/`#13`/`#17` amendments rode `084`**, as the Sec pin required.

**Three decisions in `085` a later author will be tempted to undo — each is deliberate and each is argued in the migration header:**
1. **No DEFAULT is deliberate.** A defaulted element classifies silently, and `'asset'` is the **fail-OPEN** direction for the §2.2.2 assets-only row set. The header says a reviewer meeting an unexplained `default` on this column should read it as a defect, not as tidying.
2. **Widening to `'equity'` is a DECISION to be stated, never a repair.** Whoever adds it asserts that a storage class can represent owner capital — which nothing in the V1 seed does — and should say so in their own header.
3. **`fn_subcat_market_value` CAN express `element = 'asset'` and deliberately DOES NOT.** The `081` liability cash route contributes rows the `Σ fn_subcat_market_value(as_of, true) = fn_compute_nav(as_of)` seam invariant counts, so that predicate belongs to the §2.2.2 **consumer**, not the producer. Its catalog comment now says exactly this.

**One-line shape, only so you recognise the ADR when you find it:** `pfin.user_taxonomy` keeps its name / ids / asset rows and drops `domain`; cashflow rows moved to `pfin.posting_prototype` with **original ids preserved**. Ratified order was **rename → split → `element`**, three separate PRs, no bundling.

**How to apply.** Read ADR-058 for every detail (the id mechanism, the `element` value set, the write posture, Sec F1–F11). Follow-ups have tracked homes: **BACKLOG §7.24** + **§5.3** (GL-native P&L, V2) + **§7.13 / §5.7** closure annotations.

⚠ **Sec F2's four row counts are DISCHARGED-BUT-RE-ARMED, not retired** (§7.24 item 12): run before `084`, all four came back zero **over empty tables**, so the precondition now binds **the first import that populates them** rather than the next migration. **Count 4 fails silently.**

**Still owed after the arc closed (2026-08-20):** Backend's dev-DB apply of **`076`–`085`** (dev sat at `075` throughout — every migration was verified on scratch and has never touched that database) · a **§5.2** line for the V2-CRUD **else-branch question** (`085`'s backfill `else` is a judgement: how does a USER-authored Cat acquire its element?) · a four-clause **next-touch rider** on `085`'s battery about labelling a pasted TAP tail · **§7.24 item 3's totals-equality watcher is still UNBUILT** — the seam is asserted and only half-watched.

⚠ **The §2.2.2 consumer re-point is the next issue and carries a Sec BINDING on its review:** the row set and the denominator must derive from the **same element predicate in the same query**, or a paired Σ assertion must prove the rendered rows sum to the denominator. Sec stated they will hold that review to it.

⚠ **Two things that will read as bugs and are not:** `Securities Sold Short` is ratified (ADR-031 Amendment 1 item 7) and appears **nowhere in the tree** — shorts route to Suspense; and **two `element` vocabularies exist** (reporting bucket vs ledger account), **not required to agree** — a short is `asset` on one and `liability` on the other. Never "reconcile" them by joining.

Related: [[ratified-name-is-not-a-built-table]] · [[no-concept-exists-check-deferred-decisions]] · [[join-key-decides-failure-direction]] · [[verify-the-bytes-you-commit]]
