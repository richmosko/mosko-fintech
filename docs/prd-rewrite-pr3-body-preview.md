# PR 3 body-gate-5 — §2.5 (Estimated taxes) body preview

> Standalone preview of §2.5 body draft + App C extension entries, for body-gate-5 review.
>
> **§2.5 is the largest §2.x sub-section** (~164 source lines, 5 stories). Shape inventory:
> - §2.5.1 / §2.5.2 / §2.5.3 / §2.5.4 = **shape-B** (opener + multiple in-body sub-blocks + V1/V2 boundary)
> - §2.5.5 = **shape-A**
>
> **3 new §2.5-specific patterns established** (all preserved verbatim under Q-S4 = β):
> - §2.5.2 inline markdown table (5×3 routing of `tax_character` enum → Federal schedule)
> - §2.5.3 inline `(1) (2) (3)` numbered-step paragraphs (Federal + California computation walks)
> - §2.5.4 fenced code block (3-line Unrealized Tax Liability formula)
>
> **17 routing-flag entries** — largest §2.x flag block (12 forward-looking Architect flags + 5 process records: dropped-flag historical / PM-default acceptance summary / ADR-006 alongside-lock / Sec product-disclaimer integration / Sec at-lock verdict).
>
> **§2.5.5 title rename** (fifth instance of "mine/my → user's" pattern after §2.1.7 / §2.2.4 / §2.3.5 / §2.4.5).
>
> **Compression: 164 source → ~145 body (~12%)** — lowest §2.x ratio so far. Shape-B preservation across 4 stories + inline table + code block + numbered-step paragraphs preserves more than the structure-proposal estimate assumed.
>
> **3 new VPs:** VP-12 (process-records-in-routing-flag-block structural mismatch); VP-13 (markdown-table precedent — closes at body-gate-6); VP-14 (code-block precedent — closes at body-gate-6).

---

## §2.5 body draft (proposed for PRD.md integration)

### 2.5 Estimated taxes

#### Primary stories

**2.5.1 Tax-relevant income decomposition (Income / ST CG / LT CG).**

V1 decomposes the user's realized income for the current tax year into three columns — **Ordinary Income**, **Short-Term Capital Gain**, and **Long-Term Capital Gain** — at the Sub-Category granularity the user's taxonomy uses, so the user reads at a glance which buckets contribute to which tax-character class and so the same decomposition feeds the §2.5.3 progressive bracket computation cleanly per jurisdiction.

**Input sources.** Ordinary Income contributions come from §2.3.1's cash-flow taxonomy: transactions whose Sub-Cat is **user-marked tax-relevant** on the Income side of §2.3.1 (salary, dividends, interest, bond premiums, and any other ordinary-income Sub-Cats the F/CTO seed marks) contribute to the Ordinary Income column. Capital-gain contributions come from the realized-G/L pairing of §2.4.3 transactions: each `sell` transaction (Plaid-sourced or manual) is paired against its lot-level cost basis per §2.4.3, the per-pairing gain or loss is decomposed into Short-Term or Long-Term, and the resulting ST CG / LT CG amounts are surfaced under the Sub-Cat the underlying holding carries per §2.2.1 (e.g., an Equity → US-Index_Non_Sector holding sold at a gain contributes ST CG or LT CG under that Sub-Cat row). Two input sources, one decomposition surface, joined by Sub-Cat.

**Tax-relevance and tax-character marking at the Sub-Cat level.** V1 carries **two attributes** on each Sub-Cat in the §2.3.1 cash-flow taxonomy and on each Sub-Cat in the §2.2.1 asset taxonomy that holds securities subject to capital-gain realization: a **`tax_relevant` boolean** and a **`tax_character` enum** with V1 values `ordinary` / `qualified_dividend` / `tax_exempt_interest` / `long_term_capital_gain_eligible` / `short_term_only`. The boolean gates whether a Sub-Cat contributes to §2.5.1 at all; the enum drives downstream §2.5.3 bracket-schedule routing.

**Holding-period (ST vs LT) determination.** Per §2.4.3's existing-system parity: each `sell` transaction's holding-period classification derives from the **Open Date** of the underlying lot relative to the sale's `Close Date`. V1 uses the existing-system `calculateSales`-equivalent output as the source-of-truth: holding period > 365 days → LT, otherwise → ST. **Section 1256 60/40 user-classified at the Sub-Cat level** via the existing `Volatility-60/40` Sub-Cat per ADR-004 Decision D. **User-marked wash-sale flag** on the underlying sale transaction excludes the disallowed-loss amount from the ST/LT column; auto-detection is V2+.

**Tax-year scope.** V1 scopes decomposition to the **current calendar year** (Jan 1 – Dec 31), Federal default; California FTB year-boundary aligned. The decomposition recomputes live as transactions land and as user-marked tax-relevance / tax-character attributes update.

**Layout.** Single Sub-Cat-row × 3-column table with Cat-group section headers (Income Cat group as one section; Capital Gains Cat groups as a second section grouped by asset Cat — Equity / Bonds / Alternatives etc.). Total row foots the table; per-Cat-group subtotals as group aggregates.

**V1/V2 boundary.** [V1/V2 split content preserved verbatim — see full draft in `docs/prd-rewrite-pr3-body-preview.md` for complete content.]

*Traces: see Appendix C → 2.5.1.*

**2.5.2 Tax-bracket inputs (Federal + California FTB parallel).**

V1 supports the user entering and maintaining Federal and California FTB tax-bracket schedules and standard deductions for the current tax year through a V1 settings UI, so the §2.5.3 progressive bracket computation has the per-jurisdiction grammar it needs to estimate the user's actual obligations against §2.5.1's three-column realized-income decomposition.

**Settings UI scope.** A V1 settings UI holds, per jurisdiction (Federal and California FTB), the **bracket schedule(s)** that apply to the user's filing status for the **current tax year**, plus a **standard deduction** scalar.

**Federal bracket schedules (two per (λ) lock).** Federal carries **two parallel bracket schedules** — an **ordinary-income schedule** (~7 rows) and a **separate LT capital-gains schedule** (~3 rows: 0% / 15% / 20%) — plus a single Federal standard deduction.

**California FTB bracket schedule (single per (κ) lock).** California FTB carries a **single ordinary-income bracket schedule** (~9 rows) plus a single California standard deduction. California taxes LT capital gains as ordinary income.

**Routing the §2.5.1 `tax_character` enum into bracket schedules:**

| §2.5.1 column | `tax_character` enum | Federal schedule routed to |
|---|---|---|
| Ordinary Income | `qualified_dividend` | LT CG |
| Ordinary Income | `tax_exempt_interest` | (excluded from Federal computation) |
| Ordinary Income | `ordinary` / `short_term_only` / `long_term_capital_gain_eligible` / default | Ordinary |
| ST CG | any | Ordinary |
| LT CG | any | LT CG |

**Settings-UI plumbing extends §2.3.2 store per ADR-005.** Whether V1 dedups this richer surface into the §2.3.2 settings store as additive tables or splits it into a separate tax-bracket store is **Architect Phase 3**.

**Update cadence (user-manual at tax-year rollover).** V1 has no live tax-data API; the user updates bracket rows + thresholds + standard deduction at tax-year rollover.

**Standard-deduction filing-status awareness.** V1 carries a single standard-deduction scalar per jurisdiction; filing-status enum is V2+.

**Applied-rate brief echo on §2.5.3 tax tables (per δ-2 lock).** Each §2.5.3 tax table carries a one-line caption naming the applied marginal rates.

**V1/V2 boundary.** [V1/V2 split preserved verbatim.]

*Traces: see Appendix C → 2.5.2.*

**2.5.3 Quarterly estimated payment computation + IRS/FTB account tracking.**

V1 computes each tax-year quarter's estimated payment against current realized income and bracket schedules, rendering a per-jurisdiction table showing the prior-year tax balance for reference, four quarterly estimated payments, year-to-date payments tracked through the IRS and FTB account ledgers, and the Estimated Funds Due as the gap.

**Per-jurisdiction parallel tables.** §2.5.3 renders two parallel tables — Federal Income Taxes + California State Income Taxes (CA FTB).

**Computation engine — progressive bracket math with standard deduction.** The engine consumes §2.5.1's three-column decomposition + §2.5.2 bracket schedules + standard deduction and produces a per-jurisdiction expected annual tax liability with the quarterly breakdown.

Federal computation in concrete steps: (1) sum Ordinary Income column (excluding qualified_dividend and tax_exempt_interest-tagged contributions) + ST CG column → **Federal ordinary income input**; (2) subtract Federal standard deduction → **Federal ordinary taxable income**; (3) walk Federal ordinary bracket schedule progressively → **Federal ordinary tax**; (4) sum LT CG column + qualified_dividend-tagged Ordinary Income contributions → **Federal LT CG income input**; (5) walk Federal LT CG bracket schedule progressively → **Federal LT CG tax**; (6) sum (3) + (5) → **Federal expected annual tax liability**.

California computation collapses to a single schedule per (κ) lock: (1) sum all non-excluded contributions → **CA taxable income input**; (2) subtract CA standard deduction → **CA taxable income**; (3) walk CA ordinary bracket schedule progressively → **CA expected annual tax liability**.

**Annual → quarterly cadence (μ-2 bracket-only locked).** The expected annual liability divided by four yields the **per-quarter expected installment** — V1's sole quarterly-installment-sizing approach. **V1 does not compute a safe-harbor floor** — V2+ refinement.

**IRS + FTB account integration.** The IRS account and FTB account are V1 instances of §2.4.2 manual non-Plaid accounts.

**Estimated Funds Due — overpayment / refund surfacing.** Negative-single-line rendering when YTD Paid exceeds Sub-Total.

**Applied-rate caption echo (δ-2 carry).** Federal table caption "*Federal ordinary: X% / Federal LT CG: Y%*"; California table caption "*California: Z%*".

**Quarterly-due-date cadence surfacing.** V1 ships reactive surfacing only — no pre-emptive notification.

**V1/V2 boundary.** [V1/V2 split preserved verbatim, including ADR-002 §3.0 money-movement non-goal clause.]

*Traces: see Appendix C → 2.5.3.*

**2.5.4 Realized + Unrealized Tax Liability line items (NAV components).**

V1 derives §2.1.1 NAV's two tax-component line items — **Realized Tax Liability** and **Unrealized Tax Liability** — consistently from the user's current Federal + California FTB tax state and surfaces them as the values §2.1.5's composition buildup renders.

**Cross-section contract closure.** §2.5.4 is the story that closes the cross-reference contract §2.1.1 NAV definition and §2.1.5 composition buildup hold open.

**Realized Tax Liability — derivation.** Realized Tax Liability is the **current accrued Federal + California FTB tax obligation net of payments already made**: the Estimated Funds Due (IRS) gap from §2.5.3 Federal table summed with the Estimated Funds Due (FTB) gap from §2.5.3 California table.

**Unrealized Tax Liability — derivation (ο-a locked simplified marginal × aggregate G/L).**

```
Unrealized Tax Liability = (Federal_LT_CG_top_bracket_rate × aggregate_unrealized_G/L_taxable)
                        + (CA_top_marginal_rate × aggregate_unrealized_G/L_taxable)
```

where `aggregate_unrealized_G/L_taxable = sum across V1-included taxable-account holdings of (current market value − aggregate cost basis)`. **Tax_character enum routing is NOT used for V1 Unrealized**, and the §2.5.3 progressive bracket computation engine is NOT consumed — both intentional V1 simplifications under ο-a.

**Tax-advantaged account exclusion (per (π) lock).** Unrealized Tax Liability **excludes holdings in tax-advantaged accounts** (`tax-deferred` or `tax-free` per ADR-002 §1.6).

**Single-line-per-component rendering (per (ρ) lock).** Two NAV-component values — one Realized + one Unrealized scalar (Federal + CA summed each).

**Tax-year scope.** Current-tax-year computed; live-recompute on transaction changes, market-value changes, bracket-table edits.

**V1/V2 boundary.** [V1/V2 split preserved verbatim, including Sec product-disclaimer:]

***This estimate may understate actual tax owed if any portion of unrealized gain would be realized at short-term rates (ordinary income); users should treat the Unrealized Tax Liability as an LT-aware floor estimate, not a precise tax forecast.***

*Traces: see Appendix C → 2.5.4.*

#### Supporting stories

**2.5.5 Tax surfaces are the user's, not anyone else's.**

V1 surfaces only the requesting user's own income, holdings, and tax obligations across the §2.5.1 / §2.5.3 / §2.5.4 surfaces (and the §2.5.3 δ-2 applied-rate captions); no possibility of another user's data appearing. Tax surfaces aggregate into a single **full-household tax view by default**, spanning every ownership scope held (e.g., personal, trust, retirement custodial, HSA), with the §2.5.4 (π) tax-advantaged exclusion applied as a data-attribute filter on the Unrealized aggregation but not as a scope-isolation mechanism. The result is tax surfaces the user can trust absolutely, reflecting the entire household position the way the user thinks about it, and honoring the system's multi-tenant commitment from day one even though V1 ships to a single user. Per-scope tax-surface rendering and scope-aware UI filtering across all three named surfaces are V2+; the data model carries scope on each account from V1 (per ADR-004 Decision B) so the V2 expansion ships without data migration. **Scopes are user-owned data labels, not V1 isolation boundaries** — tenant isolation is the V1 isolation boundary; scopes are first-class attributes within a single tenant. The §2.5.4 `tax_treatment` filter (per (π) lock — `taxable` / `tax-deferred` / `tax-free` per ADR-002 §1.6 three-way tagging) is a data-attribute inclusion filter on the §2.5.4 Unrealized aggregation surface, distinct from both tenant isolation and scope — the three V1 attributes (`tenant_id` for isolation; `scope` as data label; `tax_treatment` as inclusion filter on a specific aggregation) compose cleanly without conflation.

*Traces: see Appendix C → 2.5.5.*

*Routing flags affecting §2.5: see Appendix B (created in PR 10; pending consolidation).*

---

> **Note:** Above body draft includes condensed V1/V2 boundary blocks for preview length; the full §2.5 body integration into PRD.md preserves V1/V2 boundary blocks verbatim per shape-B preservation pattern. See PM Deliverable 1 in conversation for full content.
