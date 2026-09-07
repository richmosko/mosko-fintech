---
name: feedback_stub_affordance_can_already_satisfy_a_later_ac
description: A P2 "route now, build later" stub can already fully satisfy a later phase's AC once the dependent backend route lands — verify before building.
metadata:
  type: feedback
---

On SELF-358 / P6 (PDF export), the dispatch brief asked me to build a "Download PDF"
affordance (copy, final-only enable, draft-disabled-with-tooltip, plain-anchor-to-GET-route)
on `MonthlyReportView.svelte`. That exact affordance — same copy, same tooltip string, same
disabled/enabled branching, same `pdfHref` prop already pointed at the real
`/reports/monthly/{YYYY-MM}/pdf` path — had already been built at P2 (SELF-354, commit
`6af8128`) as a `pdfHref` stub anticipating this route, per that file's own "route now, build
later" convention (same one `TaxQuarterlyTables`' `decompositionHref` / `CashflowRollupTable`'s
`editTargetsHref` already use). `MonthlyReportView.ssr.test.ts` already had passing SSR
assertions for both branches. Once Backend's real route landed (P6), the stub needed ZERO
changes — it already targeted the correct path shape.

**Why:** a phase brief is written from the AC text, not from a live grep of what a prior phase
already shipped as a forward-looking stub. Treating "build X" as literally true without first
checking git blame / existing tests risks either (a) wasted duplicate work, or (b) worse,
"fixing" a stub that was already correct into something that regresses it.

**How to apply:** before writing new component markup for an AC that names a specific copy
string / disabled-state / href shape, grep the target file for that exact copy string and check
`git log --follow -p` on it first. If it's already there and already tested green, the task
reduces to a REVIEW-and-confirm, not new authorship — report that explicitly rather than
manufacturing a diff to match the brief's "build" framing. See also
[[feedback_page_svelte_ahead_of_backend_loader]] for the mirror-image precedent (UI built ahead
of a loader that doesn't exist yet); this is UI built ahead of a route that doesn't exist yet,
later found already-correct once the route landed.
