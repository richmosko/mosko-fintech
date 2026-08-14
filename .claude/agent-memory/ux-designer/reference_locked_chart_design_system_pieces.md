---
name: reference-locked-chart-design-system-pieces
description: Locked chart/dashboard design-system components (chart-placeholder states, chart-granularity chip-group, viz tokens) — check these before proposing new chart components
metadata:
  type: reference
---

The design system already carries locked components for financial time-series charts on the dashboard,
confirmed by team-lead 2026-08-12 during SELF-220 (see [[project_self220_nav_chart_status]]):

- **`chart-granularity chip-group`** — the monthly/weekly/daily-style granularity toggle.
- **`chart-placeholder`** — five states: `default`, `loading`, `empty-insufficient-history`,
  `cpi-unavailable(nominal-only)`, `stale-segment`. `empty-insufficient-history` covers both a fully-empty
  chart and a sparse/partial-data chart at its two extremes. `cpi-unavailable(nominal-only)` is for
  whole-series unavailability (not isolated per-point gaps — those are a rendering rule inside `default`).
  `stale-segment` is a shared visual primitive that can carry more than one underlying cause (differentiated
  by copy, not shape) — confirmed acceptable for account-pending-reauth AND NAV-checkpoint-carry-forward
  together, since both mean "this segment isn't as fresh as it looks."
- **Tokens:** `--c-viz-nominal`, `--c-viz-infl`, `--c-viz-fill`.

**Gaps confirmed NOT covered by the above** (as of SELF-220): a density indicator for the sparse/partial
region of `empty-insufficient-history`, and any treatment for the §2.4.4 **informational tier** (non-actionable,
self-heals) — none of the five `chart-placeholder` states is that tier, and reusing `stale-segment` for it
would collapse the actionable/informational distinction §2.4.4 exists to preserve.

**How to apply:** before proposing any new chart-local component for a NAV/allocation/cash-flow trend
surface, check against this list first — the earlier draft of the SELF-220 proposal invented parallel
components (`chart-empty-state`, `granularity-toggle`, a `stale-data-marker` analog) that all turned out to
already exist under different names. Ask team-lead or grep the design-system spec
(`docs/DESIGN/design-system-spec.md`) rather than assuming a gap.
