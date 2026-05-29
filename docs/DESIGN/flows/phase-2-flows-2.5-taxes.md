# Phase 2 — UX Flow Document: §2.5 Estimated Taxes Cluster

**Cluster:** §2.5 — Estimated taxes (tax-relevant income decomposition; Federal/CA bracket inputs; quarterly estimated-payment computation + IRS/FTB tracking; Realized + Unrealized Tax Liability NAV components).
**Author:** UX Designer (`phase-2-ux-design` team).
**Status:** DRAFT — flows only. Pre-wireframe. Pre-PM-traceability-consult.
**Phase 2 step:** Step 2 (cluster 5 of 6, dependency order; computation-heavy; depends on §2.4 transactions/holdings, §2.2.1 asset taxonomy, §2.3.1 cash-flow taxonomy; **feeds §2.1 NAV**).
**Date:** 2026-05-28.
**Companions:** §2.1 (NAV — §2.5.4 supplies its two tax-component line items; the bootstrap dependency, §1), §2.2 + §2.3 (the other two P5 planning-value surfaces), §2.4 (transactions, IRS/FTB accounts, sell-transaction attributes). Global decision log: `temp/phase-2-decisions-log.md`.

---

## 0. Scope, inputs, and load-bearing constraints

### 0.1 PRD stories in this cluster
- **2.5.1** — Tax-relevant income decomposition: Ordinary Income / ST CG / LT CG at Sub-Cat granularity (single table, 3 columns, Cat-group section headers + Total). Inputs: cash-flow ordinary income (§2.3.1 tax-relevant Sub-Cats) + realized capital gains (§2.4.3 sell-transaction pairing). Sub-Cat `tax_relevant` boolean + `tax_character` enum drive inclusion + routing.
- **2.5.2** — Tax-bracket inputs (Federal + CA FTB parallel): a **V1 settings UI** holding, per jurisdiction, bracket schedule(s) + standard deduction. Federal = ordinary schedule + LT CG schedule + standard deduction; CA = single ordinary schedule + standard deduction. Manual update at tax-year rollover.
- **2.5.3** — Quarterly estimated-payment computation + IRS/FTB tracking: two parallel tables (Federal, CA FTB), each with Tax Balance Prior Year (informational), four quarterly Estimated Tax Payment lines (with due dates), Sub-Total, YTD Paid (from IRS/FTB ledgers), Estimated Funds Due (the gap). Progressive bracket math; annual÷4 cadence; no safe-harbor.
- **2.5.4** — Realized + Unrealized Tax Liability (the two **NAV components** §2.1.1/§2.1.5 consume): Realized = sum of §2.5.3 Estimated Funds Due gaps; Unrealized = (Fed LT CG top rate × aggregate unrealized G/L taxable) + (CA top rate × aggregate unrealized G/L taxable).
- **2.5.5** *(supporting)* — Tax surfaces are the user's; full-household by default; `tax_treatment` is an inclusion filter, not isolation. *(Constraint — no scope-filter UI in V1.)*

### 0.2 Load-bearing constraints (fences)
- **PERMANENT NON-GOAL: no money movement (ADR-002 §3.0).** **Do NOT design any "pay the IRS/FTB," "schedule a payment," "transfer to tax authority," or auto-payment affordance.** The system **records payments the user made externally** (as §2.4.3 manual transactions against the IRS/FTB ledgers) and **computes obligations** — it never initiates, schedules, or moves money. This is a permanent product-identity non-goal, not a V2 deferral.
- **No safe-harbor computation (μ-2 lock).** Quarterly installment = **expected-annual ÷ 4** only. The "Tax Balance Prior Year" row is **informational reference only** — it does NOT drive computation. **Do NOT design** a safe-harbor floor, underpayment-penalty calc, or 100%/110%-prior-year affordance (V2+). The user reasons about safe-harbor/penalty risk externally in V1.
- **No Sub-Cat tax-attribute CRUD UI (2.5.1).** The `tax_relevant` boolean + `tax_character` enum per Sub-Cat are **seeded at bootstrap and editable via migration only in V1**. **Do NOT design a UI to edit a Sub-Cat's tax-relevance or tax-character** — the decomposition table READS them (Sub-Cat tax-attribute CRUD UI is V2+, additive to the §2.2.1/§2.3.1 taxonomy-CRUD V2+ family).
- **No filing-status toggle (ι lock).** V1 = a single standard-deduction scalar per jurisdiction at the user's current filing status (fixed at seed). **No MFJ/single/HoH selector** (V2+).
- **Current calendar year only; no multi-year / custom fiscal year (θ-1 lock).** All §2.5 surfaces compute for the current calendar year (Jan 1 – Dec 31). **No tax-year picker, no prior-year computation surface, no bracket-version history** (V2+).
- **No live tax-data API; manual update at rollover (flag (e)).** Bracket schedules + standard deductions are user-entered/edited; updated manually at tax-year rollover. **No "fetch current brackets" / API-ingest affordance** (V2+).
- **Reactive due-date surfacing only (ξ-1).** Tables show due dates + emphasize the current quarter. **No pre-emptive payment-due reminders, email, or calendar integration** (V2+).
- **No lot-level tax features (ADR-002 §1.7).** V1 uses **aggregate** cost basis (average-cost fallback). **No FIFO/LIFO/specific-ID lot selection, no wash-sale auto-detection, no Section 1256 auto-detection.** V1 user-MARKS wash-sale (a flag on the sell transaction) + Section 1256 (via the `Volatility-60/40` Sub-Cat) — marking, not detection.
- **Single combined NAV-component values (ρ lock).** §2.5.4 surfaces ONE Realized Tax Liab scalar (Fed+CA summed) + ONE Unrealized Tax Liab scalar (Fed+CA summed, taxable-only). **No per-jurisdiction split** on the §2.1.5 rows (per-jurisdiction Realized lives on the §2.5.3 tables; per-jurisdiction Unrealized is V2+).
- **Single full-household tax view; no scope-filter UI (2.5.5 / §7.3).** One aggregated household view. `tax_treatment` (taxable/tax-deferred/tax-free) is an **inclusion filter on the Unrealized aggregation**, not a scope/isolation control. No scope toggle.
- **Density-first (§1.3).** The archetype reasons jurisdictionally (Federal + CA in parallel) about tax and replaces an existing Est Taxes spreadsheet. Parity tables, dense and precise, are the point.
- **Non-silent staleness — D1 (global, settled).** Applied to all §2.5 tables/outputs (decomposition, quarterly tables, NAV components) **without re-flagging** (per team-lead). Stale account inputs mark the affected tax outputs.
- **Server-derived; NOT client-as-of-toggleable.** §2.5 tax computation is server-derived, current-state, live-recompute. **No as-of-date toggle on any §2.5 surface** (per Lock 15: the only client as-of surfaces are §2.3.3 + §2.6). See §1.3.

### 0.3 Appendix B §2.5 — Architect/Sec Phase-3 dependencies (NOT my surface; they constrain these flows)
- **(a)** Sub-Cat `tax_relevant` + `tax_character` schema (seed-on-bootstrap; V2 CRUD forward-compat).
- **(b)** Cross-source join for the §2.5.1 three-column projection (cash-flow ordinary income + realized CG joined under one decomposition).
- **(c)** Tax-year boundary at the query path (current-calendar-year filtering; prior-year liability sourcing).
- **(d)** Holding-period (ST vs LT) source-of-truth (Open Date mechanism).
- **(e)** Bracket-table-update cadence (V1 manual at rollover).
- **(f)** §2.5.2 settings store dedup-vs-separate from the §2.3.2 planning-targets store. → ARCH handoff H1.
- **(g)** Bracket-schedule routing-logic location (enum→schedule mapping). → ARCH handoff H5.
- **(i)** §2.5.3 computation-engine storage/caching shape (PM lean: on-demand pure-function). → ARCH handoff H2.
- **(j)** IRS/FTB account semantics (PM lean: standard §2.4.2 account + overlay). → ARCH handoff H3.
- **(k)** Aggregate unrealized G/L computation surface + **(l)** tax-advantaged exclusion (taxable-only filter). → ARCH handoff H4.
- **(q)** RESOLVED — Sec §2.5 **tri-axis** at-lock pass (tenant isolation + scope-as-data-attribute + **`tax_treatment`-as-inclusion-filter-not-isolation-boundary**, endorsed canonical). No veto, no required revisions. → §2.5 is **Sec product-passed**.

No open *product* (PM) decisions remain from Phase 1. Items below are flow-level (IRS/FTB bootstrap, wash-sale-flag placement) + the parked P5.

---

## 1. §2.5 ↔ §2.1 bootstrap dependency pin + cross-cluster consistency — LOAD-BEARING

> The single most important cross-cluster relationship in this cluster: **§2.5 is what §2.1's NAV depends on.** §2.5.4 supplies the Realized + Unrealized Tax Liability values that §2.1.1's four-component NAV subtracts and §2.1.5's composition table renders. This pin reconciles the dependency with the §2.1 PM-3 "NAV-incomplete-never-silently-dropped" commitment.

### 1.1 The derivation chain (who computes what)
- **Realized Tax Liability** (§2.5.4) = **Estimated Funds Due (IRS)** + **Estimated Funds Due (FTB)** from the §2.5.3 tables → which require the §2.5.1 income decomposition × the §2.5.2 bracket schedules.
- **Unrealized Tax Liability** (§2.5.4) = (Fed LT CG top-bracket rate × `aggregate_unrealized_G/L_taxable`) + (CA top rate × `aggregate_unrealized_G/L_taxable`) → requires §2.5.2 top-bracket rates × holdings cost basis (taxable accounts only, π filter). **Does NOT consume the §2.5.3 engine or `tax_character` routing** (ο-a simplification).
- Both single combined scalars (ρ) feed the **§2.1.5 composition rows** `Realized Tax Liab` + `Unrealized Tax Liab`, and thus §2.1.1 NAV.

### 1.2 Bootstrap-ordering reconciliation (closes §2.1 PM-3 + the §2.1 bootstrap ARCH handoff)
- **Until §2.5.2 brackets are set up** (first launch, before the user enters schedules), §2.5.3 cannot compute → §2.5.4's NAV components are **unavailable**.
- **Reconciliation with §2.1's commitment:** when a tax component is unavailable, **§2.1.5 renders that row as "not yet computed" and marks NAV incomplete — never silently dropping the component or showing it as $0** (the §2.1 PM-3 commitment, originated here). The §2.5 surfaces themselves show a **"set up bracket schedules to compute estimated taxes"** empty/bootstrap state rather than fabricated numbers.
- **Bootstrap ordering answer (the §2.1 ARCH handoff):** NAV renders **before** §2.5 is set up — it renders **incomplete**, with the tax components explicitly flagged "not yet computed." Setting up §2.5.2 (F-2.5.A) is what completes NAV. There is no hard ordering gate; the incomplete-but-honest state bridges the gap.

### 1.3 As-of / server-derived (Lock 15 consistency)
- §2.5 tax computation is **server-derived and current-state**, live-recomputing on transaction changes (Realized via §2.5.3), market-value changes (Unrealized via aggregate G/L), bracket edits (both), and §2.5.1 tax-attribute changes (Realized only). **No client as-of-date toggle on any §2.5 surface** — consistent with Lock 15 (the only free as-of surfaces are §2.3.3 + §2.6). §2.6's monthly report may render §2.5 outputs at a snapshot as-of, but that's §2.6's surface, not §2.5's.

### 1.4 Other cross-cluster consistency
- **Inputs:** §2.5.1 Ordinary Income ← §2.3.1 cash-flow Sub-Cats marked `tax_relevant`; §2.5.1 capital gains ← §2.4.3 sell-transaction realized-G/L pairing (holding period via Open Date). Section 1256 60/40 ← the `Volatility-60/40` Sub-Cat (§2.2.1 asset taxonomy). Wash-sale ← a user-marked flag on the sell transaction (§2.4.3 — see Flag PM-2).
- **IRS/FTB accounts** are standard §2.4.2 manual accounts; payments are §2.4.3 manual transactions. §2.5.3 adds a **read overlay** (tax-domain interpretation), **no new write surface**.

---

## 2. Estimated Taxes surface — region inventory

The cluster lives in an **Estimated Taxes** destination (top-level surface; nav model deferred to Step 3).

| Region | Story | Content |
|---|---|---|
| `tax-income-decomposition` | 2.5.1 | Single table: Sub-Cat rows × {Ordinary Income / ST CG / LT CG}; Cat-group section headers (Income group; Capital-Gains groups by asset Cat); Total row; per-Cat-group subtotals. |
| `tax-quarterly-federal` | 2.5.3 | Federal Income Taxes table: Tax Balance Prior Year (info) · Q1–Q4 Estimated Tax Payments + due dates · Sub-Total · YTD Paid (IRS) · Estimated Funds Due (IRS); applied-rate caption "Federal ordinary: X% / Federal LT CG: Y%"; current quarter emphasized. |
| `tax-quarterly-ca` | 2.5.3 | California State Income Taxes (CA FTB) table: same structure (single ordinary schedule); applied-rate caption "California: Z%"; CA Q3 due-date differs from Federal. |
| `tax-nav-components` | 2.5.4 | The two NAV-component scalars (Realized + Unrealized Tax Liab) + the Unrealized **floor-estimate disclaimer**; primary consumer is §2.1.5 composition — echoed here for traceability (the §1 bridge). |
| `tax-bracket-settings` | 2.5.2 | The **V1 settings UI** (P5 surface): Federal ordinary schedule + Federal LT CG schedule + CA ordinary schedule (each = ordered rate/threshold rows) + per-jurisdiction standard-deduction scalars; per-row editing; manual at rollover. |

**Info-hierarchy note:** §2.5 carries **no new 2–3-option information-hierarchy decision** (unlike §2.1 net-worth + §2.3 spending). The surfaces are PRD-prescribed parity tables (existing Est Taxes sheet structure). The only open UX item is **P5** (the bracket-settings affordance) — and §2.5.2's PRD text **explicitly says "settings UI,"** which largely resolves it (see §8). Noted so Step 3 expectations are calibrated.

---

## 3. FLOW F-2.5.A — Maintain tax-bracket inputs (the 3rd / final P5 planning-value surface)
**Traces:** 2.5.2. **Entry:** `Estimated Taxes` → `tax-bracket-settings` (a settings UI).

### Steps
1. **View / edit the schedules.** `tax-bracket-settings` holds, per jurisdiction:
   - **Federal:** an **ordinary-income schedule** (~7 rate/threshold rows) + a **separate LT CG schedule** (~3 rows: 0/15/20%) + a Federal standard-deduction scalar.
   - **California FTB:** a **single ordinary schedule** (~9 rows) + a CA standard-deduction scalar (CA taxes LT CG as ordinary — no separate CA LT CG schedule in V1).
2. **Edit per row.** The user edits marginal rate + lower-bound threshold per bracket row, and the standard-deduction scalar; **manual update at tax-year rollover** (no API ingest).
   - *System (on edit):* persists (storage shape = ARCH H1; write-path validation = ARCH H1); **live-recompute** of §2.5.3 tables, the applied-rate captions (δ-2), and §2.5.4 NAV components.
3. **Applied-rate captions** echo the computed marginal rates on the §2.5.3 tables (read-only, live) — but the **full schedules live here** in the settings UI.

### P5 (parked for Step 3) — but largely resolved toward settings-UI
- §2.5.2 is the **3rd / final** user-authored planning-value surface (with §2.2 allocation targets + §2.3.2 income/expense targets). **§2.5.2's PRD text explicitly specifies a "V1 settings UI"** (and §2.3.2 does too); §2.2 was silent (my inline-cell lean). **Recorded P5 signal: settings-UI is now the strong cross-cluster default** — the coherent P5 resolution is very likely "settings-UI for all three," reconciling my §2.2 inline-cell lean. **Still the F/CTO call at Step 3; not deciding here.** *(Note: tax brackets are a multi-row, multi-schedule structure that fits a settings panel far more naturally than inline-cell editing anyway — a further nudge toward settings-UI for the family.)*

### Error / edge states
- **Brackets unset (bootstrap)** → §2.5.3/§2.5.4 show the "set up bracket schedules" state; NAV renders incomplete (§1.2). This surface is the remedy.
- **Invalid bracket input** (negative rate, non-monotonic thresholds, NaN/Inf, missing rows) → app-layer validation (Lock 14 numeric battery, ARCH H1); computation runs only on a valid schedule.
- **Partial schedule** → flag incomplete; don't compute against a half-entered schedule silently.

### Out of scope — V1/V2 per 2.5.2
Live tax-data API ingestion (V2+). Bracket inheritance / multi-tax-year version history (V2+). Filing-status enum (V2+). Multi-state bracket sets (V2+).

---

## 4. FLOW F-2.5.B — Review tax-relevant income decomposition
**Traces:** 2.5.1. **Entry:** `Estimated Taxes` → `tax-income-decomposition`.

### Steps
1. **View the decomposition.** A single table: **Sub-Cat rows × three columns — Ordinary Income / ST CG / LT CG** — with **Cat-group section headers** (the Income Cat group as one section; Capital-Gains Cat groups by asset Cat — Equity/Bonds/Alternatives — as a second section), parallel to §2.3.2's two-section layout. Total row foots; per-Cat-group subtotals. **Current calendar year.** Live-recompute as transactions land and as the (seeded) tax-attributes apply.
2. **Read column placement.** Cash-flow ordinary-income events → Ordinary Income column; realized capital-gain events → ST CG or LT CG per holding period (Open Date). `tax_relevant = false` Sub-Cats are excluded entirely; `tax_exempt_interest`-tagged contributions are excluded from Federal computation downstream (but the decomposition shows what feeds where).

### Decision points
- None internal (a read). The `tax_character` enum (seeded) travels with each contribution into §2.5.3 routing; **the user does not edit tax-attributes here** (no CRUD UI — §0.2). Section 1256 (`Volatility-60/40` Sub-Cat) decomposes 60% LT / 40% ST; user-marked wash-sale excludes the disallowed loss (input affordances live on §2.2.1 / §2.4.3 — see §1.4 + Flag PM-2).

### Error / edge states
- **Stale account inputs** (D1) → mark affected Sub-Cat rows + subtotals + Total.
- **No realized gains / no tax-relevant income yet** → empty/partial table; not fabricated.
- **Cost basis unavailable** for a sold holding → that pairing's gain can't be classified precisely; surfaced (average-cost fallback per ADR-002 §1.7; truly-missing basis flagged), never silently zeroed.

### Out of scope — V1/V2 per 2.5.1
Sub-Cat tax-attribute CRUD UI (V2+). Wash-sale / Section-1256 auto-detection (V2+ — V1 is user-marked). Multi-year decomposition tracking (V2+). REIT/MLP K-1 character splits (V2+).

---

## 5. FLOW F-2.5.C — Review quarterly estimated payments + track IRS/FTB
**Traces:** 2.5.3. **Entry:** `Estimated Taxes` → `tax-quarterly-federal` + `tax-quarterly-ca` (two parallel tables).

### Steps
1. **View the two parallel jurisdiction tables.** Each (Federal; CA FTB) shows: **Tax Balance Prior Year** (informational only — does NOT drive computation, μ-2); **four Estimated Tax Payment** lines Q1–Q4 with **IRS-prescribed due dates** (Federal Apr 15 / Jun 15 / Sep 15 / Jan 15; CA aligns on Q1/Q2/Q4, **differs on Q3**); a **Sub-Total** running obligation; **YTD Paid (IRS / FTB)** from the account ledgers; **Estimated Funds Due** = the gap. The **current quarter is visually emphasized** (parallel to §2.3.2 month-emphasis). Each table carries its **applied-rate caption** (δ-2; read-only, live).
2. **Read the obligation.** The user reads how much is owed each jurisdiction by the next due date and how it moved as income/schedule inputs changed.
3. **Record a payment (NO money movement — §0.2 fence).** When the user makes an estimated payment **externally**, they **record it as a §2.4.3 manual transaction** against the **IRS or FTB account** (standard §2.4.2 manual accounts). The cumulative ledger balance feeds **YTD Paid**. **The system never initiates or schedules a payment** — it records what the user did and computes the remaining gap.
   - **Decision point:** payment recorded → YTD Paid increments, Estimated Funds Due shrinks · overpayment → Estimated Funds Due renders **negative on the same line** ("-$X overpaid through Q2"; ν-1 sign-flip, no separate "Refund" line in V1).

### Error / edge states
- **No IRS/FTB account exists** (V1 doesn't auto-seed them) → YTD Paid shows **0 / "no IRS (or FTB) account — create one to track payments"** with a light pointer to §2.4.2 manual-account onboarding. Estimated Funds Due then = the full obligation. **Flag PM-1** (is a light create-pointer in scope, or pure no-seed?).
- **Brackets unset** → "set up bracket schedules" state (the obligation can't be computed; §1.2).
- **Stale account inputs** (D1) → mark affected rows.
- **Reactive due dates only** — the table shows due dates + the current quarter; **no pre-emptive reminder/email/calendar** (ξ-1).

### Out of scope — V1/V2 per 2.5.3
Safe-harbor floor / underpayment-penalty computation (V2+). Alternative installment-sizing (annualized-income method) (V2+). Pre-emptive due-date reminders / email / calendar (V2+). Separate "Refund Expected" line (V2+). **Estimated-tax payment scheduling / auto-transfer — PERMANENT non-goal** (ADR-002 §3.0 money movement).

---

## 6. FLOW F-2.5.D — Realized + Unrealized Tax Liability (NAV components — the §2.1 bridge)
**Traces:** 2.5.4. **Entry:** primarily **consumed in §2.1.5 composition**; echoed in `tax-nav-components` on the Estimated Taxes surface.

### Steps
1. **Realized Tax Liability** = Estimated Funds Due (IRS) + Estimated Funds Due (FTB) from §2.5.3, surfaced as **one combined scalar** (ρ). When YTD payments exceed obligation, it surfaces smaller/negative consistent with ν-1.
2. **Unrealized Tax Liability** = (Fed LT CG top-bracket rate × `aggregate_unrealized_G/L_taxable`) + (CA top rate × `aggregate_unrealized_G/L_taxable`), **one combined scalar** (ρ), **taxable accounts only** (π — tax-deferred/tax-free excluded). Live-recompute on bracket edits + market-value changes.
3. **Both values feed §2.1.5** composition rows + §2.1.1 NAV (§1.1). The `tax-nav-components` region echoes them for traceability with the **floor-estimate disclaimer**.

### Disclaimer (PRD-mandated, Sec-endorsed)
- The Unrealized value carries the user-facing disclaimer: **"This estimate may understate actual tax owed if any portion of unrealized gain would be realized at short-term rates; treat it as an LT-aware floor estimate, not a precise tax forecast."** (Computed at the Federal LT CG top-bracket rate — less conservative than top-marginal-ordinary; "standard product disclaimer territory" per Sec.)

### Error / edge states
- **Brackets unset** → both components unavailable → §2.1.5 renders "not yet computed" + NAV incomplete (§1.2). The `tax-nav-components` echo shows the same bootstrap state.
- **No taxable holdings / no unrealized G/L** → Unrealized = $0 legitimately (not an error); Realized still computes from §2.5.3.
- **Stale account inputs** (D1) → mark; the components inherit staleness from their inputs into §2.1.5.
- **Cost basis unavailable** → aggregate uses average-cost fallback; truly-missing basis flagged (never silently zeroed).

### Out of scope — V1/V2 per 2.5.4
Per-jurisdiction split rendering on §2.1.5 (V2+; single combined scalars in V1). Lot-level / bracket-aware Unrealized refinements (ο-b/ο-c) (V2+). Tax-deferred "ordinary-income-on-withdrawal" as a 4th NAV line (V2+). Tax-loss-harvesting recommendations (V2+ non-goal).

---

## 7. Cross-cutting error / edge state matrix (V1 failure surfaces for §2.5)
| Edge / error | Where | Behavior |
|---|---|---|
| **Brackets unset (bootstrap)** | quarterly tables, NAV components, → §2.1.5 | "Set up bracket schedules" state; §2.1.5 rows "not yet computed" + NAV incomplete (§1.2). Never fabricated. |
| **Stale / pending-re-auth inputs** (D1) | decomposition, quarterly tables, NAV components | `stale-data-marker`; propagates into §2.1.5. Never silently fresh. No re-flagging. |
| **No IRS/FTB account** (no auto-seed) | YTD Paid column | 0 / "create an IRS/FTB account to track payments" + pointer to §2.4.2. Funds Due = full obligation. Flag PM-1. |
| **Invalid / partial bracket input** | `tax-bracket-settings` | Lock 14 validation (rate/threshold bounds, monotonic thresholds); compute only on valid schedule. |
| **Overpayment** (YTD > obligation) | Estimated Funds Due | Negative single line ("-$X overpaid"); ν-1. No separate Refund line (V2+). |
| **Cost basis unavailable** | decomposition (CG), Unrealized | Average-cost fallback; truly-missing basis flagged; never silently zeroed. |
| **Money-movement "missing"** | — | **Not an error — permanent non-goal.** No pay/schedule/transfer affordance exists by design (ADR-002 §3.0). |

---

## 8. Open decisions to surface to F/CTO (NOT decided unilaterally)
**No new information-hierarchy decision for §2.5** (the surfaces are PRD-prescribed parity tables). The one open UX item:

### P5 — bracket-settings affordance (3rd / final planning-value surface) — largely resolved toward settings-UI
§2.5.2 is the final P5 surface (with §2.2 allocation targets + §2.3.2 income/expense targets). **§2.5.2 + §2.3.2 PRD text both explicitly specify a "settings UI";** §2.2 was silent (inline-cell lean). With two of three surfaces explicitly settings-UI — and tax brackets being a multi-row/multi-schedule structure that fits a settings panel far better than inline cells — **the strong P5 resolution is "settings-UI for the planning-value family,"** reconciling my §2.2 inline-cell lean. **Recorded as the standing recommendation; the coherent decision is still the F/CTO call at the Step 3 walk-through.** Not deciding here.

---

## 8A. Phase 3 ARCH handoffs (from §2.5 PM consult)
Captured for cross-team routing when Phase 3 spins up (per ADR-012). Backend/architecture/security; NOT UX surfaces.
- **H1 — §2.5.2 bracket-settings write-path (flag (d)/(f); Architect / Sec joint).** Inherits the **Lock 14 settings-store fence** (Zod `.strict()` + numeric battery + tenant-scoping), like §2.2 H1 + §2.3 H1. Richer field shape than §2.3.2's scalars: **per-jurisdiction bracket-row arrays + standard-deduction scalars** → validate rate/threshold bounds + monotonic thresholds + row-count sanity. Architect picks dedup-vs-separate-from-§2.3.2-store (flag (f)). **Completes the 3-surface planning-value settings family** (§2.2 H1 + §2.3 H1 + this H1).
- **H2 — §2.5.3 computation-engine shape (flag (i)).** Progressive-bracket compute; PM lean **on-demand pure-function** (bounded single-user volume). Architect picks precomputed/on-demand/hybrid.
- **H3 — IRS/FTB account semantics (flag (j)).** PM lean **standard §2.4.2 account + tax-domain read overlay** (j-1); no special account-type in V1.
- **H4 — aggregate unrealized G/L surface (flag (k)) + tax-advantaged exclusion (flag (l)).** Sum of (market value − aggregate cost basis) across taxable holdings; `tax_treatment IN ('taxable')` query filter (π); average-cost fallback per ADR-002 §1.7.
- **H5 — bracket-schedule routing-logic location (flag (g)).** Where the `tax_character` enum → schedule mapping lives; PM lean hardcoded static routing table in the V1 compute engine (g-1).

---

## 9. Scope-creep / ambiguity flags for PM *(route to PM, not designed around)*

### Flag PM-1 — IRS/FTB account bootstrap: light create-pointer vs. pure no-seed? *(ambiguity)*
V1 does NOT auto-seed IRS/FTB accounts (they're standard §2.4.2 manual accounts the user creates "whenever"). If they don't exist, YTD Paid can't track payments.
- *Question:* is a **light empty-state pointer** ("create an IRS/FTB account to track payments" → §2.4.2) in V1 scope, or is it pure no-seed (the user just knows to create them, no pointer)?
- *Lean:* a light pointer/empty-state hint (not a forced or auto-create flow) — it makes the §2.5.3 YTD-Paid column self-explanatory without adding a new write surface. Confirm.

### Flag PM-2 — Where does the user mark the wash-sale flag? (cross-cluster; touches LOCKED §2.4.3) *(ambiguity)*
§2.5.1 specifies a **user-marked wash-sale flag "on the underlying sale transaction"** (excludes the disallowed-loss amount) — V1. My **locked §2.4.3 `Transaction Entry`** flow did not include a wash-sale-flag field (§2.4 didn't drill tax). This implies a **small addition to the locked §2.4.3 sell-transaction edit surface**: a user-markable wash-sale flag (+ disallowed-loss amount).
- *Question:* confirm the wash-sale flag is a **field on the §2.4.3 sell-transaction edit** (my lean — the flag travels with the transaction, cleanest), vs. a separate §2.5 marking surface. If §2.4.3, it's a minor addition to a locked flow — routing to PM/team-lead so the locked §2.4 doc gets a small annotation rather than me silently adding it.
- *(Section 1256 60/40 is already handled — it rides the `Volatility-60/40` Sub-Cat in the §2.2.1 asset taxonomy, no new surface.)*

### P5 note (not a scope flag) — §2.5.2 reinforces the settings-UI P5 resolution (§8). Surfaced for Step 3 context.

*(Sec already product-passed §2.5 tri-axis at lock — Task at §2.5 close. No fresh Sec spawn indicated; the write-path/RLS items are Phase-3 ARCH handoffs H1/H4, not open product questions.)*

---

## 10. Provisional screen / surface inventory (for the eventual Visual handoff — NOT final until Step 3 lock)
| # | Surface / region | Type | Flow | Traces |
|---|---|---|---|---|
| 1 | `Estimated Taxes` | full screen (surface) | container | 2.5.* |
| 2 | `tax-income-decomposition` | region (3-column section table) | F-2.5.B | 2.5.1 |
| 3 | `tax-quarterly-federal` | region (jurisdiction table) | F-2.5.C | 2.5.3 |
| 4 | `tax-quarterly-ca` | region (jurisdiction table) | F-2.5.C | 2.5.3 |
| 5 | `tax-nav-components` | region (2 scalars + disclaimer; echo of §2.1.5) | F-2.5.D | 2.5.4 |
| 6 | `tax-bracket-settings` | settings UI (P5) | F-2.5.A | 2.5.2 |

Cross-cutting components: `stale-data-marker` (consumed, D1), bracket-row editor (rate/threshold), standard-deduction-scalar field, jurisdiction-tax-table-row, `applied-rate-caption` (read-only, live — δ-2; same pattern as §2.3.2 captions), current-quarter-emphasis, `due-date` annotation (reactive), overpayment-negative-line, floor-estimate-disclaimer. Cross-links: IRS/FTB payment recording → §2.4.3 `Transaction Entry`; wash-sale flag → §2.4.3 sell-transaction edit (Flag PM-2); Section 1256 → §2.2.1 `Volatility-60/40` Sub-Cat; **`tax-nav-components` → §2.1.5 composition rows (the §1 bridge)**.

---

## 11. PRD §2.5 story → flow traceability (for the PM consult)
| PRD story | Covered by | Notes |
|---|---|---|
| 2.5.1 Income decomposition | F-2.5.B (`tax-income-decomposition`) | 3-column Sub-Cat table; seeded tax-attributes (no CRUD UI); inputs from §2.3.1 + §2.4.3. |
| 2.5.2 Bracket inputs | F-2.5.A (`tax-bracket-settings`) | Settings UI (P5; settings-UI resolution strong); Fed ordinary + Fed LT CG + CA ordinary + std deductions; manual at rollover. |
| 2.5.3 Quarterly computation + IRS/FTB | F-2.5.C (`tax-quarterly-federal` + `tax-quarterly-ca`) | Two parallel tables; annual÷4 (no safe-harbor); YTD Paid from §2.4.3 ledgers; record-not-move; overpayment negative. |
| 2.5.4 Realized + Unrealized NAV components | F-2.5.D (`tax-nav-components`) + §2.1.5 | Two combined scalars; Unrealized = LT-CG-top-rate × aggregate G/L taxable-only; floor disclaimer; the §2.1 bridge. |
| 2.5.5 Tax surfaces are the user's | §0.2 constraint (all flows) | Full-household; `tax_treatment` inclusion filter ≠ isolation; no scope UI; own data only. Not a screen. |

**No flow exceeds its PRD story.** All fences respected: money-movement permanent non-goal; no safe-harbor; no tax-attribute CRUD UI; no filing-status toggle; current-year-only; no API ingest; reactive due dates only; no lot-level features; single combined NAV-component scalars; no scope UI. D1 applied without re-litigation. PM items isolated as Flags PM-1/PM-2; P5 surfaced for Step 3.

---

## 12. Status / next
- **This draft:** §2.5 (computation-heavy) flow structure complete; the **§2.5↔§2.1 bootstrap-dependency pin (§1)** reconciles NAV-incomplete behavior + answers the §2.1 bootstrap-ordering ARCH handoff (NAV renders incomplete, tax components flagged "not yet computed," never silently dropped); all V1 failure surfaces in §7; **money-movement + safe-harbor + tax-attribute-CRUD fences enforced throughout.**
- **Surfaced to F/CTO (Step 3):** P5 — §2.5.2 is the 3rd planning-value surface; its explicit "settings UI" PRD text makes settings-UI the strong coherent P5 resolution (reconciles my §2.2 inline-cell lean). No new info-hierarchy decision.
- **D1 applied** (staleness on all §2.5 outputs) without re-litigation.
- **Flags for PM:** PM-1 (IRS/FTB bootstrap pointer), PM-2 (wash-sale flag placement — a small implied addition to LOCKED §2.4.3; routing rather than silently adding).
- **ARCH handoffs (§8A):** H1 (bracket write-path — completes the 3-surface planning-value settings family), H2 (compute engine), H3 (IRS/FTB semantics), H4 (unrealized G/L + tax-advantaged exclusion), H5 (routing-logic location).
- **Sec:** §2.5 already product-passed tri-axis at lock; no fresh spawn indicated (write-path/RLS are Phase-3 ARCH handoffs).
- **Next:** PM traceability consult (team-lead spawns PM; I do NOT self-certify). Then **§2.6 monthly report — the final cluster** (6 of 6) → Step 3 F/CTO walk-through → wireframing (Step 4).
- **No wireframing** until the Step 3 gate confirms the flow set.
