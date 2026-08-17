---
name: target-denominator-beta-ruling
description: F/CTO 2026-08-17 — allocation targets are HIERARCHICAL (β): §2.2.3 renormalizes %Target at display over the twelve US-equity targets; 074 storage semantics (share of Total Non-RE) unchanged; two-way door with a p.5 post-hoc check at parity time
metadata:
  type: project
---

F/CTO ruled (2026-08-17, on the SELF-240 AC4 α-vs-β flag): **option β — targets are hierarchical, relative to the drill-down level** ("that's the intent"). §2.2.3's `%Target displayed = target_percent / Σ(twelve target_percents) × 100`; `$Target = that × Total US Equity`. §2.2.2 (incl. the collapsed "US - Sector Diversified" row) stays on 074's stored semantics: `target_percent` = share of Total Non-RE.

**Why:** 074 pins storage as share-of-Total-Non-RE while PRD §2.2.3 evaluates against Total US Equity — the two readings (α dollar-anchored vs β renormalized) diverge whenever actual US-equity weight ≠ the target sum. β matches the hierarchical intent and is **display-layer only**, so it's a recorded two-way door: flippable to α later without migration.

**How to apply:** (1) At §3.3 §2.2 parity time, an incumbent p.5 %Target-column inspection is the cheap post-hoc check — if p.5 contradicts β, flip is a display change + AC amendment, not schema. (2) β brings its own degenerate case: `Σ(twelve target_percents) = 0` → target columns render unset, never division-by-zero/NaN (SELF-240 AC5(ii)). (3) Any future drill-down surface (e.g. V2+ Ex-US) inherits the hierarchical reading by default — cite this ruling, don't re-litigate. Final AC sets delivered to team-lead 2026-08-17; landed in Linear via liaison. Related: [[cash-bucket-granularity]].
