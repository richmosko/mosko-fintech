# Phase 2 — Wireframes: Shared App SHELL

**Scope:** the layout chrome common to every surface — sidebar nav (P1), conditional re-auth/staleness banner (P4), top-bar notifications, and the Settings area that houses all planning-value editors (P5).
**Author:** UX Designer. **Step:** Phase 2 Step 4 (wireframes — layout realization; flows are LOCKED). **Date:** 2026-05-28.
**Decisions applied:** D1 + P1–P6 per ADR-013 (`DECISIONS.md`) / `temp/phase-2-decisions-log.md` RESOLVED section.
**Format:** structured-text wireframes — layout **regions**, named **component** placement, per-component **states**. ASCII sketches for key screens. Solo (Visual joins at Step 5).

---

## 0. Terminology (defined precisely to avoid loose shorthand)
- **Region** — a named layout zone within a screen (e.g., sidebar, top-bar, content). Not a component; a container for components.
- **Component** — a named, reusable UI element placed in a region. Names reuse the locked flow-doc vocabulary (e.g., `account-row`, `stale-data-marker`).
- **Persistent** — rendered on **every** surface and **not** removed on navigation. Specifically NOT "stays after the user dismisses it" — persistent chrome here is **non-dismissible** by definition.
- **Conditional** — rendered **only when a named condition holds**; when the condition is false it has **zero layout footprint** (not hidden-but-occupying-space; absent). Used for the P4 banner.
- **Modal** — a blocking overlay; the user must complete or dismiss it before interacting with the surface beneath. **Panel** — a non-blocking region (inline or side-docked) the user can ignore. **Drawer** — an edge-anchored panel that slides in. These three are distinguished deliberately; a screen labeled "modal" blocks, one labeled "panel" does not.
- **State vocabulary** (applied per component where the state is meaningful): `default` / `hover` / `pressed` (incl. active/selected) / `loading` / `disabled` / `empty` / **`stale`** / `error`.
  - **`stale`** is defined here once (D1): a component is in the `stale` state when the value(s) it renders are derived — wholly or partly — from an account currently in a §2.4.4 credential-error / re-auth state (or stale beyond the freshness threshold). The `stale` state is **visual-marker-only; it never blocks or hides the value** (non-silent-staleness contract).

---

## 1. App shell — overall frame

Two persistent regions (sidebar + top-bar) frame one conditional region (P4 banner) above the content region.

**Healthy state (no re-auth/staleness condition — P4 banner ABSENT, clean chrome):**
```
┌──────────────┬──────────────────────────────────────────────────────┐
│ app-sidebar  │ app-topbar (persistent, thin)         [ ⌕ ] [ inbox ] │
│ (persistent) ├──────────────────────────────────────────────────────┤
│              │                                                        │
│  ◰ Accounts  │  CONTENT REGION                                        │
│  ⌂ Net Worth │  (the active surface renders here)                     │
│  ◑ Allocation│                                                        │
│  ⇅ Cash Flow │                                                        │
│  ⅀ Est. Taxes│                                                        │
│  ▤ Report    │                                                        │
│  ──────────  │                                                        │
│  ⚙ Settings  │                                                        │
│              │                                                        │
│  ‹ collapse  │                                                        │
└──────────────┴──────────────────────────────────────────────────────┘
   ↑ P4 banner region is ABSENT here (zero height) — clean chrome when all connections healthy.
```

**Attention state (≥1 account in re-auth/credential-error — P4 banner PRESENT):**
```
┌──────────────┬──────────────────────────────────────────────────────┐
│ app-sidebar  │ app-topbar (persistent, thin)         [ ⌕ ] [ inbox•2]│
│              ├──────────────────────────────────────────────────────┤
│  ◰ Accounts •│ ⚠  2 accounts need re-authentication                  │ ← reauth-staleness-banner
│  ⌂ Net Worth │    [Fidelity ⟳] [Chase ⟳]                 [ Review → ]│   (P4; CONDITIONAL; persistent
│  ◑ Allocation├──────────────────────────────────────────────────────┤    across surfaces until resolved)
│  ⇅ Cash Flow │  CONTENT REGION                                        │
│  ⅀ Est. Taxes│   (aggregations sourced from Fidelity/Chase render     │
│  ▤ Report    │    with inline stale-data-markers — D1)                │
│  ⚙ Settings  │                                                        │
└──────────────┴──────────────────────────────────────────────────────┘
   ↑ Banner sits ABOVE content, BELOW top-bar; survives navigation between surfaces until every re-auth resolves.
```

---

## 2. `app-sidebar` (P1 — persistent left sidebar)

**Region:** full-height left rail, persistent. Houses the six destination surfaces + Settings. **NOT a drawer** (always present on wide viewports); collapses to an icon rail on narrow viewports.

**Components & placement (top → bottom):**
- `nav-item` × 6 (the destinations, in dependency/reading order):
  1. **Accounts** (→ Accounts Hub, §2.4)
  2. **Net Worth** (§2.1)
  3. **Asset Allocation** (§2.2)
  4. **Cash Flow** (§2.3)
  5. **Estimated Taxes** (§2.5)
  6. **Monthly Report** (§2.6)
- `nav-divider`
- `nav-item` **Settings** (⚙ — the P5 planning-value home + owner-id)
- `sidebar-collapse-toggle` (‹ / ›) at the bottom.

**`nav-item` states:**
- `default` — icon + label.
- `hover` — affordance highlight.
- `pressed`/active — the current surface; persistent highlight so location is always legible.
- `attention-dot` (modifier, not a base state) — a small `•` on a nav-item whose surface has an unresolved condition: **Accounts •** when an account needs re-auth (mirrors P4); **Monthly Report •** when a report is `pending`. Subtle; secondary to the P4 banner and the inbox.
- `collapsed` — icon-only (label hidden; label shows on hover as a tooltip).
- `disabled` — not used in V1 (all six destinations always available single-user).

**`sidebar-collapse-toggle` states:** `default` (expanded) / `pressed` (collapsed → icon rail) / `hover`. Collapse is a viewport-width affordance, NOT a per-session preference surface in V1 (no settings toggle for it).

---

## 3. `app-topbar` (persistent, thin) + `notifications-inbox`

**Region:** thin persistent bar across the top of the content column (right of the sidebar). Deliberately minimal.

**Components (right-aligned):**
- `global-search` (⌕) — **RESOLVED (F/CTO): keep as a labeled V1 placeholder slot.** Reserve the chrome space in the top-bar, marked clearly as a placeholder (behavior/scope TBD — no §2.x flow defines its search semantics yet). **Not a built feature; do not invent its behavior.** The slot exists so the chrome layout accounts for it.
- `notifications-inbox` — a badge affordance opening a `notifications-panel` (a **panel**, non-blocking). It aggregates the two task queues from the flows:
  - **Pending symbol classifications** (`New-Symbol-Classification-Queue` count — §2.4.1 / P3).
  - **Pending monthly reports** (`pending-report-queue` — §2.6.3).

**Distinction (defined to avoid conflation):** the `notifications-inbox` is for **at-leisure task queues** (classify symbols, finish a report) — dismissible, user resolves on their cadence. The **P4 `reauth-staleness-banner`** (§4) is for an **integrity condition** (data is stale until a connection is fixed) — non-dismissible, persists until resolved. They are different surfaces with different urgency semantics; do not merge.

**`notifications-inbox` states:** `default`/`empty` (no badge) · `has-items` (badge count) · `hover` · `pressed`/open (panel shown) · `loading` (fetching).
**`notifications-panel` states:** `empty` ("No pending tasks") · populated (grouped: Classifications / Reports) · item `hover`/`pressed` (→ navigates to the queue/editor).

---

## 4. `reauth-staleness-banner` (P4 — conditional top-chrome banner)

**Region:** a conditional strip **between** `app-topbar` and the content region. **Absent (zero height) when healthy; present when ≥1 account is in a credential-error/re-auth state or stale beyond threshold.** Persistent across surface navigation **until the condition resolves** (non-dismissible — closing it is not offered; only fixing the connection clears it).

**Wireframe — present (N accounts):**
```
┌────────────────────────────────────────────────────────────────────┐
│ ⚠  {N} accounts need re-authentication                              │
│    [Fidelity ⟳]  [Chase ⟳]  … (account chips, one per affected)     │
│                                                  [ Review accounts → ]│
└────────────────────────────────────────────────────────────────────┘
```
**Components:**
- `banner-icon` (⚠) + `banner-summary` text (count).
- `account-chip` × N — each names a stale/affected account; `hover` → which credential state (the four §2.4.4 classes); `pressed` → deep-links to that account's `connection-status-panel` (Account Detail, §2.4).
- `banner-review-action` ([Review accounts →]) → Accounts Hub filtered/scrolled to attention accounts.

**States:**
- `absent` — healthy; zero footprint (clean chrome). **This is the default and the most common state.**
- `present-single` — "1 account needs re-authentication: [X ⟳]".
- `present-multiple` — count + chip list (chips may wrap/truncate with "+k more").
- `INSTITUTION_DOWN-only nuance` — if the only affected accounts are `INSTITUTION_DOWN` (institution offline, no user action), the banner copy shifts to **informational** ("1 institution temporarily unavailable — no action needed") with **no [Review] call-to-action** (per the §2.4.4 four-state presentation; avoid teaching credential-entry when nothing is wrong).
- `hover`/`pressed` on chips/action as above.

**Relationship to content `stale-data-marker` (D1):** the banner is the **global** signal (which accounts); the per-aggregation `stale-data-marker` is the **local** signal (which numbers). Both render simultaneously when stale; neither replaces the other.

---

## 5. `settings-surface` (P5 — the planning-value home; all four editors live here)

**Region:** the Settings destination. A secondary sub-nav (left, within the content region) lists the setting groups; the selected group's editor renders to its right. **All planning-value editing happens here — there is NO inline target/bracket editing on any data surface (P5).**

**Wireframe:**
```
┌──────────────┬───────────────────────────────────────────────────────┐
│ settings-    │  {selected editor renders here}                        │
│  subnav      │                                                        │
│              │                                                        │
│ ▸ Allocation │   e.g. Allocation Targets editor:                      │
│    Targets   │   ┌─────────────────────────────────────────────┐     │
│ ▸ Cash-Flow  │   │ Sub-Cat            % Target                  │     │
│    Targets   │   │ US-Index_Non_Sector [ 22.0 ] %               │     │
│ ▸ Tax        │   │ T-bill              [  8.0 ] %               │     │
│    Brackets  │   │ …                                            │     │
│ ▸ Report     │   │ ───────────────────────────                 │     │
│    Identity  │   │ Sum of targets: 97.0%  (informational)       │     │
│              │   │                          [ Save ] [ Cancel ] │     │
│              │   └─────────────────────────────────────────────┘     │
└──────────────┴───────────────────────────────────────────────────────┘
```

**`settings-subnav` items (V1 — the four planning-value editors):**
1. `settings-allocation-targets` — §2.2 `% Target` per Sub-Cat (a keyed list of rate inputs).
2. `settings-cashflow-targets` — §2.3.2 income target (annual scalar) + expense target (monthly scalar).
3. `settings-tax-brackets` — §2.5.2: Federal ordinary schedule (rate/threshold rows) + Federal LT CG schedule (rows) + CA ordinary schedule (rows) + per-jurisdiction standard-deduction scalars.
4. `settings-report-identity` — §2.6 owner-identification header (single plain-text string).

**`settings-subnav` states:** `default`/`hover`/`active` (selected group).

**Shared editor component states** (apply to each editor's inputs + save):
- `default` (showing current persisted values) · `editing` (dirty, unsaved) · `hover`/`pressed` on inputs · `loading` (saving) · `disabled` (save disabled until a valid change) · `empty` (e.g., targets/brackets not yet set — bootstrap; see below) · `error` (validation failure — inline per field) · `saved` (confirmation).

**Per-editor specifics + states:**
- **Allocation Targets:** keyed `% Target` rows. `error` per row (negative %, >100%, non-numeric). A **`target-sum-readout`** ("Sum of targets: 97.0%") is **informational only** — per the §2.2 PM-3 / non-goal discipline it must **NOT** be styled as a warning/alert/blocker and must NOT block save (it reports the sum; it never enforces 100%).
- **Cash-Flow Targets:** two labeled scalars (income = annual; expense = monthly). **NON-GOAL fence (carried from §2.3 §7A):** these are reference values; the editor must NOT preview variance, progress, or over/under against actuals.
- **Tax Brackets:** three schedules (per-jurisdiction ordered rows of rate + lower-bound threshold) + two standard-deduction scalars. `error` states: non-monotonic thresholds, negative/>100% rates, NaN. Manual-update-at-rollover (no API-fetch affordance — V1).
- **Report Identity:** single plain-text field. **INV-1 (security-load-bearing):** plain-text only — **no markdown/rich-text affordance** (the V2+ formatting path is a security-surface expansion, not a styling nicety). `error`: length-bound / disallowed-content validation.

**Bootstrap `empty` state (cross-cluster consequence):** when Tax Brackets are unset, this editor shows an `empty`/setup state ("Enter your current-year Federal + California schedules to enable estimated-tax computation"). Until set, §2.5 computes nothing and §2.1 NAV renders incomplete-but-honest (the §2.5↔§2.1 bridge). The Settings Tax-Brackets editor is the **remedy surface** for that incomplete-NAV state.

---

## 6. Shell-level cross-cutting components (vocabulary used by all clusters)
- `stale-data-marker` (D1) — inline indicator on any derived value/row in the `stale` state. `present`/`absent`; `hover` → tooltip naming the stale source account + "needs re-authentication" + (if actionable) a re-auth deep-link. **Per-aggregation** (every aggregation that consumed stale data carries its own marker — not one global flag).
- `connection-status-chip` — compact status indicator for an account (Fresh / Re-auth required / Institution down / Grant revoked / Manual / Inactive-sync-paused). Used on `account-row`, in the P4 banner, and on Account Detail.
- `account-row` — the shared account list-row (name, type, scope, tax-treatment, current **gross** value, `connection-status-chip`). Used on Accounts Hub + composition.
- freshness stamps (surface-specific, defined where they live): `nav-asof-timestamp` (§2.1), `report-generation-stamp` (§2.6). Kept distinct from `stale-data-marker` per the multi-signal discipline.

---

## 7. Responsive / viewport note (density-first archetype)
- **Wide (primary target):** sidebar expanded; dense tables render full-width; this is the design center (the owner works at a desktop on monthly reviews).
- **Narrow:** `app-sidebar` collapses to the icon rail (`sidebar-collapse-toggle`); the P4 banner wraps its chip list; dense tables gain horizontal scroll rather than reflowing into cards (preserve column structure — density is a feature; do NOT collapse the financial tables into mobile "stacked card" patterns that lose the grid).
- V1 is a desktop-first single-user tool; a full mobile redesign is out of V1 scope (graceful narrow-viewport degradation only).

---

## 8. Status / next
- **Shell wireframe complete:** sidebar (P1) + conditional banner (P4) + top-bar/notifications + Settings area (P5, all four editors) + cross-cutting components + the bootstrap-empty Tax-Brackets remedy surface.
- **`global-search` RESOLVED (F/CTO):** keep as a labeled V1 placeholder slot in the top-bar (reserved chrome space; behavior TBD; not built). Reflected in the HTML render.
- **Next:** §2.4 cluster wireframes (the checkpoint deliverable, this pass), then §2.1 → §2.2 → §2.3 → §2.5 → §2.6 after shell + §2.4 are confirmed.
- **No Visual styling** — placement + states only; Visual joins at Step 5.
