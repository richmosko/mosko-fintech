# Phase 2 — UX Flow Document: §2.2 Asset Allocation Cluster

**Cluster:** §2.2 — Asset allocation (two-level taxonomy + holding-to-bucket assignment; Non-RE allocation table; US Equity sub-allocation).
**Author:** UX Designer (`phase-2-ux-design` team).
**Status:** DRAFT — flows only. Pre-wireframe. Pre-PM-traceability-consult.
**Phase 2 step:** Step 2 (flow drafting per cluster, dependency order — §2.2 is cluster 3 of 6; depends on §2.4 accounts/holdings + the §2.2.1 taxonomy).
**Date:** 2026-05-28.
**Companions:** `temp/phase-2-flows-2.4-cross-cutting.md` (foundation — accounts, holdings, new-symbol surfacing, `stale-data-marker`), `temp/phase-2-flows-2.1-net-worth.md` (NAV cluster — value-semantics pin, composition table this cluster shares holdings with). Global decision log: `temp/phase-2-decisions-log.md`.

---

## 0. Scope, inputs, and load-bearing constraints

### 0.1 PRD stories in this cluster
- **2.2.1** — Two-level asset taxonomy (Cat × Sub-Cat, six Cats: Cash / Bonds / Equity / Alternatives / Liabilities / Real Estate) + holding-to-bucket assignment UI (per-symbol for Plaid securities; per-account for manual non-securities holdings).
- **2.2.2** — Non-RE allocation table (Sub-Cat rows under Cat-group headers; five columns % Target / % Alloc / $ Target / $ Alloc / $ ReAlloc; RE excluded; Liabilities included as a leverage-management extension).
- **2.2.3** — US Equity sub-allocation (12-row drill-down off the "US - Sector Diversified" Sub-Cat row; same five columns; evaluated against Total US Equity).
- **2.2.4** *(supporting)* — Allocation is the user's; full-household by default. *(Constraint — no scope-filter UI in V1.)*

### 0.2 Load-bearing constraints
- **Assign to the SEEDED taxonomy only; no taxonomy CRUD in V1 (2.2.1).** The user assigns holdings to **existing** seeded Cats/Sub-Cats. **No create / rename / delete Category or Sub-Category affordance** anywhere in V1 — taxonomy CRUD is V2+ (V1 taxonomy edits happen via migration). The assignment UI offers a fixed pick-list, never a "+ new bucket."
- **Visualization only; no rebalance engine (2.2.2 / 2.2.3).** V1 shows over/under-target at a glance so the user decides trades **externally**. **No auto-generated rebalance suggestions, no "buy/sell X" recommendations, no trade execution** — preserving decisional authority. V1 never tells the user what to trade.
- **US Equity is the only drill-down; no Ex-US drill (2.2.3).** V1 ships only the US Equity sub-allocation. **No international/Ex-US sub-allocation table.** Per flag (f), whether drill-down is a general capability is Architect's call, but the only V1-surfaced drill is US Equity.
- **Real Estate excluded from the rebalance view (2.2.2 / flag (d)).** RE is non-liquid (house-fractions can't be sold on demand); it does NOT appear in the Non-RE allocation table. RE's value lives in §2.1.5 composition only.
- **Single full-household allocation; no scope-filter UI (2.2.4 / §7.3).** One aggregated household allocation across all ownership scopes. **No scope toggle / per-scope view.** Own data only. Per-scope allocation views are V2+.
- **Density-first (§1.3).** The owner maintains deliberate two-level taxonomies and reasons at Sub-Cat granularity ("a coarse-bucket tool would be unusable"). Dense tabular precision is the point.
- **Non-silent staleness — D1 (global, F/CTO-ratified; `temp/phase-2-decisions-log.md`).** Already settled: every derived aggregation consuming stale-account data carries the `stale-data-marker`. **Applied to §2.2.2 + §2.2.3 here without re-flagging the scope** (per team-lead). A stale investment account's holdings mark the affected allocation rows + Cat subtotals + totals.

### 0.3 Appendix B §2.2 — Architect Phase-3 dependencies (NOT my surface; they constrain these flows)
- **(a)** Multi-level user-scoped taxonomy data model (Cat × Sub-Cat tables; seed-on-bootstrap; per-symbol assignment storage (AssetDB-style registry); per-account assignment for manual holdings; additive-only forward-compat for V2 CRUD). **UX consequence:** the assignment surface writes to this registry; per-symbol assignments apply across all accounts.
- **(b)** Sub-Cat-aware holdings aggregation query path (computes `% Alloc` / `$ Alloc` at Sub-Cat granularity with Cat subtotals) — parallels §2.1 flag (a). **UX consequence:** the allocation tables read from this; the same staleness/availability caveats as §2.1 apply per row.
- **(c)** **Target allocation storage shape** — where user-defined target %s per Sub-Cat live, **how user-editable target updates persist**, Cat-target = sum-derived vs. independent, per-scope-target V2 forward-compat. **UX consequence:** flag (c)'s "user-editable target updates persist" language indicates **targets are V1-editable** — this drives F-2.2.B's target-edit affordance + **Flag PM-1** (confirm editability + surface shape).
- **(d)** Real Estate / non-liquid Cat semantics (exclusion predicate vs. `rebalanceable` taxonomy flag). **UX consequence:** RE absent from the Non-RE table.
- **(e)** Liabilities-as-Cat semantics (V1 leverage-management extension; target % = desired leverage; positive `$ ReAlloc` = under-leveraged; Liabilities `$ Alloc` appears in BOTH §2.1.5 Debt subtotal and §2.2.2 allocation). **UX consequence:** the Non-RE table includes a Liabilities Cat-group read with leverage semantics; see §1 cross-cluster consistency.
- **(f)** Drill-down view capability (US Equity drill = general capability vs. hardcoded V1 special case). **UX consequence:** §2.2.3 drills off the §2.2.2 "US - Sector Diversified" row; V1 surfaces only this one drill.
- **(g)** RESOLVED — Sec §2.2.4 isolation + scope-attribute pass (Task #14, pass-with-comments).

No open *product* (PM) decisions remain on §2.2 from Phase 1. Items I surface below are flow-level (target editability, target-sum behavior) + the parked P3 interaction.

---

## 1. Cross-cluster consistency (allocation ↔ composition ↔ onboarding) — load-bearing

> Parallel to §2.1's value-semantics pin: §2.2 shares holdings with §2.1.5 composition and consumes §2.4.1's new-symbol surfacing. These must stay consistent so no surface silently contradicts another.

- **Holdings are the same underlying data as §2.1.5 composition.** Allocation `$ Alloc` per Sub-Cat aggregates the **same per-holding current (gross) values** §2.1 pinned (current market value for securities, per 2.1.6). Allocation is a Sub-Cat-granularity *re-grouping* of the asset side, not a new valuation. The two surfaces must never disagree on a holding's value.
- **Total US Equity reconciliation (2.2.3 ↔ 2.2.2).** The sum of the twelve US Equity Sub-Cat rows (2.2.3) **equals** the "US - Sector Diversified" Sub-Cat row in the Non-RE table (2.2.2). Invariant — the drill-down foots to its parent row.
- **Liabilities dual-appearance (flag (e)).** A liability's `$ Alloc` appears in **§2.1.5 composition's Debt subtotal** (liability-side sign) AND in **§2.2.2's Liabilities Cat-group** (leverage-target sign). Same underlying value, two reading frames; signs must be presented consistently per surface so the user isn't confused (composition = "what I owe"; allocation = "leverage vs. target").
- **`Unsorted` provenance (2.4.1 → 2.2.2).** New symbols surfaced by §2.4.1 land as `Unsorted` Sub-Cat under an `Uncategorized` Cat. **The §2.2.2 allocation table renders the `Unsorted` row honestly until cleaned** — it is the allocation surface's manifestation of the §2.4.4 non-silent discipline (the table never lies about provenance). See §2 + the P3 interaction (§7).
- **`$ ReAlloc` sign convention (shared vocabulary).** Positive `$ ReAlloc` = **underweight** (need to add); negative = overweight (need to trim). For Liabilities: positive = **under-leveraged**. This sign convention is shared vocabulary across Visual/Frontend — define once, apply in both tables.

---

## 2. Asset Allocation surface — region inventory

The cluster lives in an **Asset Allocation** destination (top-level surface; the nav model that reaches it is deferred to Step 3, consistent with §2.4/§2.1).

| Region | Story | Content |
|---|---|---|
| `alloc-nonre-table` | 2.2.2 | Non-RE allocation: Sub-Cat rows grouped under Cat-group headers (Cash / Bonds / Equity / Alternatives / Liabilities) + an `Uncategorized`/`Unsorted` group; five columns (% Target / % Alloc / $ Target / $ Alloc / $ ReAlloc); Cat-group subtotals; RE excluded. |
| `alloc-us-equity-table` | 2.2.3 | US Equity sub-allocation drill-down: 12 rows (US-01…US-10 sectors + Index Non-Sector + Growth Non-Sector); same five columns; evaluated vs. Total US Equity. |
| `alloc-unsorted-row` | 2.4.1→2.2.2 | The provenance-honest `Unsorted` row; the P3 classification-surfacing interaction point (§7). |
| `alloc-target-edit` | 2.2.2/flag(c) | The target-% editing affordance (inline-cell vs. settings surface — Flag PM-1). |

**Region composition note:** §2.2 does **not** force a new 2–3-option information-hierarchy decision (unlike §2.1's net-worth surface). The two tables + the drill relationship are PRD-prescribed (US Equity drills off the Non-RE "US - Sector Diversified" row). The only open UX decisions here are two parked-for-Step-3 cross-cluster decisions: **P3** (new-symbol classification surfacing, §7) + **P5** (the target-edit surface shape — inline-cell vs settings-panel, decided coherently with §2.3.2 + §2.5.2; see F-2.2.B). Noting explicitly so the Step 3 walk-through doesn't expect more §2.2-local decisions than exist.

---

## 3. FLOW F-2.2.A — Assign / reassign holdings to taxonomy buckets
**Traces:** 2.2.1. **Entry:** (i) from §2.4.1 onboarding new-symbol surfacing; (ii) from the `alloc-unsorted-row`; (iii) from a holdings-management entry on the Asset Allocation surface (reassign an already-classified symbol as the portfolio evolves, per §1.3).

### Screen list
| Screen | Type | Role |
|---|---|---|
| `Symbol Classification` | panel / modal | Assign a Plaid-surfaced **symbol** to Cat + Sub-Cat (per-symbol; applies across all accounts). **Reused from §2.4.A**, extended to reassignment. |
| `Reassign Symbol Bucket` | panel (variant) | Re-open `Symbol Classification` for an already-assigned symbol to change its bucket. |
| *(manual-holding bucket)* | — | Set at `Add Manual Account` / `Account Detail` edit (§2.4.2) — **no new screen**; cross-ref. |

### Sub-flow A1 — Classify / reassign a Plaid-surfaced symbol (per-symbol)
1. User opens `Symbol Classification` for a symbol (from the queue, the Unsorted row, or a reassign action).
   - *System:* shows Plaid's security metadata (`security_type`, `description`, `ticker`) **as a recommendation hint — never auto-applied** (per §2.4.1). Offers the **seeded** Cat + Sub-Cat pick-list (no "+ new bucket" — taxonomy CRUD is V2+).
2. User selects Cat + Sub-Cat (Sub-Cat inherits its parent Cat).
   - *System:* writes the per-symbol assignment to the taxonomy registry (flag (a)); **the assignment applies across all accounts holding that symbol**; the symbol leaves `Unsorted`; allocation tables + composition recompute.
   - **Decision point:** assign → classified · cancel/defer → stays `Unsorted` (rollups still work; row persists).
3. **Reassign** (portfolio evolves): user re-opens `Reassign Symbol Bucket` on an already-classified symbol and picks a different Sub-Cat. Same write path; re-aggregates everywhere.

### Sub-flow A2 — Set a manual non-securities holding's bucket
- Happens at **manual account create** (`Add Manual Account`, §2.4.2 — the Sub-Cat field there IS this assignment) or **edit** (`Account Detail`). Per-account assignment storage (flag (a)). No separate screen; cross-referenced for traceability.

### Error / edge states
- **No matching seeded bucket** for a holding the user wants to classify → V1 has no "create bucket" escape (CRUD is V2+); the user assigns the closest seeded Sub-Cat or leaves it `Unsorted`. **Flag PM-2** (is "closest seeded bucket or stay Unsorted" the intended V1 dead-end, or is there an expectation of a catch-all?).
- **Deferred classification** → symbol persists in `Unsorted`; surfaces in the queue + the `alloc-unsorted-row`; never blocks aggregation.

### Out of scope — V1/V2 per 2.2.1
Taxonomy CRUD (create/rename/delete Cat or Sub-Cat) — V2+. Auto-classification from Plaid metadata without confirmation — V2+ (per §2.4.1).

---

## 4. FLOW F-2.2.B — Review the Non-RE allocation table
**Traces:** 2.2.2. **Entry:** app nav → `Asset Allocation` → `alloc-nonre-table`.

### Steps
1. **View allocation.** `alloc-nonre-table` renders Sub-Cat rows grouped under Cat-group headers — **Cash / Bonds / Equity / Alternatives / Liabilities** (Liabilities = the V1 leverage-management extension, flag (e)) — plus the `Uncategorized`/`Unsorted` group if any holdings are unclassified. **Real Estate is excluded** (flag (d)). Each Sub-Cat row carries the five columns: **% Target / % Alloc / $ Target / $ Alloc / $ ReAlloc** (positive `$ ReAlloc` = underweight; for Liabilities = under-leveraged). Cat-group subtotals foot each group. Single full-household aggregation (2.2.4); no scope chrome.
2. **Read over/under-target at a glance.** The user scans `$ ReAlloc` / `% Alloc` vs `% Target` to see which Sub-Cats + Cat-groups are over/under, then decides trades **externally** (no suggestions — visualization only).
3. **Drill into US Equity.** Selecting the **"US - Sector Diversified"** Sub-Cat row opens `alloc-us-equity-table` (F-2.2.C).
   - **Decision point:** the "US - Sector Diversified" row drills (the one V1 drill, flag (f)) · other rows do not drill in V1.

### Sub-flow — Edit target %s (V1-editable — CONFIRMED; surface shape parks to Step 3 as P5)
- **PM-1(a) CLOSED:** allocation `% Target` **IS user-editable in V1** (confirmed PRD interpretation — not seeded/migration-only like the taxonomy).
- **PM-1(b) → P5 (cross-cluster; parked for Step 3).** The *edit surface shape* — **(i)** inline-editable `% Target` cells in the table vs. **(ii)** a dedicated `alloc-target-edit` settings panel — is deferred to the Step 3 walk-through as a **CROSS-CLUSTER** decision (logged as **P5** in `temp/phase-2-decisions-log.md`). It is the **1st of 3 user-authored planning-value surfaces** (with §2.3.2 income/expense targets + §2.5.2 tax brackets); the affordance is decided **coherently across all three** so they don't diverge. **My recorded recommendation: inline-cell editing** (dense, in-context, matches the archetype).
  - *System (on edit — either surface):* persists the target (flag (c) storage; write-path validation per ARCH handoff H1, §8A); `$ Target` and `$ ReAlloc` recompute live against current total Non-RE.

### Error / edge states
- **Stale / re-auth holding** (D1) → `stale-data-marker` on the affected Sub-Cat rows + their Cat-group subtotals + the table total; `% Alloc` / `$ Alloc` for stale contributions marked, never silently fresh.
- **`Unsorted` holdings present** → the `Uncategorized`/`Unsorted` row shows actual `% Alloc` / `$ Alloc` but **no meaningful target** (`% Target` / `$ Target` render "—"; `$ ReAlloc` n/a). It inflates the denominator until cleaned — honest provenance over a clean-but-false 100%. P3 interaction in §7.
- **Targets don't sum to 100%** of Non-RE → **Flag PM-3**: lean = show the target-sum with a **reconciliation indicator** ("targets sum to 97%") but **do not block** (visualization-only ethos; the user owns it), rather than force-normalizing. Confirm with PM.
- **Holding value unavailable** (no price for a security; manual asset w/o value) → `$ Alloc` cell marked unavailable, never silently zeroed (parallels §2.1 flag (a) / §2.1.5).

### Out of scope — V1/V2 per 2.2.2
Auto-rebalance suggestions / trade recommendations — V2+. Per-scope allocation views + scope filter — V2+.

---

## 5. FLOW F-2.2.C — Drill into the US Equity sub-allocation
**Traces:** 2.2.3. **Entry:** `alloc-nonre-table` → "US - Sector Diversified" row → `alloc-us-equity-table`.

### Steps
1. **View US Equity breakdown.** `alloc-us-equity-table` renders the **12 rows** — US-01 Basic Materials … US-10 Utilities (the ten sectors) + **Index Non-Sector** + **Growth Non-Sector** — using the same five columns as §2.2.2, **evaluated against Total US Equity** (the sum of all twelve rows, which equals the parent "US - Sector Diversified" row in §2.2.2).
2. **Read concentration vs. balance.** The user scans whether US equity exposure is sector-concentrated or balanced, and whether non-sector (index + growth) holdings sit at the desired level; decides trades externally.
3. **Return** to `alloc-nonre-table`.

### Decision points
- Return ↔ stay. (No further drill — Ex-US is V2+; no third level.)

### Error / edge states
- **Total US Equity = 0** (no US equity holdings) → degenerate/empty drill state ("no US equity holdings"); table not fabricated.
- **Stale / unavailable contributions** (D1 + availability) → same marking discipline as F-2.2.B, applied per row + foot.
- **Parent/child reconciliation break** → if the twelve rows don't foot to the parent "US - Sector Diversified" value (data integrity), surface it rather than hide (should be invariant per §1; a visible mismatch is a bug signal, not a silent reconcile).

### Out of scope — V1/V2 per 2.2.3
Ex-US / international sub-allocation — V2+. Auto-rebalance suggestions — V2+. Deeper-than-one-level drill — V2+.

---

## 6. Cross-cutting error / edge state matrix (V1 failure surfaces for §2.2)
| Edge / error | Where | Behavior |
|---|---|---|
| **Stale / pending-re-auth holding** (D1 — settled global) | both allocation tables: affected rows + Cat subtotals + totals | `stale-data-marker`; `% Alloc`/`$ Alloc` for stale contributions marked; never silently fresh. No re-flagging — D1 is global. |
| **`Unsorted` holdings** (2.4.1 provenance) | `alloc-unsorted-row` in `alloc-nonre-table` | Show actual `% Alloc`/`$ Alloc`; no meaningful target (`—`); inflates denominator until cleaned. P3 interaction (§7). |
| **Holding value unavailable** (no price / manual w/o value) | the holding's Sub-Cat row | `$ Alloc` marked unavailable; never silently zeroed. Parallels §2.1 flag (a). |
| **Targets ≠ 100%** of Non-RE | `alloc-nonre-table` foot | **Passive reconciliation readout** ("targets sum to 97%"); **NOT an alert/block** — stays clear of the §2.3.2-class variance/alert/budget-tracking NON-GOAL (ADR-002 §1.2). PM-3 ✅ CONFIRMED. |
| **Total US Equity = 0** | `alloc-us-equity-table` | Empty/degenerate state; not fabricated. |
| **Parent/child reconciliation break** (2.2.3 ↔ 2.2.2) | drill foot | Surface the mismatch (bug signal), don't silently reconcile. |
| **No matching seeded bucket** (CRUD is V2+) | `Symbol Classification` | Closest seeded Sub-Cat or stay `Unsorted` — no "+ new bucket" (Flag PM-2). |

---

## 7. Live coupling: P3 — new-symbol classification surfacing × the allocation table *(parked for Step 3; §2.2 is where it bites)*

**Context:** P3 (the §2.4 Open Decision 2) is the choice of where the new-symbol classification *task* primarily lives — **(A)** notification-queue inbox, **(B)** inline-in-allocation-table, **(C)** hybrid. It was parked for the Step 3 walk-through. **§2.2.2 is the surface where it bites**, because the `alloc-unsorted-row` is the allocation-side manifestation of unclassified symbols. How each option plays out *at the allocation table*:

- **Option A — Queue-only.** `alloc-unsorted-row` is **read-only display** (shows the unclassified aggregate); classification happens only in the `New-Symbol Classification Queue`. *Allocation-table effect:* the row is informational; the user leaves the surface to clean it. Clean separation, but a context switch from "I see the gap" to "I go elsewhere to fix it."
- **Option B — Inline.** The user **classifies directly from the `alloc-unsorted-row`** — expand it to list pending symbols, each with an inline `Symbol Classification` affordance. *Allocation-table effect:* fix-where-you-see-it; no context switch; but loads onboarding-task UI into an analytic surface and couples §2.2 tightly to §2.4's queue.
- **Option C — Hybrid (my standing recommendation).** The `alloc-unsorted-row` **deep-links into the queue** (and the queue badge remains the canonical task home). *Allocation-table effect:* discoverable from the analytic surface AND the post-connect moment; the row stays lightweight (a link, not an embedded editor).

**UX recommendation: Option C**, consistent with my §2.4 recommendation — but this is the **F/CTO call at Step 3** across §2.4 + §2.2 together (the decision now has both surfaces visible, which is exactly why it was parked). I have **not** designed a single option in; the `alloc-unsorted-row` is specified to support whichever option lands (read-only row that can either stay informational, host an inline editor, or deep-link).

> **Second parked Step-3 decision for this cluster — P5** (the target-edit surface shape, F-2.2.B): distinct from P3. P5 is cross-cluster (decided with §2.3.2 + §2.5.2 planning-value surfaces); P3 is cross-cluster with §2.4. Both ride the Step 3 walk-through.

---

## 8. Scope-creep / ambiguity flags for PM *(route to PM, not designed around)*

### Flag PM-1 — Allocation `% Target` editability + surface. — ✅ **RESOLVED (PM-cleared, 3-part disposition)**
- **PM-1(a) CLOSED:** `% Target` **IS user-editable in V1** (confirmed PRD interpretation). The "pending" conditionality in F-2.2.B is removed.
- **PM-1(b) → P5 (parked for Step 3):** the edit *surface shape* (inline-cell vs. dedicated settings panel) is a **cross-cluster** decision — the 1st of 3 user-authored planning-value surfaces (with §2.3.2 targets + §2.5.2 brackets), decided coherently. Logged as P5 in `temp/phase-2-decisions-log.md`. My inline-cell lean is recorded as the recommendation.
- **PM-1(c) → Phase 3 ARCH handoff H1** (see §8A): the `%Target` write inherits the Lock 14 settings-store fence + a keyed-array validation wrinkle.

### Flag PM-2 — V1 dead-end when no seeded bucket fits. — ✅ **CONFIRMED**
Closest-seeded-bucket-or-stay-`Unsorted`; **no "Other" CRUD affordance** (taxonomy CRUD is V2+). **Routed (not my surface):** whether the *seeded taxonomy itself* contains catch-all "Other" Sub-Cats is an **ADR-004 / Architect Phase-3 bootstrap** seed-content question, not a Phase-2 UX surface.

### Flag PM-3 — Targets ≠ 100% behavior. — ✅ **CONFIRMED**
**Passive reconciliation readout** ("targets sum to 97%"), **NOT** an alert/block/normalize. **Caveat (kept in §6):** the readout must stay passive to remain clear of the **§2.3.2-class variance / alert / budget-tracking NON-GOAL (ADR-002 §1.2)** — it reports the sum; it never warns, scores, or enforces.

*(P3 in §7 + P5 above are the parked Step-3 cross-cluster decisions, not open PM scope flags — surfaced for Step 3 context.)*

---

## 8A. Phase 3 ARCH handoffs (from §2.2 PM consult)
Captured for cross-team routing when Phase 3 spins up (per ADR-012). Backend/architecture concerns, NOT UX surfaces.

- **H1 — `%Target` write-path validation (PM-1(c); Architect / Sec joint).** The allocation-target write inherits the **Lock 14 settings-store fence** (Zod `.strict()` + numeric-input battery + tenant-scoping). New wrinkle vs. §2.3.2's two scalars: targets are a **per-Sub-Cat KEYED ARRAY**, so additionally — (i) each **Sub-Cat key is validated against the seeded taxonomy** (reject forged / cross-tenant Sub-Cat keys), and (ii) **target-specific numeric bounds** (reject negative %, >100%, NaN/Inf; define precision). Architect/Sec joint at Phase 3.
- *(Storage shape itself is Appendix B flag (c) — per-tenant vs per-scope target table; Architect dedupes with the taxonomy registry per flag (a).)*

---

## 9. Provisional screen / surface inventory (for the eventual Visual handoff — NOT final until Step 3 lock)
| # | Surface / region | Type | Flow | Traces |
|---|---|---|---|---|
| 1 | `Asset Allocation` | full screen (surface) | container | 2.2.* |
| 2 | `alloc-nonre-table` | region (table; expandable subtotals) | F-2.2.B | 2.2.2 |
| 3 | `alloc-us-equity-table` | region (drill-down table) | F-2.2.C | 2.2.3 |
| 4 | `alloc-unsorted-row` | row + interaction state | F-2.2.B / §7 | 2.4.1→2.2.2 |
| 5 | `alloc-target-edit` | inline-cell OR settings surface (Flag PM-1) | F-2.2.B | 2.2.2 |
| 6 | `Symbol Classification` | panel/modal (reused from §2.4.A) | F-2.2.A | 2.2.1 |
| 7 | `Reassign Symbol Bucket` | panel (variant) | F-2.2.A | 2.2.1 |

Cross-cutting components consumed/authored: `stale-data-marker` (consumed, D1), allocation-table-row (five-column), Cat-group-subtotal-row, `$ ReAlloc` sign treatment (shared vocab), seeded-bucket pick-list (no-CRUD). Cross-links: `Symbol Classification` ← §2.4.1 queue / §2.4.2 manual; `alloc-nonre-table` "US - Sector Diversified" row → `alloc-us-equity-table`; manual-holding bucket set at §2.4.2 `Add Manual Account` / `Account Detail`.

---

## 10. PRD §2.2 story → flow traceability (for the PM consult)
| PRD story | Covered by | Notes |
|---|---|---|
| 2.2.1 Taxonomy + holding-to-bucket assignment | F-2.2.A (`Symbol Classification` / `Reassign`; manual via §2.4.2) | Seeded buckets only (no CRUD); per-symbol applies across accounts; per-account for manual. |
| 2.2.2 Non-RE allocation table | F-2.2.B (`alloc-nonre-table`) | 5 columns; Cat-groups + Liabilities; RE excluded; target edit (Flag PM-1); Unsorted row. |
| 2.2.3 US Equity sub-allocation | F-2.2.C (`alloc-us-equity-table`) | 12 rows; drills off "US - Sector Diversified"; foots to Total US Equity. |
| 2.2.4 Allocation is the user's (full-household) | §0.2 constraint (all flows) | Single aggregated household allocation; no scope UI; own data only. Not a screen. |

**No flow exceeds its PRD story.** V1/V2 boundaries respected (no taxonomy CRUD, no rebalance engine, no Ex-US drill, no scope UI, RE excluded). D1 applied without re-litigation. PM items isolated as Flags PM-1/2/3; P3 surfaced for Step 3, not designed in.

---

## 11. Status / next
- **✅ §2.2 LOCKED (2026-05-28):** PM traceability PASS; D1 applied correctly; all 3 flags resolved (no F/CTO escalation). Fold-in landed: PM-1(a) CLOSED (V1-editable; conditionality removed from F-2.2.B), PM-1(b)→P5 parked for Step 3, PM-1(c)→ARCH handoff H1 (§8A); PM-2 CONFIRMED (+ seed-content "Other" routed to ADR-004/Architect bootstrap); PM-3 CONFIRMED (passive readout, non-goal fence in §6).
- **Draft coverage:** flow structure complete; cross-cluster consistency pin (§1: allocation↔composition↔onboarding, Total-US-Equity reconciliation, Liabilities dual-appearance, Unsorted provenance, `$ ReAlloc` sign); all V1 failure surfaces in §6.
- **Carried to Step 3 walk-through (parked cross-cluster):** **P3** (new-symbol classification surfacing × allocation table, §7; rec. Option C) + **P5** (target-edit surface shape, F-2.2.B; rec. inline-cell).
- **D1 applied** (staleness on both tables) without re-litigation per team-lead.
- **Next:** §2.3 spending + income categorization (cluster 4 of 6). Then §2.5 → §2.6, Step 3 walk-through, wireframing (Step 4).
- **No wireframing** until the Step 3 gate confirms the flow set.
