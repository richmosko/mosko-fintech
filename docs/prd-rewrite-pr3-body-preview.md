# PR 3 body-gate-6 — §2.6 (Monthly report) body preview — FINAL BODY GATE

> Standalone preview of §2.6 body draft, for body-gate-6 review. **This is the final body gate of PR 3.**
>
> **§2.6 = 6 stories** (5 primary + 1 supporting). Shape inventory:
> - §2.6.1 = **shape-C** (most complex: opener + 6 sub-blocks + **ordered list (6 items)** + **markdown table (6×3)**)
> - §2.6.2 through §2.6.5 = **shape-B** (opener + 8–10 sub-blocks + V1/V2 boundary each)
> - §2.6.6 = **NEW shape-B-Supporting pattern** (first Supporting story with sub-blocks in §2; elevates new Sec axis "snapshot store as derivative surface")
>
> **21 routing-flag entries** (12 Architect + 6 Sec + 3 process records) — largest §2.x flag block.
>
> **§2.6.6 title rename**: "Monthly report is mine, not anyone else's" → "the user's" — **6th and final instance** of pattern across all §2.x supporting stories.
>
> **VP closures at body-gate-6:** VP-3 (σ-1/σ-2/σ-3 framing preserved in body) + VP-4 (V1/V2 boundary blocks confirmed as standard shape-B structure) + VP-13 + VP-14 (markdown table + code block precedents) all close. **No new VPs surfaced.**
>
> **Compression: 198 source → ~155 body (~22%)**. App C entries: 6. App B entries: 21.

---

## §2.6 body draft (proposed for PRD.md integration)

### 2.6 Monthly report

#### Primary stories

**2.6.1 Monthly report composition and section ordering.**

V1 renders the monthly report as a single standalone document with a fixed sequence of six named sections — **Account Holdings → NAV Performance → Asset Allocation → Rebalancing Targets → Cash Flow → Estimated Taxes** — composed from the §2.1–§2.5 surfaces the live app already supplies, with Historical Expenditures rendered inline within the Cash Flow section and an owner-identification trust-name header at the top, so the canonical V1 deliverable the user relies on today carries forward into V1 with the same shape and the same reading order, and every report section traces unambiguously back to the live surface that authored its content.

**Composition contract scope.** §2.6.1 is the composition contract for the monthly report-as-artifact: which sections appear, in what order, with what header, and which upstream §2.1–§2.5 surfaces author each section's content. §2.6.1 does **not** redefine any individual section's content shape — each section's content authority lives in the originating § (e.g., the Account Holdings rendering is owned by §2.1.5, not re-specified here). §2.6.1 does **not** own free-text Rebalancing Targets capture (that's §2.6.2), generation cadence or format or snapshot semantics or retention (those are §2.6.3 / §2.6.4), staleness-marker rendering (that's §2.6.5), the owner-identification config storage shape (that's §2.6.4 — §2.6.1 names the header slot but §2.6.4 owns the config), or tenant isolation on the report read path (that's §2.6.6 Supporting). §2.6.1's job is to lock the **section list, the section order, and the cross-section data-source map** for V1.

**Section list and ordering — V1 fixed six-section sequence.** The V1 monthly report carries six sections in the following fixed order, parity-exact with the existing Finance_Report layout (parity-matrix lines 98 – 109):

1. **Account Holdings** — the integrated NAV-buildup table.
2. **NAV Performance** — comparison anchor at three reference dates, multi-horizon delta panel, and 60-month inflation-normalized NAV chart.
3. **Asset Allocation** — per-asset Cat × Sub-Cat allocation table plus asset-allocation visualizations.
4. **Rebalancing Targets** — free-text commentary captured by the user each month.
5. **Cash Flow** — Income + Expenses table with Historical Expenditures chart rendered inline immediately below the Expenses table per parity-matrix lines 105 – 106.
6. **Estimated Taxes** — the three-column tax-relevant income decomposition plus the Federal and California FTB quarterly tables.

The order is **V1-fixed, not user-configurable**: V1 does not ship a settings UI for reordering or hiding sections. Every V1 monthly report renders all six sections in this order. The parity grounding is the canonical existing Finance_Report month-after-month reading sequence the F/CTO has shipped against for years; locking the order V1 removes one decision surface from the V1 build and preserves the reading pattern unchanged.

**Cross-section data sources.**

| Report section | Upstream surface(s) | Composition note |
|---|---|---|
| **Account Holdings** | §2.1.5 (composition buildup) | The §2.1.5 integrated NAV-buildup table is the canonical Account Holdings rendering — per-account values + unrealized G/L grouped by account-type, with subtotals running Total Non-RE → Gross Total → Debt → Realized Tax Liabilities → Unrealized Tax Liabilities → NAV per parity-matrix line 99. |
| **NAV Performance** | §2.1.2 + §2.1.3 + §2.1.4 | Three §2.1 surfaces compose into one report section: §2.1.4 NAV-at-three-reference-dates table, §2.1.3 multi-horizon NAV-delta panel, and §2.1.2 NAV chart. |
| **Asset Allocation** | §2.2.2 + §2.2.3 | Per-asset Cat × Sub-Cat allocation table + asset-allocation visualizations per parity-matrix line 101. |
| **Rebalancing Targets** | §2.6.2 | The one report-section whose content the §2.1–§2.5 live surfaces do **not** author. |
| **Cash Flow** | §2.3.2 + §2.3.4 | §2.3.2 Income + Expenses Category × Month/Q1-Q4/YTD tables primary; §2.3.4 Historical Expenditures chart renders **inline within the Cash Flow section** (below the Expenses table). |
| **Estimated Taxes** | §2.5.1 + §2.5.3 | §2.5.1 three-column tax-relevant income decomposition + §2.5.3 Federal + California FTB quarterly tables. §2.5.4 NAV-component values appear on Account Holdings via §2.1.5, not as Estimated Taxes section rows. |

**Owner-identification header.** Trust-name string (parity example: "*THE RICHARD MELVIN MOSKO, JR. 2023 TRUST*" per parity-matrix line 94) + month/year stamp. Administrative label, **not a tenant-isolation boundary or scope filter** — report content remains full-household. Config storage shape is §2.6.4's surface.

**Sections dropped from parity.** Amortized Expenses (Big Ticket Fund) dropped per F/CTO Phase 0.5 call; Historical Expenditures as standalone top-level section collapses into Cash Flow inline rendering.

**V1/V2 boundary.**
*V1:* fixed six-section sequence in parity-exact order; Historical Expenditures inline within Cash Flow; owner-identification trust-name + month/year header; composition map normative; Amortized Expenses dropped; §2.5.4 NAV-component lines on Account Holdings.
*V2+:* user-configurable section ordering (ω-2); user add/remove sections (ω-3); user-defined custom sections; multi-scope reports (parity-matrix line 180 V2+); reintroduction of Big Ticket Fund / Amortized Expenses; alternative cross-section composition.

*Traces: see Appendix C → 2.6.1.*

---

**2.6.2 Rebalancing Targets free-text commentary.**

V1 provides an editor surface where the user authors the **Rebalancing Targets free-text commentary** that appears on each month's report — written by the user at report-generation time, keyed visually to the `$ ReAlloc` deltas from §2.2.2 as the data grounding, persisted per-report alongside the rest of the month's snapshot — so the action-item narrative the existing Finance_Report carries forward unchanged into V1 in the one parity surface §2.1–§2.5 do not author themselves.

[Body content with 8 sub-blocks preserved verbatim: Capture mechanism scope / **Free-text user-authored under σ-1** (VP-3 closure point — σ-1/σ-2/σ-3 framing here) / Sub-section structure (Cash/Bonds/Equity/Alternatives parity-fixed V1) / `$ ReAlloc` side-by-side reference rendering / Editor format (plain text V1, line breaks preserved) / Pre-population behavior (blank by default, explicit "copy from prior month" affordance) / Capture timing (author-before-generate, part of §2.6.3 flow) / Per-report persistence commitment / Write-path RLS commitment. Plus V1/V2 boundary.]

*Traces: see Appendix C → 2.6.2.*

---

**2.6.3 Report generation cadence, trigger, and output format.**

V1 makes the monthly report available both on an automated cadence (so the user doesn't have to remember to generate it) and on user-demand (so the user can regenerate when amended data lands or when a fresh as-of-today view is desired). The canonical surface is an in-app rendered web page with PDF export available on demand.

[Body content with 9 sub-blocks: Generation surface scope / Generation cadence τ-1 (cron + on-demand) / Output format υ-1 (in-app web + PDF export) / Authoring-step placement / Cron schedule default (1st of month for prior month) / User-on-demand trigger and target-month selection / Idempotency / regeneration semantics (overwrite semantics, no revision history V1) / PDF export / "Generated" state semantics (3-state lifecycle: not-yet-triggered → pending → generated) / Cron failure handling. Plus V1/V2 boundary.]

*Traces: see Appendix C → 2.6.3.*

---

**2.6.4 Snapshot, historical retention, and report identity.**

V1 freezes the rendered surfaces at generation time so every prior month is retrievable as the artifact it was the day it shipped, and a single owner-identification string the user configures once drives the trust-name header at the top of every report — so the report behaves like the existing-system Finance_Report PDFs do today: a stable, archived record of the month as the user closed it, not a re-computed view that drifts when upstream transactions change.

[Body content with 10 sub-blocks: Persistence-layer scope / Snapshot-vs-live semantics under φ-1 / Historical retention under χ-1 / Retention horizon (indefinite V1) / Owner-identification header under ψ-1 / ADR-005 settings store extension / Snapshot shape commitment / Owner-identification at render time (snapshot, not live) / **Staleness-marker live-read carve-out** (deliberate exception) / Snapshot regeneration semantics / Snapshot read path for in-app view + PDF export. Plus V1/V2 boundary.]

*Traces: see Appendix C → 2.6.4.*

---

**2.6.5 Staleness markers on report surfaces.**

V1 ensures that when a contributing account is in a credential-error / re-auth state at the moment the user views (or generates) the monthly report, every report section sourced from that account's data carries a clear visual staleness marker — so the report never silently presents stale numbers as authoritative, and the user sees at a glance which accounts need to be fixed to restore the report's integrity. The report still renders; the marker is the integrity contract, not a block.

[Body content with 6 sub-blocks: Scope / α′-1 lock (generate-with-markers, not block-with-warning) / Marker visual shape (inline per-section + report-level banner) / Trigger states (all four §2.4.4 states trigger uniformly) / Sections excluded from marking (§2.6.2 commentary + §2.6.4 header) / PDF export markers (live-read at export moment) / Historical-report markers (reflect current state, not historical). Plus V1/V2 boundary.]

*Traces: see Appendix C → 2.6.5.*

---

#### Supporting stories

**2.6.6 Monthly report is the user's, not anyone else's.**

V1 ensures that when the user views the monthly report — current month or any historical month, in-app view or PDF export — the only reports surfaced are the ones generated from the user's own tenant's data, with zero possibility that another tenant's snapshot, commentary, owner-identification header, or generation state leaks into the user's view. The report is the user's; the persistence and read path enforce that without requiring the user to think about it.

[Body content with 5 sub-blocks (NEW shape-B-Supporting pattern): Scope (tenant-isolation read-path Supporting) / Named-surface scoping / Scope-attribute-not-isolation-boundary (sixth-instance canonical clause) / **Snapshot store as derivative surface** (NEW Sec axis — first derivative-persistence layer in §2; flagged for §4 Sec attention) / Multi-scope V1/V2. Plus V1/V2 boundary.]

*Traces: see Appendix C → 2.6.6.*

*Routing flags affecting §2.6: see Appendix B (created in PR 10; pending consolidation).*

---

> **Note**: Full §2.6 body with all sub-blocks preserved verbatim is what lands in PRD.md on integration. This preview shows §2.6.1 in full and §2.6.2–§2.6.6 with bracketed summaries for length. The actual integration preserves every sub-block verbatim per shape-B preservation pattern.

---

# PR 3 CLOSURE SUMMARY (per PM Deliverable 8)

## Total compression across §2.1–§2.6

| §2.N | Source lines | Rewritten | Compression | App C entries | App B entries |
|---|---|---|---|---|---|
| §2.1 | 53 | ~35 | 34% | 7 | 5 |
| §2.2 | 37 | ~22 | 40% | 4 | 7 |
| §2.3 | 49 | ~32 | 35% | 5 | 11 |
| §2.4 | 68 | ~50 | 26% | 5 | 12 |
| §2.5 | 164 | ~145 | 12% | 5 | 17 |
| §2.6 | 198 | ~155 | 22% | 6 | 21 |
| **Total** | **569** | **~439** | **~23%** | **32** | **73** |

## VP-flag final state (14 total)

**Closed during body gates (6):** VP-1, VP-3, VP-4, VP-5, VP-13, VP-14.

**Verify-pass-deferred (8):** VP-2 + VP-11 (Sec-verdict-vs-trace duplication across §2.4/§2.5/§2.6); VP-12 (process-records in App B — broader consolidation strategy); VP-7 + VP-9 (§3.3 parity-test framework interactions); VP-6 + VP-8 + VP-10 (light trace editorial cleanup).

## Pattern catalog established for PR 4–10

- Shape-A / Shape-B / Shape-C per-story shape categorization
- Voice-cleanup of first-person references in preserved shape-B sub-blocks
- `§`-prefix normalization at first encounter (16 instances applied across §2.4 + §2.5 + §2.6)
- "Mine/my → the user's" supporting-story title rewrite (6 instances)
- Shape-B-Supporting story shape (§2.6.6 first instance — pattern available for future Supporting stories elevating new axes)
- Inline markdown tables / numbered-step paragraphs / fenced code blocks / ordered lists inside story body
- Cross-reference no-new-flag entries in App B
- Process-records vs. forward-looking-flags distinction in App B

## Ratification track

- Structure gate: 6-for-6 ratify (1 PM-recommendation override at Q-S4)
- Body gates: 6-for-6 ratify (Q-B7 pending); zero substance amendments; all "α — accept as drafted"
- Q-B2 sub-question at body-gate-1: F/CTO β = §2-top framing line (VP-5 closure)
- VP-1 silent-closure at body-gate-4
