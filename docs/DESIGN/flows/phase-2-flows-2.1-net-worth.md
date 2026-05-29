# Phase 2 — UX Flow Document: §2.1 Net Worth Cluster

**Cluster:** §2.1 — Net worth (current NAV, NAV-over-time, multi-horizon deltas, reference-date NAVs, composition).
**Author:** UX Designer (`phase-2-ux-design` team).
**Status:** DRAFT — flows only. Pre-wireframe. Pre-PM-traceability-consult.
**Phase 2 step:** Step 2 (flow drafting per cluster, dependency order — §2.1 is 2nd, the first read-surface; depends on §2.4 supplying account data).
**Date:** 2026-05-28.
**Working artifact** — `temp/` (gitignored) per `feedback_working_artifacts_temp_not_docs`.
**Companion:** `temp/phase-2-flows-2.4-cross-cutting.md` (the foundation cluster — supplies accounts, values, and the `stale-data-marker` this cluster consumes).

---

## 0. Scope, inputs, and load-bearing constraints

### 0.1 PRD stories in this cluster
- **2.1.1** — Current net worth (NAV = Gross Asset Value − Debt − Realized Tax Liabilities − Unrealized Tax Liabilities).
- **2.1.2** — Net worth over time (time-series chart; monthly default + on-demand weekly/daily; inflation-adjusted overlay as a second simultaneous line; 60-month rolling window).
- **2.1.3** — Multi-horizon NAV-delta panel (Month / YTD / 1-Year / 3-Year / 5-Year; $ + %; Inflation-Adjusted column for the three multi-year horizons).
- **2.1.4** — NAV at three reference dates (This Month / Prior Month / Prior Year-End; nominal + prior-Year-End-$ columns).
- **2.1.5** — Net worth composition (single integrated build-up table: account rows → subtotals → NAV; per-row current value + unrealized G/L; expandable categories).
- **2.1.6** *(supporting)* — Investment net worth uses current market value. *(A valuation rule, not a screen — informs composition row values; see §1 value-semantics pin.)*
- **2.1.7** *(supporting)* — Net worth is the user's, full-household NAV by default. *(A constraint — no scope-filter UI in V1; see §0.2.)*

### 0.2 Load-bearing constraints
- **Single full-household NAV; no scope-filter UI (2.1.7 / §7.3 / ADR-004 Decision B).** V1 shows ONE aggregated household NAV spanning every ownership scope. **No scope toggle, no per-scope view, no scope filter chrome** — per-scope reporting is V2+. The data model carries scope per account, but the V1 UI never surfaces it. Only the requesting user's own data ever appears.
- **Fixed sets (no user configuration in V1).** 60-month rolling window (2.1.2), the five delta horizons (2.1.3), the three reference dates (2.1.4) are all **fixed** in V1. No "configure window / horizon / reference date" affordances.
- **Inflation overlay is NOT a toggle.** 2.1.2's inflation-adjusted line is drawn **simultaneously** with the nominal line; 2.1.3's IA column and 2.1.4's prior-Yr-$ column are **side-by-side**, never behind a toggle. Do not design a "show inflation-adjusted" switch.
- **NAV is conservatively tax-adjusted at the aggregate, never per-account.** The four-component definition (Gross − Debt − Realized Tax Liab − Unrealized Tax Liab) applies at the whole-position level. **Tax adjustments are aggregate subtractions, not per-account values** — critical for the §1 value-semantics pin.
- **Density-first (§1.3).** The owner reasons jurisdictionally about tax, cares about cost basis / unrealized G/L, and wants structure visible — not a single hand-holding scalar. "The single headline number doesn't hide its structure" (2.1.5) is a direct design mandate. Precision and density are features.
- **Non-silent staleness (inherited from §2.4.4).** Every NAV-derived aggregation that consumed data from a stale / pending-re-auth account must carry the `stale-data-marker`. See §6 + Flag PM-1 (scope of the marking).

### 0.3 Appendix B §2.1 — Architect Phase-3 dependencies (NOT my surface, but they constrain these flows)
- **(a)** Manual / re-auth account contribution rule (last-known-good vs. user-entered vs. zero vs. omitted) — Architect's call. **UX consequence:** composition rows + the headline NAV carry account provenance/staleness; the exact contributed *value* is set by (a). UX never silently zeroes a stale account.
- **(b)** Period aggregation for the time series (pre-aggregated multi-resolution vs. on-the-fly) — Architect's. **UX consequence:** the granularity toggle (monthly/weekly/daily) assumes finer resolution is reachable; latency of granularity switches depends on (b).
- **(c)** Historical NAV import depth (Dec-2015 forward; whether per-category breakdown imports alongside total NAV) — Architect's. **UX consequence:** 3Y/5Y deltas + the trend's full 60-month window are only meaningful where history exists; pre-import periods → "insufficient history" edge state (§6). Whether the *composition* table has historical depth (vs. current-only) depends on whether per-category NAV imported — flagged as dependency for the as-of behavior of 2.1.5.
- **(d)** CPI-U source (live API vs. manual entry; depth back to Dec-2015) — Architect's. **UX consequence:** the inflation-adjusted line/column requires CPI-U; missing/stale CPI-U → IA-unavailable edge state (§6); nominal still renders. Never fabricate an IA value.
- **(e)** RESOLVED — Sec §2.1.7 isolation + scope-attribute pass (Task #8, pass-with-comments).

**Named Phase-3 ARCH locks this cluster couples to (per team-lead steer):**
- **Lock 8 — NAV materialization.** NAV is *materialized* to the `pfin.nav` table — computed on a cron cadence and written directly (no review gate); CPI-U auto-ingested via the existing `pfin_back_etl` BLS pull; historical NAV imported Dec-2015-forward. This is the source the headline NAV, trend, deltas, and reference dates read from, and it pins the **freshness** meaning of every NAV value (see §1.2).
- **Lock 15 — as-of-date read semantics.** Dual-column read filter (`transaction_date ≤ as_of` AND `created_at ≤ as_of`), immutable `created_at`. Primarily a **§2.3.3 / §2.6** mechanism (those surfaces expose an as-of toggle); referenced here only for historical-state reconstruction consistency — **§2.1 exposes no free as-of toggle**, only the fixed reference dates of 2.1.4.

No open *product* (PM) decisions remain on §2.1 from Phase 1. The decision this cluster surfaces (information hierarchy) is a Phase-2 UX decision, not a re-litigation.

---

## 1. Value-semantics pin (CARRY-FORWARD from the §2.4 PM consult) — load-bearing

> **Why this section exists:** the §2.4 `Accounts Hub` `account-row` shows a **"current value,"** and the §2.1.5 composition table reuses the **same account-type grouping vocabulary** and shows each account's **"current value" + unrealized G/L.** Team-lead flagged a read-dependency: drilling §2.1 must **pin value semantics so the Accounts Hub does not silently define a NAV presentation.** This is that pin. It is the shared vocabulary across §2.1, §2.4, Visual, and Frontend.

### 1.1 Per-account "current value" = GROSS, current, never tax-adjusted
- An account's **"current value"** (on the Accounts Hub `account-row` AND in the §2.1.5 composition account rows) is its **current gross value** — current market value for investments (per 2.1.6), current balance for depository/loan, current user-maintained value for manual assets. It is the account's contribution to **Gross Asset Value**.
- **Per-account values are NEVER tax-adjusted.** The Realized + Unrealized Tax Liability subtractions exist ONLY at the aggregate (the composition table foot). No account row anywhere shows a tax-adjusted number. This is what keeps the Hub from implying a NAV.

### 1.2 As-of semantics: the Hub is always "current"; NAV surface owns history
- `Accounts Hub` `account-row` "current value" = **current state** (as of latest successful sync / latest known value), **staleness-marked** if stale or pending re-auth. The Hub never renders a historical as-of view.
- The **Net Worth surface** owns all historical / as-of / reference-date presentations (2.1.2 trend, 2.1.4 reference dates). "This Month / current NAV" on that surface = current state, consistent with the Hub's current values.
- **Materialization + as-of coupling (Phase-3 ARCH locks).** Current + historical NAV are read from the **materialized `pfin.nav`** table — NAV is computed on a cron cadence and written directly per **Lock 8** (no review gate). So "current NAV" is precisely *as-of the last NAV materialization*. The Net Worth surface therefore **displays the NAV-materialization timestamp** ("NAV as of …") — a freshness signal **distinct from** per-account sync staleness: the `stale-data-marker` covers stale *account inputs*, while NAV-materialization recency is its own line (added to the §6 matrix). Historical/as-of *reconstruction* follows the **Lock 15** dual-column read discipline; but §2.1 surfaces only the fixed reference dates of 2.1.4, never a free as-of toggle (that toggle is a §2.3.3 / §2.6 surface).

### 1.3 The Hub does NOT present NAV
- **Decision (CONFIRMED by PM-2):** the `Accounts Hub` presents per-account gross current values and, at most, a **clearly-labeled "Gross total (pre-tax-adjustment)"** subtotal — it does **NOT** display NAV or any tax-adjusted figure. **NAV is owned exclusively by the Net Worth surface.** The Hub links to Net Worth for the tax-adjusted whole-position number.
- **PM-2 handoff caveat (carry to Visual):** the Hub's "Gross total (pre-tax-adjustment)" subtotal must stay **clearly labeled "not net worth / pre-tax-adjustment."** It is a **presentational mirror of the §2.1.5 `Gross Total` subtotal — NOT a second NAV-like headline and NOT a new computed metric.** Visual must not style it as a hero/headline number.
- **Reconciliation invariant:** sum of active `account-row` gross current values on the Hub == the composition table's **Gross Total** subtotal (modulo inactive accounts, which both surfaces exclude from current-state). The two surfaces must never disagree on gross.

### 1.4 Shared subtotal vocabulary (from 2.1.5; becomes Visual/Frontend vocabulary)
`Total Non-RE` → `Gross Total` → `Debt` → `Realized Tax Liab` → `Unrealized Tax Liab` → `NAV`. Asset-half grouping categories (shared with the Hub): `depository`, `investment`, `retirement`, `crypto`, `manual/other`, with `Real Estate` as its own adjacent group and `Liabilities` on the debt side.

> **Carry-back note for team-lead/PM:** this pin is *consistent with* what §2.4 already wrote ("current value") — it does not reopen the locked §2.4 flows. It defines the meaning so Visual/Frontend don't render a tax-adjusted per-row number or a Hub-level NAV. Surfaced as **Flag PM-2** for explicit confirmation.

---

## 2. Net Worth surface — region inventory

The cluster lives in a single **Net Worth** destination (a top-level app surface; the nav-model that *reaches* it is deferred to the Step 3 walk-through, consistent with §2.4). The surface is composed of five named regions, each tracing to a story:

| Region | Story | Content |
|---|---|---|
| `nav-headline` | 2.1.1 | Current NAV (the single tax-adjusted whole-position number) + its four-component definition made legible. |
| `nav-delta-panel` | 2.1.3 | Month / YTD / 1Y / 3Y / 5Y, each as $ Δ + % Δ; Inflation-Adjusted column for 1Y/3Y/5Y (referenced to prior Year-End). |
| `nav-reference-dates` | 2.1.4 | This Month / Prior Month / Prior Year-End; two columns each — NAV (nominal) + NAV—Prior Yr $ (inflation-adjusted). |
| `nav-trend-chart` | 2.1.2 | 60-month time-series; nominal + inflation-adjusted lines drawn simultaneously; granularity control (monthly default / weekly / daily); inflection drill-down. |
| `nav-composition-table` | 2.1.5 | Build-up table: account rows (current value + unrealized G/L) → subtotals (§1.4 vocabulary) → NAV at foot; categories expand one level. |

**How these regions compose into the surface is OPEN DECISION 1 (§7) — the information-hierarchy decision** (number-first vs. trend-first vs. breakdown-first / dense-single-canvas). Region content is fixed by the PRD; their arrangement and which anchors the view is the F/CTO call.

---

## 3. FLOW F-2.1.A — Review current net worth
**Traces:** 2.1.1, 2.1.3, 2.1.4, 2.1.7. **Entry:** app nav → `Net Worth`.

### Steps — user actions → system responses → decision points
1. **Open Net Worth.** User navigates to the surface.
   - *System:* computes/loads current NAV (2.1.1) = Gross − Debt − Realized Tax Liab − Unrealized Tax Liab; renders `nav-headline`, `nav-delta-panel`, `nav-reference-dates`. Single full-household aggregation (2.1.7); no scope chrome.
2. **Read the headline NAV (2.1.1).** `nav-headline` shows the current tax-adjusted whole-position number. The four-component definition is legible (not hidden) — links/expands into `nav-composition-table` (F-2.1.C) where the build-up is traceable.
3. **Read directional deltas (2.1.3).** `nav-delta-panel` shows the five fixed horizons, each $ + %, with the IA column on 1Y/3Y/5Y. No interaction required (static read); horizons fixed.
4. **Read anchor-date NAVs (2.1.4).** `nav-reference-dates` shows This Month / Prior Month / Prior Year-End in nominal + prior-Yr-$ columns.

### Decision points
- None internal to this flow (it's a read). Cross-links: headline → composition (F-2.1.C); the surface co-presents the trend chart (F-2.1.B) per the §7 composition decision.

### Error / edge states (detailed in §6)
- Stale / re-auth account contribution → `stale-data-marker` on the headline + deltas + reference dates (pending Flag PM-1 scope).
- Tax-component unavailable (§2.5 dependency) → NAV build-up shows the missing component explicitly; never presents an incomplete NAV as complete.
- Insufficient history → 3Y/5Y delta cells + Prior-Year-End reference show "insufficient history" rather than a fabricated value.

---

## 4. FLOW F-2.1.B — Explore net worth over time
**Traces:** 2.1.2. **Entry:** the `nav-trend-chart` region on the Net Worth surface.

### Steps
1. **View the trend.** `nav-trend-chart` renders the 60-month rolling window with the **nominal NAV line and the inflation-adjusted (CPI-U-normalized) NAV line drawn simultaneously** (not a toggle), visually distinct. Monthly granularity by default.
2. **Change granularity.** User switches granularity: **monthly (default) ↔ weekly ↔ daily**.
   - *System:* re-renders at the chosen resolution (resolution reachability + latency per Architect flag (b)).
   - **Decision point:** monthly / weekly / daily — three fixed options; no custom interval.
3. **Drill into an inflection point.** User selects/zooms a point or sub-range to investigate a specific inflection.
   - *System:* renders the shorter-period detail around that point (finer granularity).
   - **Decision point:** drill into a sub-range → finer view · return → 60-month default.

### Error / edge states
- **CPI-U unavailable** (flag (d)) → the inflation-adjusted line is **omitted with an explicit note** ("inflation-adjusted view unavailable — CPI-U data missing"); the nominal line still renders. Never fabricate the IA line.
- **Insufficient history** for the full window → chart truncates to the available range with a boundary note (e.g., "history begins [import-anchor]").
- **Stale-account contribution** in a recent period → the affected segment / latest point carries the `stale-data-marker` (this surface is explicitly named in §2.4.4).

### Out of scope — V1/V2 per 2.1.2
User-configurable rolling windows (V2+). The 60-month window is fixed. The inflation overlay is not toggleable (always co-drawn).

---

## 5. FLOW F-2.1.C — Trace NAV composition
**Traces:** 2.1.5, 2.1.6, 2.1.1 (build-up). **Entry:** `nav-composition-table` region, or from `nav-headline` "see how this is built."

### Steps
1. **View the build-up.** `nav-composition-table` renders the single integrated table: account rows grouped by account-type category within the asset half (depository / investment / retirement / crypto / manual-other), with **Real Estate as its own adjacent group**; then the subtotal build-up in order: **Total Non-RE → Gross Total → Debt → Realized Tax Liab → Unrealized Tax Liab → NAV** (foot). Each **account row** shows **current value (gross, per §1.1) + unrealized gain/loss** (2.1.6: market value for investments).
2. **Expand a category.** User expands an account-type category one level.
   - *System:* reveals the individual contributing accounts under that category.
   - **Decision point:** expand ↔ collapse (one level only — no deeper nesting in V1).
3. **Drill to an account.** User selects an account row → **`Account Detail`** (the §2.4 container).
   - *Cross-cluster link:* composition row → Account Detail; provenance/staleness on the row mirrors the Hub.

### Decision points
- Category expand/collapse (one level). Account-row → Account Detail.

### Error / edge states
- **Stale / re-auth / manual account** → the contributing row carries provenance (synced-fresh / synced-stale / pending-re-auth / manual) and the `stale-data-marker` where applicable; the **subtotals and NAV that include it are also marked** (non-silent staleness — this table is named in §2.4.4). The contributed value follows Architect flag (a); UX never silently zeroes it.
- **Tax-component unavailable** (§2.5 not computed: brackets unset, computation can't run) → the `Realized Tax Liab` and/or `Unrealized Tax Liab` rows render an explicit **"not yet computed"** state; the NAV foot is marked **incomplete** rather than silently dropping the component. *(Inter-cluster dependency on §2.5 — see Flag PM-3.)*
- **Unrealized G/L unavailable** for an account (no cost basis, e.g., a manual asset without basis) → the G/L cell shows "—"/"n/a"; current value still contributes to gross.

### Out of scope — V1/V2 per 2.1.5 / 2.1.7
Per-scope composition views + scope-filter UI (V2+). Deeper-than-one-level drill within the table (V2+ if ever). Single full-household build-up only.

---

## 6. Cross-cutting error / edge state matrix (the V1 failure surfaces for §2.1)
| Edge / error | Where it shows | Behavior |
|---|---|---|
| **Stale / pending-re-auth account** | headline NAV (2.1.1), delta panel (2.1.3), reference dates (2.1.4), trend chart (2.1.2), composition rows + subtotals + NAV (2.1.5), AND `nav-asof-timestamp` | `stale-data-marker` on **every** NAV-derived aggregation that consumed the stale data — including the headline NAV, deltas, and reference dates that §2.4.4's literal list omitted. **Resolved per D1 (global, F/CTO-ratified):** the staleness-marking surface list is ILLUSTRATIVE, not exhaustive; aggregations are never silently presented as fresh. Inherited contract upheld on the most prominent number. |
| **Tax component not computed** (§2.5 dependency) | composition `Realized/Unrealized Tax Liab` rows + headline NAV | Missing component shown explicitly ("not yet computed"); NAV marked incomplete; never presented as complete. **Flag PM-3** (inter-cluster). |
| **Insufficient NAV history** (pre-import / no checkpoint) | 3Y/5Y deltas (2.1.3), Prior-Year-End reference (2.1.4), trend window (2.1.2) | "insufficient history" / "—"; chart truncates to available range. Per Architect flag (c) import depth. |
| **CPI-U unavailable** (flag (d)) | inflation line (2.1.2), IA column (2.1.3), prior-Yr-$ column (2.1.4) | IA presentation omitted with an explicit note; **nominal always still renders**. Never fabricate. |
| **Manual account contribution** (flag (a)) | composition row + all aggregations | Row marked `manual`; contributed value per Architect rule (a); never silently zeroed. |
| **NAV-materialization recency** (Lock 8 cron cadence) | Net Worth surface header | Display "NAV as of <last `pfin.nav` write timestamp>". A freshness signal **distinct from** per-account sync staleness — NAV could be computed-recent while an input account is sync-stale, or vice versa. Both signals shown; neither masks the other. |

---

## 7. Open decisions to surface to F/CTO (NOT decided unilaterally)

### Open Decision 1 — Net Worth information hierarchy: single number vs. trend vs. breakdown *(ADR-bound; the §2.1 info-hierarchy decision team-lead named)*
All five regions ship (PRD-fixed). The decision is **which anchors the surface and how the regions compose.** Per WORKFLOW Phase-2 Step 3, this lands at the F/CTO walk-through with a **DECISIONS.md ADR**. Three options:

- **Option A — Number-first.** `nav-headline` + `nav-delta-panel` dominate above the fold; `nav-reference-dates` adjacent; `nav-trend-chart` and `nav-composition-table` below / on drill.
  - *Pro:* fastest "what am I worth today, tax-adjusted, and which way am I moving" read; matches 2.1.1's "single trustworthy whole-position number." *Con:* de-emphasizes structure + trend, which this archetype actively reviews.
- **Option B — Trend-first.** `nav-trend-chart` is the hero; headline NAV + deltas as a compact header strip; composition on drill.
  - *Pro:* foregrounds "improving / holding / declining over a meaningful horizon" (2.1.2's framing) + the real-purchasing-power view; strong fit for the monthly-review cadence. *Con:* the headline number becomes a chart annotation; composition traceability is a click away.
- **Option C — Breakdown-first.** `nav-composition-table` anchors the surface (it already builds up to NAV at its foot); headline/deltas/chart sit above as context.
  - *Pro:* directly honors 2.1.5's "the single headline number doesn't hide its structure" + the archetype's categorization precision; NAV is provably built from parts. *Con:* dense as a landing view; de-emphasizes trend.

- **UX recommendation:** a **dense single-canvas composition anchored number-first** — `nav-headline` + `nav-delta-panel` head the page, `nav-trend-chart` follows, `nav-composition-table` anchors the foot — so all five are co-visible on one scroll (density is a feature for this archetype; avoids hiding structure behind tabs). This is essentially **A as the above-the-fold ordering + C always present below**, rather than an either/or. Whether the regions are one scroll vs. tabbed, and the above-the-fold ordering, is the F/CTO call at Step 3. *(If the surface is tabbed instead of single-scroll, that couples to Open Decision 1 of §2.4 — the global nav model — so it may resolve together at Step 3.)*

### Open Decision 2 — (none beyond OD1 for this cluster)
The granularity toggle (monthly/weekly/daily), inflation co-draw, fixed horizons/windows/reference-dates are all PRD-determined — no UX option space. Noting explicitly so the walk-through doesn't expect more decisions here than there are.

---

## 8. Scope-creep / ambiguity flags for PM *(route to PM, not designed around)*

### Flag PM-1 — Is §2.4.4's staleness-marking surface list exhaustive or illustrative? — ✅ **RESOLVED as GLOBAL principle D1 (F/CTO-ratified)**
**Resolution:** F/CTO ratified the **"mark all"** reading as a **global principle D1** (logged in `temp/phase-2-decisions-log.md`): *the staleness-marking surface scope is **illustrative, not exhaustive** — every derived aggregation that consumes stale-account data carries the staleness marker; aggregations are never silently presented as fresh.* This applies across §2.2 / §2.3 / §2.5 / §2.6 too — **not re-litigated per cluster.** Folded into §6: headline NAV (2.1.1), delta panel (2.1.3), reference dates (2.1.4), and `nav-asof-timestamp` are all marked staleness-capable. My original "mark all" lean was the faithful reading.
- *Original ambiguity (retained for history):* §2.4.4's literal list named only the §2.1.2 trajectory + §2.1.5 composition, omitting the headline NAV / delta panel / reference dates — yet all are aggregations consuming the same data.

### Flag PM-2 — Confirm the value-semantics pin (§1) and the "Hub shows no NAV" call. *(confirmation — touches locked §2.4)*
The §1 pin defines `account-row` "current value" = gross / current / staleness-marked, and asserts the `Accounts Hub` presents no NAV (NAV is owned by the Net Worth surface; Hub shows at most a labeled "Gross total"). This is consistent with §2.4's locked wording (it doesn't reopen the flow) but it **assigns meaning** that Visual/Frontend will render. Confirm: (a) per-account values are gross-only everywhere; (b) the Hub shows no NAV / no tax-adjusted per-row number.

### Flag PM-3 — NAV's dependency on §2.5 tax computation (calculation-unavailable behavior). *(inter-cluster dependency)*
NAV (2.1.1) subtracts Realized + Unrealized Tax Liabilities, which are §2.5 computations. When §2.5 can't compute (brackets unset, no tax data), NAV is structurally incomplete. My flows render the missing component explicitly and mark NAV incomplete (never silently drop it). Confirm this is the intended V1 behavior, and confirm the §2.1↔§2.5 ordering expectation (does NAV ever render before §2.5 is set up at bootstrap?). *(Will also surface when §2.5 is drilled.)*

---

## 9. Provisional screen / surface inventory (for the eventual Visual handoff — NOT final until Step 3 lock)
*Names are proposed shared vocabulary across PM / Visual / Frontend. Region-vs-screen status resolves with Open Decision 1.*

| # | Surface / region | Type | Flow | Traces |
|---|---|---|---|---|
| 1 | `Net Worth` | full screen (surface) | container | 2.1.* |
| 2 | `nav-headline` | region | F-2.1.A | 2.1.1 |
| 3 | `nav-delta-panel` | region | F-2.1.A | 2.1.3 |
| 4 | `nav-reference-dates` | region | F-2.1.A | 2.1.4 |
| 5 | `nav-trend-chart` | region (interactive) | F-2.1.B | 2.1.2 |
| 6 | `nav-trend-chart` (drill state) | interaction state | F-2.1.B | 2.1.2 |
| 7 | `nav-composition-table` | region (expandable) | F-2.1.C | 2.1.5 |
| 8 | `nav-composition-table` (category-expanded) | interaction state | F-2.1.C | 2.1.5 |

Cross-cutting components consumed/authored here: `stale-data-marker` (consumed from §2.4.4), `nav-asof-timestamp` ("NAV as of …" — the Lock 8 materialization-recency signal), `account-row` value semantics (pinned in §1, shared with §2.4 Hub), granularity-control, inflation-line treatment, subtotal-row, metric-card (for headline/deltas). Cross-link: `nav-composition-table` row → `Account Detail` (§2.4).

---

## 10. PRD §2.1 story → flow traceability (for the PM consult)
| PRD story | Covered by | Notes |
|---|---|---|
| 2.1.1 Current NAV | F-2.1.A (`nav-headline`) + F-2.1.C (build-up) | Four-component tax-adjusted number; structure traceable in composition. |
| 2.1.2 NAV over time | F-2.1.B (`nav-trend-chart`) | 60-mo window; nominal + IA co-drawn; granularity toggle; inflection drill. |
| 2.1.3 Multi-horizon delta panel | F-2.1.A (`nav-delta-panel`) | 5 fixed horizons; $/%; IA column on 1Y/3Y/5Y. |
| 2.1.4 NAV at three reference dates | F-2.1.A (`nav-reference-dates`) | This/Prior Month + Prior Year-End; nominal + prior-Yr-$. |
| 2.1.5 Composition | F-2.1.C (`nav-composition-table`) | Account rows → subtotals → NAV; expandable; unrealized G/L. |
| 2.1.6 Investment uses market value | §1 value-semantics pin + F-2.1.C rows | Valuation rule; not a screen. |
| 2.1.7 NAV is the user's (full-household) | §0.2 constraint (all flows) | Single aggregated household NAV; no scope UI; own data only. Not a screen. |

**No flow exceeds its PRD story.** All V1/V2 boundaries respected (fixed window/horizons/reference-dates; no scope UI; inflation not toggleable). Items requiring PM resolution isolated as Flags PM-1/2/3 rather than designed around.

---

## 11. Status / next
- **✅ §2.1 LOCKED (2026-05-28):** PM traceability PASS; PM-2 + PM-3 confirmed; **PM-1 ratified as global principle D1** (staleness marking is illustrative-not-exhaustive — mark all derived aggregations; logged in `temp/phase-2-decisions-log.md`). D1 fold-in landed in §6 (headline NAV / deltas / reference dates / `nav-asof-timestamp` all marked staleness-capable). PM-2 handoff caveat captured in §1.3 (Hub "Gross total" stays labeled "not net worth," presentational mirror only).
- **Draft coverage:** flow structure complete; value-semantics pin (§1) with Lock 8 (NAV materialization) + Lock 15 (as-of read) citations; all V1 failure surfaces in §6 (stale/re-auth, NAV-materialization recency, tax-component-unavailable, insufficient-history, CPI-U-unavailable, manual-contribution).
- **Carried to F/CTO Step 3 walk-through:** Net Worth information hierarchy (Open Decision 1 — number/trend/breakdown; 3 options + recommendation; parked for Step 3 alongside the nav-model decision; ADR captured then).
- **PM flags status:** PM-1 ✅ RESOLVED (→ D1 global); PM-2 ✅ CONFIRMED; PM-3 ✅ CONFIRMED.
- **Next:** §2.2 asset allocation (cluster 3 of 6). Then §2.3 → §2.5 → §2.6, the Step 3 F/CTO walk-through, then wireframing (Step 4).
- **No wireframing** until the Step 3 gate confirms the flow set.
