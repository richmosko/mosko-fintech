# Phase 2 — UX Flow Document: §2.6 Monthly Report Cluster (CONVERGENCE)

**Cluster:** §2.6 — Monthly report (composition contract; Rebalancing Targets commentary; generation cadence/trigger/format; snapshot/retention/identity; staleness markers; tenant isolation).
**Author:** UX Designer (`phase-2-ux-design` team).
**Status:** DRAFT — flows only. Pre-wireframe. Pre-PM-traceability-consult. **Final cluster (6 of 6).**
**Phase 2 step:** Step 2 (the **convergence cluster** — composes §2.1–§2.5 surfaces at a snapshot as-of; every cross-cluster commitment converges here).
**Date:** 2026-05-28.
**Companions:** §2.1 (NAV/Account-Holdings + incomplete-NAV), §2.2 ($ReAlloc reference + allocation section), §2.3 (Cash Flow section + as-of pin §1.1 + non-goal fence), §2.4 (`stale-data-marker` + credential states + pending-queue pattern), §2.5 (Estimated Taxes section + money-movement fence + bootstrap-incomplete). Global decision log: `temp/phase-2-decisions-log.md`.

---

## 0. Scope, inputs, and load-bearing constraints

### 0.1 PRD stories in this cluster
- **2.6.1** — Composition contract: six fixed-order sections — **Account Holdings → NAV Performance → Asset Allocation → Rebalancing Targets → Cash Flow → Estimated Taxes** — + owner-identification header; Historical Expenditures inline within Cash Flow; cross-section data-source map. Not user-configurable.
- **2.6.2** — Rebalancing Targets free-text commentary: editor; four fixed sub-sections (Cash/Bonds/Equity/Alternatives); §2.2.2 `$ ReAlloc` side-by-side reference; plain text + line breaks; blank-by-default + "copy from prior month"; author-before-generate; per-report persistence; write-path RLS.
- **2.6.3** — Generation cadence/trigger/format: **dual-trigger** (monthly cron + user-on-demand); in-app web page canonical + PDF export on demand; 3-state lifecycle; overwrite-semantics regeneration; pending-report queue; cron-failure → system log + on-demand fallback.
- **2.6.4** — Snapshot/retention/identity: frozen-at-generation snapshot; indefinite retention; owner-id header config (3rd ADR-005 settings field); rendered-value-level snapshot; owner-id snapshot-not-live; **staleness live-read carve-out**; overwrite regeneration; tenant-scoped read.
- **2.6.5** — Staleness markers: α′-1 generate-with-markers; per-section inline indicator + report-level banner naming stale accounts; all four credential states trigger uniformly; §2.6.2 + §2.6.4 excluded; live-read at render incl. historical + PDF.
- **2.6.6** *(supporting)* — Monthly report is the user's; tenant-isolation read path.

### 0.2 Load-bearing constraints (fences — many converge here)
- **PERMANENT NON-GOALS converge (both apply to report content):** **money movement** (ADR-002 §3.0 — the Estimated Taxes section shows obligations + Estimated Funds Due but **NO pay/schedule/transfer affordance**) AND **budgeting/variance** (ADR-002 §1.2 — the Cash Flow section shows targets as **static reference only**, no progress bar / over-under / variance; the §2.3 §7A Visual fence applies to the report's Cash Flow section too; **no target line** on the inline Historical Expenditures chart).
- **No auto-generated rebalance commentary (σ-1).** Rebalancing Targets is **user-authored free-text only** — the system does NOT auto-generate or draft commentary from `$ ReAlloc` (decisional-authority posture; ADR-004 Decision A). No rebalance suggestions anywhere in the report.
- **Fixed composition; no report-config UI (2.6.1).** Six sections, fixed order, fixed four commentary sub-sections. **No reorder / hide / add-section / rename-sub-section UI** in V1 (all V2+).
- **Snapshot is frozen + rendered-value-level (2.6.4).** A generated report freezes the §2.1–§2.5 rendered values at generation time; later views show the values as-generated, NOT re-computed. **Exception:** staleness markers are read **live** (§1.3). Retention indefinite; **no user-delete, no PDF caching** (V2+/lock).
- **In-app web + PDF export only (2.6.3).** **No email / SMS / shared-link / Google Doc / other export formats** in V1 (all V2+). PDF is a transient download (not server-persisted).
- **Server-derived `data_as_of`; NEVER client-asserted for §2.6 (Lock 15).** The report's as-of is set by the trigger (cron = last day of prior month; on-demand = selected target month, or as-of-today for the in-progress month). The **§2.3.3 drill-down is the ONLY client-toggle as-of surface**; §2.6 reuses the as-of *mechanism* but not client control (§1.2).
- **Single full-household report; owner-id header is a label, not a filter (2.6.1/2.6.6/§7.3).** One aggregated household report; the trust-name header is administrative, **not** a tenant/scope boundary. No scope UI. Own-tenant reports only.
- **Density-first (§1.3); parity-exact.** The report reproduces the existing Finance_Report reading sequence the F/CTO has shipped for years.
- **Non-silent staleness — D1 (global, settled).** §2.6.5 IS the report-side manifestation; applied **without re-flagging** (per team-lead). Generate-with-markers (α′-1), never block, never silent.

### 0.3 Appendix B §2.6 — Architect/Sec Phase-3 dependencies (18 flags; NOT my surface)
Architect-only: (a) PDF gen mechanism, (b) cron mechanism, (c) snapshot storage shape, (d) snapshot-vs-live render composition, (e) owner-id settings-store dedup, (f) snapshot regeneration write path, (g) commentary persistence shape, (h) `$ ReAlloc` side-by-side rendering shape, (i) cross-section staleness signal threading (dedupes with §2.4.4), (j) section-rendering composition layer, (k) pending-queue affordance shape, (l) marker visual shape (Architect/**Design** Phase 2/3).
**Architect / Sec joint (security-load-bearing — already PRD-locked, landing at §4):** **(m)** snapshot-store tenant-scoping (RT-08), **(n)** owner-id write-path validation/input-sanitization (RT-12), **(p)** commentary write-path RLS + free-text sanitization (RT-11), **(q)** staleness-marker live-read tenant-scoping (RT-13), **(r)** cron-job tenant-scoping (RT-09). **(o)** RESOLVED — snapshot row as derivative surface of §2.5-grade sensitive classes (SD-12/SD-13).
→ These five Sec-joint flags are surfaced to team-lead in §9 (the convergence cluster has the highest Sec surface area; they're already-catalogued, not fresh product questions).

---

## 1. CONVERGENCE MAP + load-bearing pins

> §2.6 is where every §2.1–§2.5 surface and every cross-cluster commitment converges. This section is the heart of the cluster: which sections consume which clusters, and which commitments propagate into the report.

### 1.1 Section → upstream source → propagated commitments (normative)
| Report section | Upstream surface(s) | Commitments that propagate |
|---|---|---|
| **1. Account Holdings** | §2.1.5 composition buildup | Value-semantics pin (gross per-account, tax-adj only at aggregate); **incomplete-NAV-never-silently-dropped** (§1.4); D1 staleness. **§2.5.4 Realized/Unrealized rows appear HERE** (via §2.1.5), NOT in the Estimated Taxes section. |
| **2. NAV Performance** | §2.1.2 + §2.1.3 + §2.1.4 | Inflation overlay co-drawn (not toggle); fixed horizons/reference-dates; CPI-U basis; D1 staleness. NAV values are the **frozen snapshot** values (the §2.1 `nav-asof-timestamp` is captured into the snapshot's data-as-of — §1.3). |
| **3. Asset Allocation** | §2.2.2 + §2.2.3 | $ReAlloc sign convention; **visualization-only, no rebalance suggestions**; Total-US-Equity reconciliation; D1 staleness. |
| **4. Rebalancing Targets** | §2.6.2 (user-authored) | **σ-1 user-authored free-text only**; the ONE section §2.1–§2.5 don't author. **Excluded from staleness marking** (non-account-derived). |
| **5. Cash Flow** | §2.3.2 + §2.3.4 (inline) | **NON-GOAL fence — static targets, no variance/budget viz, no target line on the chart** (§2.3 §7A applies); Historical Expenditures inline (expenses-only, inflation-normalized); D1 staleness. |
| **6. Estimated Taxes** | §2.5.1 + §2.5.3 | **MONEY-MOVEMENT fence — obligations shown, no pay/transfer**; quarterly tables (no safe-harbor); applied-rate captions; bootstrap-incomplete state if brackets unset (§1.4); D1 staleness. §2.5.4 NOT here (it's on Account Holdings). |
| **Header** | §2.6.4 owner-id config | Administrative label, not a filter; snapshot-not-live (frozen per report); excluded from staleness marking. |

### 1.2 As-of: REUSE the §2.3 mechanism, do NOT diverge — but §2.6 is server-derived
- **Same Lock 15 mechanism as §2.3.3** (the dual-column `transaction_date ≤ data_as_of` AND `created_at ≤ data_as_of` historical read). §2.6 is the **2nd legitimate as-of surface** (with §2.3.3); it **reuses** §2.3 §1.1's pin — I do NOT define a divergent as-of here.
- **Critical distinction — control axis:** §2.6's `data_as_of` is **server-derived, NEVER client-asserted** (Lock 15): cron sets it to the **last day of the prior month**; on-demand sets it to the **selected target month** (or **as-of-today** for the in-progress month). **§2.3.3 is the ONLY surface where the user freely toggles as-of.** §2.6 has no free as-of toggle — only the server-set generation date. (Appendix B §2.3 flag (f): one system-wide as-of parameter threads both surfaces; §2.6's path never accepts a client-asserted date.)

### 1.3 Freshness-signal enumeration at the report (the multi-signal discipline — kept DISTINCT)
The report carries **two distinct freshness signals; do NOT conflate them** (this extends the §2.1 nav-asof-timestamp-≠-stale-marker discipline to its convergence point):
1. **Report snapshot recency — `report-generation-stamp` (NEW, §2.6-specific).** "Generated `<generation-timestamp>`, data as-of `<data_as_of>`." The report is a **frozen** artifact; this names *when it was frozen and to what as-of date*. This is its OWN dimension — **not** D1's `stale-data-marker`, **not** §2.1's `nav-asof-timestamp` (which is captured INTO the snapshot at generation and subsumed by `data_as_of` for the report).
2. **Live credential staleness — per-section `stale-data-marker` + report-level `report-staleness-banner` (§2.6.5; LIVE-read, the §2.6.4 carve-out).** Read live at view/export time from §2.4.4 credential state — NOT frozen into the snapshot. A historical report viewed today shows *today's* staleness state on its frozen data (the §2.6.5 historical-marker behavior).
- **Why distinct:** the snapshot-recency stamp tells the user *how old the frozen numbers are*; the live staleness markers tell the user *which accounts are currently broken*. A report can be freshly generated yet carry stale-account markers, or be months old with no current staleness. Both shown; neither masks the other.

### 1.4 Incomplete-NAV propagation (honors the §2.1 commitment + §2.5 bootstrap pin)
- The Account Holdings section is §2.1.5 composition. If a report is generated when **§2.5.2 brackets are unset** (or tax components otherwise uncomputable), the Realized/Unrealized Tax Liability rows render **"not yet computed" and NAV is marked incomplete** — **never silently dropped or shown as $0** (the §2.1 PM-3 + §2.5 §1.2 commitment). Because the snapshot is rendered-value-level, **an incomplete NAV freezes as incomplete** (honest) into that month's report. The report never fabricates a complete NAV.

### 1.5 Tenant-isolation read path (2.6.6 — Supporting)
- Only the user's own tenant's reports surface (snapshot store, commentary read, generation-state, owner-id config read-side all tenant-scoped). Write-path RLS for §2.6.2 commentary authoring + owner-id config is carried on the write surfaces (§2.6.2 / ADR-005 store). Scope is a data label, not isolation. (Sec routing flags m/p/q/r/n — §8A.)

---

## 2. Monthly Report surface — region/screen inventory

The cluster lives in a **Monthly Report** destination (top-level surface; nav model deferred to Step 3).

| Surface / region | Story | Role |
|---|---|---|
| `report-listing` | 2.6.3 | Lists prior generated reports + "Generate monthly report" trigger + target-month selection + the `pending-report-queue`. |
| `pending-report-queue` | 2.6.3 | In-app notification + queue for cron-fired (or user-triggered) reports awaiting commentary authoring (parallel to §2.4.1's notification-queue pattern). |
| `rebalancing-targets-editor` | 2.6.2 | The author-before-generate commentary editor (4 sub-sections + `$ ReAlloc` reference + copy-from-prior). |
| `report-view` | 2.6.1/2.6.4/2.6.5 | The in-app rendered report: 6 sections + owner-id header + commentary + live staleness markers + `report-generation-stamp` + PDF-export button. |
| `report-staleness-banner` | 2.6.5 | Report-level banner naming stale-contributing accounts (additive to per-section markers). |
| `owner-id-settings` | 2.6.4 | The trust-name header config (3rd additive ADR-005 settings field). |

**Info-hierarchy note:** §2.6 carries **no new 2–3-option information-hierarchy decision** — composition is PRD-fixed (six sections, fixed order). Design-shape items (marker visual, `$ ReAlloc` side-by-side layout, pending-queue shape) are **Architect/Design Phase 2/3** (resolved at wireframing/Visual), not UX 2–3-option flow decisions (§8).

---

## 3. FLOW F-2.6.A — Generate a monthly report
**Traces:** 2.6.3 (+ 2.6.2 authoring step, 2.6.4 snapshot). **Entry:** monthly cron (auto) OR `report-listing` → "Generate monthly report."

### Lifecycle (three states)
`not-yet-triggered` → (cron fire OR user trigger) → **`pending`** → (§2.6.2 commentary complete-or-skip) → **`generated`** → (user re-trigger) → `pending` (regeneration).

### Steps
1. **Trigger.**
   - **Cron:** fires **1st of each month, generating the prior month's report**, `data_as_of` = **last day of prior month** (server-derived). Lands a `pending` report in the `pending-report-queue` (in-app notification; **cron does NOT auto-finalize** — author-before-generate is honored on both paths).
   - **On-demand:** user picks a **target month** on `report-listing` — default = prior month (if cron hasn't fired); **current-month-in-progress** is valid (`data_as_of` = **as-of-today**). Always available; no rate-limit beyond idempotency.
2. **Author commentary (blocks finalization).** The generation flow **opens the §2.6.2 `rebalancing-targets-editor` first** (F-2.6.B); the report stays `pending` until the user **completes or explicitly skips** authoring (empty sub-sections render empty).
3. **Finalize → `generated`.** On complete-or-skip, the report transitions to `generated`: a **frozen rendered-value snapshot** (all six sections + commentary + owner-id header + `data_as_of` + generation timestamp + state) is written, single row per `(tenant, target-month)`. Now readable as `report-view` + exportable as PDF.
4. **Regeneration (overwrite).** Re-triggering a month that already has a report → editor opens **pre-populated with the existing commentary** → re-finalize **overwrites** the prior snapshot (no revision history V1). §2.6.2 survivability holds **between** regenerations.

### Decision points
- Cron vs on-demand trigger · target-month selection (prior vs in-progress) · complete vs skip authoring · first-generation vs regeneration (overwrite).

### Error / edge states
- **Cron failure** (didn't fire / partial / interrupted) → **system-level log for the F/CTO** (operational, not user-facing V1); the **on-demand trigger is the manual fallback** (always available). No auto-retry / partial-recovery / in-app cron-failure notification in V1.
- **Authoring abandoned** → report stays `pending`; reachable again via the queue; not finalized.
- **Generate when brackets unset / tax incomplete** → report still generates; Account Holdings NAV freezes **incomplete-but-honest** (§1.4).
- **Generate with stale accounts** → report still generates (α′-1); staleness markers render live (F-2.6.C).

### Out of scope — V1/V2 per 2.6.3
User-configurable cron schedule (V2+); email/SMS/shared-link delivery (V2+); revision history for regenerated months (V2+); automated cron-retry / in-app cron-failure notification (V2+); drill-down from a report section to its source surface (V2+ forward-compat).

---

## 4. FLOW F-2.6.B — Author Rebalancing Targets commentary
**Traces:** 2.6.2. **Entry:** the author-before-generate step within F-2.6.A (the `rebalancing-targets-editor`).

### Steps
1. **Editor opens** under **four fixed sub-sections — Cash / Bonds / Equity / Alternatives** (parity; not user-configurable). Each is a labeled **plain-text** region (line breaks preserved; **no markdown / rich-text / link insertion**).
2. **`$ ReAlloc` reference alongside.** The editor surfaces the relevant §2.2.2 `$ ReAlloc` deltas as **read-only reference** while writing (reuses §2.2.2 content authority by reference; **does not write back** to §2.2.2). The side-by-side *layout* (modal / inline panel / linked / dual-pane) is Architect Phase 3 (flag (h)).
3. **Blank by default + copy-from-prior.** A new month opens **blank**; an explicit **"copy from prior month"** affordance (per-sub-section or global) pulls prior commentary as a starting point, which the user then edits. **No auto-pre-population default** (avoids stale-commentary leak-forward).
4. **Complete or skip** → returns to F-2.6.A finalization. Commentary is **persisted per-report** (survives unchanged on the historical report, between regenerations).

### Decision points
- Author vs skip (per sub-section) · copy-from-prior (per-sub-section or global) vs write-fresh.

### Error / edge states
- **Empty sub-sections** → render with label + empty body on the report (not an error; authoring isn't required under every sub-section).
- **Write-path tenant-scoping** → commentary is tenant-scoped on write (ARCH/Sec flag (p), RT-11; input sanitization on free-text). This surface is **excluded from staleness marking** (non-account-derived).

### Out of scope — V1/V2 per 2.6.2
Auto-generated / hybrid-with-edit commentary (σ-2/σ-3, V2+ — needs ADR-004 Decision A amendment); **markdown / rich-text (V2+ — SECURITY-surface expansion, requires a Sec re-touch per INV-1, §8A; NOT a harmless UX refinement)**; user-configurable sub-sections (V2+); auto-pre-population default + settings toggle (V2+); late-edit/amend-after-generation with revision tracking (V2+); per-sub-section template prompts (V2+).

---

## 5. FLOW F-2.6.C — View / retrieve / export a report
**Traces:** 2.6.1 (composition render) + 2.6.4 (snapshot/retention) + 2.6.5 (staleness markers). **Entry:** `report-listing` → select a report → `report-view`.

### Steps
1. **Render the report.** `report-view` renders the **six sections in fixed order** (§1.1 map) + the owner-id header + inline §2.6.2 commentary, reading the **frozen snapshot** for that target-month. The `report-generation-stamp` ("Generated …, data as-of …") shows the snapshot recency (§1.3 signal 1).
2. **Live staleness layer (§1.3 signal 2).** Per-section `stale-data-marker`s + the `report-staleness-banner` (naming stale accounts) render **LIVE** from current §2.4.4 credential state — NOT from the snapshot (the §2.6.4 carve-out). **All four credential states trigger markers uniformly**; the actionable-language under a marker inherits §2.4.4's per-class framing. §2.6.2 commentary + §2.6.4 header are **excluded** from marking.
3. **Retrieve a historical report.** Select any prior month → renders that month's frozen snapshot + **today's** live staleness markers (an account healthy in Jan but stale in May shows markers on Jan's data when viewed in May; and vice versa).
4. **Export PDF.** A button on `report-view` (only for `generated`-state reports) downloads a PDF carrying the same six-section composition + header + commentary + **live staleness markers at the click moment** (§2.6.4 carve-out — PDF is a frozen capture of the live-rendered view at export time). PDF is a **transient download, not server-persisted**; re-generated from the snapshot each export (no caching).

### Decision points
- Current vs historical month · in-app view vs PDF export · (markers are not interactive in V1 — no dismiss/acknowledge, that's V2+).

### Error / edge states
- **Incomplete NAV in the snapshot** (§1.4) → Account Holdings renders the frozen incomplete state ("not yet computed" tax components; NAV incomplete) — honest, not fabricated.
- **All four credential states** → uniform "stale" marker (no per-class marker visual in V1; per-class differentiation is V2+).
- **Snapshot derivative of sensitive data** → read path tenant-scoped (ARCH/Sec flag (m)/(q), RT-08/RT-13).
- **PDF of a `pending`/`not-yet-triggered` report** → not available (export only from `generated` state).

### Out of scope — V1/V2 per 2.6.4 / 2.6.5
Live-rendered date-filtered historical views (V2+); user-initiated report deletion (V2+); retention-window cleanup / archival tiers (V2+); PDF caching (lock: none); per-credential-class marker visuals (V2+); user dismiss/acknowledge of markers (V2+); marker-state snapshotting / staleness-history (V2+).

---

## 6. FLOW F-2.6.D — Set the owner-identification header
**Traces:** 2.6.4 (ψ-1). **Entry:** `owner-id-settings` (a V1 settings UI field).

### Steps
1. User edits a **single per-tenant owner-identification string** (the trust-name header; plain text, parity example "THE RICHARD MELVIN MOSKO, JR. 2023 TRUST"). It is the **3rd additive field** to the ADR-005 settings store (after §2.3.2 planning targets + §2.5.2 brackets).
2. *System:* persists; **applies forward, not retroactively** — every report carries the header **in effect at its generation time** (snapshot-not-live, §2.6.4). Renaming the trust mid-year leaves prior reports showing the prior name.

### Error / edge states
- **Write-path validation** (ARCH/Sec flag (n), RT-12): input sanitization, length bounds, **no executable content in the rendered header** (the header is rendered into the report + PDF, so injection-safety matters).

### Out of scope — V1/V2 per 2.6.4
Multi-line / **rich-text headers (V2+ — SECURITY-surface expansion, requires a Sec re-touch per INV-1, §8A)**; multi-named-owner config (V2+, anticipates multi-scope reports); per-report header override at generation (V2+).

---

## 7. Cross-cutting error / edge state matrix (V1 failure surfaces for §2.6)
| Edge / error | Where | Behavior |
|---|---|---|
| **Cron failure** | generation | System-level log (F/CTO ops, not user-facing V1); on-demand trigger is the manual fallback. No auto-retry V1. |
| **Stale / pending-re-auth account** (D1, α′-1) | `report-view`, PDF, historical | Generate-with-markers: per-section `stale-data-marker` + `report-staleness-banner` (names accounts); **live-read** (not frozen); never blocks, never silent. |
| **Incomplete NAV** (brackets unset, §1.4) | Account Holdings section | Tax components "not yet computed"; NAV incomplete; frozen honest in the snapshot; never fabricated. |
| **Authoring abandoned** | generation | Report stays `pending`; reachable via queue; not finalized. |
| **Regeneration** | generation | Overwrite (no revision history V1); commentary pre-populated from prior snapshot; survivability holds between regenerations. |
| **Money-movement "missing"** (Estimated Taxes section) | — | **Not an error — permanent non-goal.** Obligations shown; no pay/transfer affordance (ADR-002 §3.0). |
| **Budget/variance "missing"** (Cash Flow section) | — | **Not an error — permanent non-goal.** Static targets; no variance/progress/target-line (ADR-002 §1.2; §2.3 §7A). |
| **PDF of non-generated report** | export | Not available (export only from `generated`). |

---

## 8. Open decisions / Phase-2-3 design-shape items (NOT 2–3-option UX flow decisions)
- **No new information-hierarchy 2–3-option decision** — §2.6 composition is PRD-fixed.
- **Design-shape items routed to Architect/Design Phase 2/3 (resolve at wireframing/Visual, not now):** marker visual shape (flag (l)); `$ ReAlloc` side-by-side layout (flag (h)); pending-report-queue affordance shape (flag (k)); section-rendering composition (flag (j)). I'll carry these into the wireframe pass; none forces a flow decision now.
- **P5-adjacent note:** the owner-id header (F-2.6.D) is the **3rd additive ADR-005 settings field** (after planning targets + brackets). It is **identity config, not a planning value** — but it lives in the same settings-UI surface family, so it rides whatever the **P5 settings-UI resolution** lands at Step 3 (settings-UI is the strong P5 default per §2.3/§2.5). Recorded, not a new decision.

---

## 8A. Phase 3 ARCH + Sec handoffs (from §2.6 — the convergence cluster)
Captured for cross-team routing when Phase 3 spins up (per ADR-012). NOT UX surfaces.
**Architect-only:** (a) PDF gen mechanism, (b) cron mechanism, (c) snapshot storage shape `(tenant_id, target_month)`, (d) snapshot-vs-live render composition (fuse frozen rows + live staleness), (f) single-row-per-month overwrite write path, (g) commentary persistence, (h) `$ReAlloc` side-by-side layout, (i) cross-section staleness signal threading (dedupes with §2.4.4 flag (i) — shared infra), (j) section composition layer, (k) pending-queue affordance, (l) marker visual.
**Architect / Sec joint (security-load-bearing; already PRD-locked, land at §4):**
- **(m) Snapshot-store tenant-scoping** — read-path RLS; snapshot persists §2.5-grade sensitive derivatives → RT-08.
- **(n) Owner-id write-path validation** — input sanitization, length bounds, **no executable content in the rendered header** → RT-12.
- **(p) Commentary write-path RLS** — tenant-scoped per §2.4.5; free-text input sanitization → RT-11.
- **(q) Staleness-marker live-read tenant-scoping** — live read of §2.4.4 state at render; cross-tenant signal-leak surface to verify → RT-13.
- **(r) Cron-job tenant-scoping** — per-tenant cron; no cross-tenant data path in the generation worker → RT-09.
- **(o) RESOLVED** — snapshot row = derivative surface of §2.5-grade classes (SD-12/SD-13; not a new class).

**Injection invariants (PM-flagged at §2.6 lock — explicit Phase-3 / §4-Sec-authoring inputs so they survive):**
- **INV-1 — plain-text-only is SECURITY-LOAD-BEARING, not just UX-simplicity.** The §2.6.2 commentary's plain-text/no-markdown/no-rich-text constraint (and the §2.6.4 owner-id header's plain-text constraint) is a **security boundary**, not merely a parity/simplicity choice. The V2+ "add markdown / rich-text" path is therefore a **security-surface expansion that REQUIRES a Sec re-touch** — it must NOT be treated as a harmless UX-affordance refinement. Flag carried on the V2+ markdown item in both F-2.6.B and F-2.6.D out-of-scope lists.
- **INV-2 — output-encoding must span BOTH render contexts AND couples to flag (a).** RT-11 (commentary) + RT-12 (owner-id header) output-encoding must hold across **both** the HTML in-app view **and** the PDF export. The mitigation **differs by PDF render path** (server-side templated render vs. client-side DOM-to-PDF — flag (a) is open), so **RT-11/RT-12 must be addressed JOINTLY with flag (a)** at Phase 3, not independently. Both render contexts (HTML + PDF), one encoding contract.

### Note to team-lead — §2.6 has the highest Sec surface area; is a Sec consult wanted? *(surfaced per your "flag if security-load-bearing" steer)*
§2.6 carries **five Architect/Sec-joint routing flags** (m/n/p/q/r → RT-08/09/11/12/13): snapshot tenant-scoping, owner-id input-sanitization (header is rendered → injection surface), commentary write-path RLS + free-text sanitization, staleness-marker live-read tenant-scoping, cron-job tenant-scoping. **All five are already PRD-locked routing flags** catalogued at §2.6 lock and landing at §4 (Sec primary author) — they are **Phase-3/§4 implementation obligations, not open product questions.** My read: **no fresh Sec spawn strictly required** (this mirrors §2.3/§2.5 — Sec already engaged at PRD lock). **But** §2.6 is the convergence cluster with the densest Sec surface (free-text authoring + rendered header injection surface + cron worker + cross-tenant live-read), so flagging explicitly for your call on whether a Sec cross-cluster-consistency touch is warranted before §2.6 locks.

### Flag PM-1 — Regeneration vs. §2.6.2 persistence tension. *(PRD-acknowledged; confirm no UX surprise)*
The PRD already resolves this (overwrite, no revision history V1; survivability holds *between* regenerations). My flows reflect overwrite-with-commentary-pre-populated. Confirm no expectation of a "you're about to overwrite the prior snapshot" warning beyond the implicit pre-populated-editor behavior. *(Lean: the pre-populated editor IS the safeguard; no separate destructive-action warning needed since prior commentary is preserved into the editor.)*

### Flag PM-2 — Cron-failure visibility. *(confirmation)*
V1 logs cron failures at system level (not user-facing); on-demand is the fallback. Confirm the F/CTO is comfortable with **no in-app cron-failure notification** in V1 (a month could silently fail to auto-generate; the user notices when they go to view it and find it `not-yet-triggered`). *(Lean: acceptable per PRD τ-1 rationale; the on-demand trigger + the report-listing showing a missing month is the V1 recovery path.)*

*(No info-hierarchy flag; composition is PRD-fixed. Design-shape items are Phase-2/3 Architect/Design, §8.)*

---

## 10. Provisional screen / surface inventory (for the eventual Visual handoff — NOT final until Step 3 lock)
| # | Surface / region | Type | Flow | Traces |
|---|---|---|---|---|
| 1 | `Monthly Report` | full screen (destination) | container | 2.6.* |
| 2 | `report-listing` | full screen (list + trigger) | F-2.6.A | 2.6.3 |
| 3 | `pending-report-queue` | notification + queue | F-2.6.A | 2.6.3 |
| 4 | `rebalancing-targets-editor` | editor (4 sub-sections + reference) | F-2.6.B | 2.6.2 |
| 5 | `report-view` | full screen (6-section render) | F-2.6.C | 2.6.1/2.6.4/2.6.5 |
| 6 | `report-staleness-banner` | report-level banner | F-2.6.C | 2.6.5 |
| 7 | `report-generation-stamp` | recency stamp (generated / data-as-of) | F-2.6.C | 2.6.3/2.6.4 |
| 8 | PDF export | download affordance (on `report-view`) | F-2.6.C | 2.6.3 |
| 9 | `owner-id-settings` | settings field (3rd ADR-005) | F-2.6.D | 2.6.4 |

Cross-cutting components: `stale-data-marker` (consumed live, D1/§2.6.5), `report-staleness-banner`, `report-generation-stamp` (NEW snapshot-recency signal), report-section-block (×6), commentary-sub-section-editor, `$ReAlloc`-reference (read-only, reused from §2.2.2), copy-from-prior affordance, owner-id-header (snapshot-not-live), pending-report-queue-item (parallels §2.4.1 notification queue), PDF-export button. Cross-links: every report section → its §2.1–§2.5 source surface (drill-down forward-compat V2+); editor → §2.2.2 `$ReAlloc`; markers → §2.4.4 credential state (live); `owner-id-settings` → ADR-005 store (with §2.3.2 + §2.5.2).

---

## 11. PRD §2.6 story → flow traceability (for the PM consult)
| PRD story | Covered by | Notes |
|---|---|---|
| 2.6.1 Composition contract | F-2.6.C (`report-view` 6-section render) + §1.1 map | Fixed six-section order; owner-id header; HistExp inline in Cash Flow; §2.5.4 on Account Holdings not Estimated Taxes. |
| 2.6.2 Rebalancing Targets commentary | F-2.6.B (`rebalancing-targets-editor`) | σ-1 user-authored; 4 fixed sub-sections; `$ReAlloc` reference; plain text; blank+copy-from-prior; author-before-generate; per-report persistence. |
| 2.6.3 Generation cadence/trigger/format | F-2.6.A | Dual-trigger (cron 1st-of-month + on-demand); 3-state lifecycle; in-app + PDF; overwrite regeneration; pending queue; cron-fail→log+fallback. |
| 2.6.4 Snapshot/retention/identity | F-2.6.C + F-2.6.D | Frozen rendered-value snapshot; indefinite retention; owner-id snapshot-not-live; staleness live-read carve-out; tenant-scoped read. |
| 2.6.5 Staleness markers | F-2.6.C (`stale-data-marker` + `report-staleness-banner`) | α′-1 generate-with-markers; per-section + banner; all 4 states uniform; §2.6.2/§2.6.4 excluded; live incl. historical + PDF. |
| 2.6.6 Report is the user's | §1.5 + §0.2 (constraint, all flows) | Tenant-isolation read path; owner-id = label not filter; no scope UI. Not a screen. |

**No flow exceeds its PRD story.** All fences converge + hold: money-movement (permanent), variance/budget (permanent), σ-1 no-auto-commentary, fixed composition, frozen snapshot, in-app+PDF only, server-derived as-of, single-household. D1 applied (α′-1) without re-litigation. PM items isolated as Flags PM-1/PM-2 + the Sec-spawn surfacing.

---

## 12. Status / next
- **This draft (the CONVERGENCE cluster):** §2.6 flow structure complete. **§1 convergence map** ties each of the six sections to its §2.1–§2.5 source + the commitments that propagate. Load-bearing pins: **as-of reuse-not-diverge** (§1.2 — same Lock 15 mechanism as §2.3.3, but §2.6 `data_as_of` is SERVER-derived, never client-asserted); **freshness-signal enumeration** (§1.3 — `report-generation-stamp` snapshot-recency kept DISTINCT from the live `stale-data-marker`, per the multi-signal discipline); **incomplete-NAV propagation** (§1.4 — Account Holdings freezes incomplete-but-honest); **non-goal fences converge** (money-movement + variance/budget both apply to report content).
- **D1 applied** as α′-1 generate-with-markers (live-read) without re-litigation.
- **Flags for PM:** PM-1 (regeneration/persistence — PRD-resolved, confirm no extra warning), PM-2 (cron-failure visibility — confirm no in-app notification V1).
- **SEC-SPAWN SURFACING (§9):** §2.6 has the highest Sec surface area — 5 Architect/Sec-joint flags (RT-08/09/11/12/13), all already PRD-locked. My read: no fresh spawn strictly required, but flagged for your call given the convergence density (free-text authoring + rendered-header injection + cron worker + cross-tenant live-read).
- **ARCH/Sec handoffs (§8A):** 12 Architect-only + 5 Architect/Sec-joint + 1 resolved.
- **ALL SIX CLUSTERS DRAFTED.** §2.4 / §2.1 / §2.2 / §2.3 / §2.5 LOCKED; §2.6 ready for the PM traceability consult (with extra cross-cluster scrutiny as the convergence cluster).
- **Next:** §2.6 PM consult → then the **Step 3 F/CTO flow walk-through gate** (all six clusters end-to-end; the parked decisions — nav model, §2.1 info-hierarchy, §2.3 info-hierarchy, P3 classification surfacing, P5 planning-value affordance — all land there) → then wireframing (Step 4).
- **No wireframing** until the Step 3 gate confirms the flow set.
