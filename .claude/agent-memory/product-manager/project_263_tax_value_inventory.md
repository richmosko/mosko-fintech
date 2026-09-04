---
name: self-263-tax-value-inventory
description: SELF-263 inventory proposal delivered 2026-09-03 on feature/self-263-pm (e472bd5); leans and the two findings that outlive the ruling
metadata:
  type: project
---

SELF-263 (V1.4 step 1) inventory proposal at `docs/records/v14-execution/self263-inventory.md`, branch `feature/self-263-pm` @ `e472bd5`, awaiting team-lead ruling (F/CTO delegation per sitting-log R5).

**Leans:** (i) `Equity / Contribution` → false/NULL, ADR-062 D4 rider replaced (equality-guarded backfill); (ii) Bond Premium confirm `ordinary` (notes wrong, value right); Dividend confirm `qualified_dividend` + ADD `Revenue / Dividend - Ordinary` (C; C′ = flip the generic bucket, F/CTO's call — depends on their MMF/REIT mix); (iii) asset principle = "disposed through the §2.4.3 lot machinery as a taxable event"; (iv) 24 LT-eligible + T-Bill `short_term_only`; Real Estate false EXPLICITLY.

**Why:** "per account type" cannot be a prototype-row value — `tax_treatment` is per `pfin.account`; the honest resolution is false + a V2 booking. And the routing table reads `tax_character` only on Ordinary-column contributions, so asset-side characters route nothing in V1 (eligibility declaration for §2.5.4 V2+).

**How to apply:** post-ratify PM owes §5 bookings (O-1 CA Treasury exemption, O-3 retirement-account events, O-4 Crypto-Fx split, O-5 collectibles, O-6 real-estate sales) and the R-1 reader obligation (Income reader must be class-scoped or STC/BTC proceeds sum into Ordinary Income) must reach SELF-262's AC. Verify against the landed migration before citing any value here.
