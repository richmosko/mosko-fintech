---
name: component-history-option-c
description: Component-history Option C chain fully LANDED 2026-08-12 (ADR-054 Accepted; A9/§5.1/§7.13 in BACKLOG) — read canon from the repo, not here
metadata:
  type: project
---

The 2026-08-12 component-history chain is **fully landed on main** — read canon there, not here: ADR-054 (Accepted; both Decision-5 questions CLOSED per the PM recommendations at the doc-PR double gate), BACKLOG §7.1 A9 (capture substrate), §5.1 (V2 visualization + sheet-backfill deferral), §7.13 (CoA/hierarchical-accounts design question, Architect-owned, timing fence (a) GL-substrate sequencing; fence (b) vacuous per ADR-054 D3 leaf capture).

**Why this memory survives at all — three residuals not obvious from any single file:**
1. **F/CTO rider on D5(2)** ("the scope of this might be configurable in V2.x versions") is recorded as a *named possibility, no inference drawn* — do not let a future V2 scoping session read it as direction; it is equally compatible with the posture staying fixed.
2. The ratified **never-list** (no columns on `054`; no §2.1.2 scalar-only-lock reopen; Expenses history stays with §2.3.4 + Distributions-(E) routed to the CoA question) lives at ADR-054 D5 — cite it when anyone re-litigates.
3. **Process fact:** the two D5 questions were deliberately held OPEN because the ratified P-flag text covered neither — the pattern to reuse: post-ratify scope-precision questions ride the ADR's own review gate rather than being baked as decided or delayed for a separate gate.

**How to apply:** before any V2 visualization or CoA work, re-read ADR-054 D5 closure lines + §7.13 live. temp/pm-* files from this chain are disposable.
