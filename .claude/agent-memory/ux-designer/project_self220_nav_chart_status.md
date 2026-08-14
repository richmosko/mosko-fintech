---
name: project-self220-nav-chart-status
description: SELF-220 NAV-over-time chart UX status as of 2026-08-12 — proposal complete, PM concurred, held for F/CTO ratify
metadata:
  type: project
---

SELF-220 (§2.1.2.d NAV-over-time chart UI) — **F/CTO ratified the ADR-053 D7 disposition (Option b,
suppress-and-disclose) on 2026-08-12.** Finished addendum text (ready to paste as `## 12.` onto
`docs/DESIGN/flows/phase-2-flows-2.1-net-worth.md`, after the locked `## 11.`) is at
`temp/ux-self220-addendum.md`, handed to team-lead who carries it in a doc branch (UX doesn't commit here per
team-lead's instruction for this item). Full working history/PM exchange is in `temp/ux-self220.md`
(superseded by the addendum once it lands — both are gitignored, so if this project entry survives and those
files don't, the addendum's landed copy in the flow doc is the source of truth going forward).

**Two-part deliverable:**
1. ADR-053 Decision 7 disposition (routed PM+UX joint per the ADR). Recommended Option (b) — suppress the
   NAV checkpoint-carry marker before the first cron-written checkpoint (the imported Dec-2015-forward
   monthly-grain decade would otherwise mark ~3,600 points "stale" at weekly/daily zoom), replaced with a
   static "Monthly resolution before <date>" disclosure. PM concurred and reframed it as an application of
   §2.4.4's already-ratified "fires only where due" rule to a second axis, not a new exception — that framing
   is load-bearing for how the ratify ask should read.
2. Interaction/marker states for the chart (dual-line legend, gap rendering for NULL
   `nav_inflation_adjusted`, informational CPI-carry marker, granularity toggle density behavior, zoom/drill,
   empty/sparse states) — designed against `067_fn_nav_series_inflation_adjusted.sql`'s exact 11-column
   contract, and reconciled onto team-lead-confirmed locked design-system pieces (`chart-granularity
   chip-group`, `chart-placeholder` 5-state set) rather than inventing parallel components.

**Confirmed real gaps needing Visual Designer** (team-lead confirmed both, single dispatch after F/CTO
ratify): the sparse-history density indicator (no locked spec existed) and `informational-marker-badge` (no
`chart-placeholder` state covers the §2.4.4 informational tier — reusing `stale-segment` would collapse the
actionable/informational distinction §2.4.4 exists to preserve). `resolution-disclosure` joins that dispatch
only if Option (b) ratifies.

**Post-ratify progress (as of this session's later turns):** sparse-state anchoring corrected — the 60-month
window is PRD-locked as *rolling* (trailing, ending at today), so the partial line is right-anchored to today
and the density hatch sits on the LEFT (months before tracking-start), not right as Visual's first CSS
attempt assumed; corrected in `temp/ux-self220-addendum.md` §12.9. Also ruled the imported-only
resolution-disclosure copy variant (no cron boundary date exists to name): **"Monthly resolution —
daily/weekly tracking hasn't started yet."** — generalizes a Frontend placeholder (landed `c7ba15f`) that had
named only "daily." This is a follow-up owed to §12.6 when the doc branch reopens for edits (not yet folded
into the addendum text itself — flagged to team-lead as text to paste in). Build was authorized on a
LayerCake render decision + a 3-field helper (`069`) exposing the boundary date. If picking this up cold,
verify current state from team-lead/MILESTONES rather than trusting this entry — SELF-220 was moving fast at
session's end (component build → QA battery → Sec joint-review → F/CTO PR was the stated remaining sequence).

**Why:** the imported historical decade collides with the existing checkpoint-carry staleness marker at fine
chart granularity — correct mechanically, misleading as UX. See [[reference_locked_chart_design_system_pieces]].

**How to apply:** when this session or a future one picks SELF-220 back up, check whether F/CTO has ratified
before assuming the doc is final — `temp/` content doesn't survive cleanup, so if this file is gone, recover
from `docs/DESIGN/flows/phase-2-flows-2.1-net-worth.md`'s addendum (where it promotes to post-ratify) or ask
team-lead for status.
