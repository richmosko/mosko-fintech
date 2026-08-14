---
name: feedback-check-locked-components-before-proposing
description: Team-lead corrected a component inventory that invented parallels to already-locked design-system pieces — check first, propose second
metadata:
  type: feedback
---

Don't draft a component inventory for a chart/dashboard interaction spec before checking whether the pieces
already exist in the locked design system. During SELF-220 (2026-08-12) I proposed `chart-empty-state`,
`granularity-toggle`, and treated the stale/carry-forward marker as needing a new parallel to the existing
`stale-data-marker` — team-lead corrected all three: the design system already had `chart-granularity
chip-group` and a 5-state `chart-placeholder` (`default`/`loading`/`empty-insufficient-history`/
`cpi-unavailable(nominal-only)`/`stale-segment`) that covered nearly everything I'd proposed fresh. Only two
of my flagged items turned out to be real gaps (a density indicator, and the §2.4.4 informational-tier
marker) — team-lead confirmed both explicitly rather than me assuming either way.

**Why:** inventing a parallel component when a locked one already covers the case creates redundant
vocabulary Visual/Frontend then has to reconcile — the cost lands on someone else's turn, not mine, so it's
cheap for me to skip the check and expensive for them to clean up.

**How to apply:** before finalizing a component inventory in any UX hand-off, either grep
`docs/DESIGN/design-system-spec.md` / ask team-lead what's already locked, or explicitly flag each proposed
item as "possible gap, not assumed" (as I did for the informational-marker-badge) rather than asserting it's
new outright. When genuinely unsure whether something is covered, say so and let team-lead or Visual Designer
confirm — that pattern worked cleanly here and got a fast, unambiguous answer back. See
[[reference_locked_chart_design_system_pieces]].
