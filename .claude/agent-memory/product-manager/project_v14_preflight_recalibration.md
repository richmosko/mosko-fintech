---
name: v14-preflight-recalibration
description: V1.4 (§2.5 Estimated taxes) pre-flight PM findings delivered 2026-09-03 @ b462816 (baseline 2cd94ae); what gates on the sitting and what PM owes after ratify.
metadata:
  type: project
---

V1.4 pre-flight PM findings pushed 2026-09-03 at `meta/v14-preflight-pm` @ `25c5685` (round 1 `b462816`; §8 reconciliation + §9 Part B on 259–262 added) (`docs/records/v14-preflight/pm-findings.md`, baseline `2cd94ae`); sibling files: Architect @ `9774a7c`, Sec @ `39bc549`. Gates on the F/CTO batch-ratify sitting.

**Why:** ADR-063 D1 pass; 0 of 9 issues buildable as drafted (V1.3 precedent held). The findings that outlive the file: (1) §2.5.1's CG columns have no V1 input path (no sale writer, `lot_match` dormant) — §6.1 options, PM rec UNAVAILABLE-with-reason; (2) Gate B Option A (`tax_jurisdiction` column) is CHANGELOG-only, and the IRS/FTB ledgers double-count payments in NAV under PRD-as-written (A-9, PM-found, Architect to verify vs `051`); (3) Seam E one-way door — PM refinement A′ (headline + §2.1.5 tax-adjusted via composed reader; `nav_daily` stays gross, labeled); (4) SELF-264 IS V1.4 — ledger line wrong, drop the count; (5) §7.28 item 3 carrier = SELF-263 re-scoped, and the booking omitted the asset-side `taxonomy_default` rows; (6) 302/303 MOVE to Platform with Seam I residual on 262 (empty domain today — no basis_adjust writer); (7) Part B: promote 259/260/262 INTO V1.4 (SELF-245 Comment-3 ground), 261 by seam W; 259 lacks a create path for a new tax year; 260 seeds the founding user only.

**How to apply:** post-ratify, PM owes the PRD amendment PR (A-1..A-13 per rulings; A-7/A-8/A-12 wording held for seam W / Gate B / F-4), the MILESTONES:44 fix, and the SELF-263/264 AC re-derivation. Verify every ruling against `docs/records/v14-preflight/sitting-log.md` (if it exists) before drafting — never from this memory. Seam W lean (A) is conditional on §6.1 ruling (A).
