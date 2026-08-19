---
name: gl-taxonomy-split-ratified
description: The 2026-08-18 F/CTO-ratified asymmetric split of user_taxonomy into a storage spine + posting_prototype — ratified but NOT landed; artifacts live only in gitignored temp/.
metadata:
  type: project
---

**F/CTO ratified the two-function split of `pfin.user_taxonomy` on 2026-08-18. As of that session close it is RATIFIED AND UNLANDED — no migration, no `DECISIONS.md` entry.**

**The frame (F/CTO verbatim):** *"domain::asset -> defines a type of account a thing stores it's book value in; domain::cashflow -> defines a GL Journal Entry prototype... list of accounts to debit/credit which sum to 0."* The table conflates a **storage-classification vocabulary** with a **posting-rule vocabulary**.

**Ratified shape (asymmetric / "4a"):** cashflow rows move OUT to a new `pfin.posting_prototype`; `user_taxonomy` keeps its name, ids and asset rows and drops `domain`. Also ratified: original **id values preserved**, via **disjoint reserved ranges, both tables `generated always`**; `element` on the storage table only, `check (element in ('asset','liability'))` for V1; sequencing **rename → split → element** — the asset-domain Cat `'Equity'` → `'Marketable Securities'` rename ships **FIRST** (it removes an ambiguity every later decision is written in), then S1's split, then `element`, with a V1.2-landability flip to S2.

**Why:** the four live FK-shaped referents of `user_taxonomy(id)` partition **cleanly 2/2** along that seam (`022`/`074` asset, `023`/`029` cashflow), so the split is a clean cut — and three of the four domain rules are **app-layer only** today, so the split converts them to structural.

**Why: (the reason this is a memory at all)** the design, the Sec touchpoint and the ADR draft live **only in gitignored `temp/`** — `architect-gl-brainstorm-opening.md`, `architect-gl-split-adr-draft.md`, `sec-gl-split-touchpoint.md`, `brainstorm-taxonomy-vs-gl.md`. **None of it is derivable from the repo until the doc-PR lands.**

**How to apply:** ⚠ **First action in a follow-up session is to check whether the ADR landed** (`grep -n "posting_prototype" DECISIONS.md supabase/migrations/*.sql`). If it did, read it there and **delete this memory** — the repo becomes authoritative. If it did not, the `temp/` files may have been swept and the decisions must be reconstructed from the session record before any migration is authored.

⚠ Two things that will read as bugs and are not: **`Securities Sold Short` is ratified (ADR-031 Amendment 1 item 7) and appears NOWHERE in the tree** — shorts route to Suspense; and after the split **two `element` vocabularies exist** (bucket vs ledger account) which are **not required to agree** — a short is `asset` on one and `liability` on the other. Never "reconcile" them by joining.

Related: [[ratified-name-is-not-a-built-table]] · [[no-concept-exists-check-deferred-decisions]] · [[join-key-decides-failure-direction]]
