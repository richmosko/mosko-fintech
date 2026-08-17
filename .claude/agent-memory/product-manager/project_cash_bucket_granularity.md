---
name: cash-bucket-granularity
description: One-raw-cash-bucket limit (076 L1) vs 041's four Cash Sub-Cats — FDIC/SPIC are account-shaped and unresolved; CD/T-Bill dissolve via the multi-asset ruling; F/CTO fixture inspection is the hinge
metadata:
  type: project
---

The 022 cash-via-currency-asset model gives ONE raw-cash classification per user per currency (076 header L1), but the 041 seed carries four Cash Sub-Cats. The seed's own descriptions split the gap: **CD / T-Bill are instruments** — fillable per-asset today (brokered = per-symbol via 022 junction; bank CD = first-class manual asset per the SELF-325 ruling, see [[v12-manual-bucket-rehome]]) — while **FDIC / SPIC name the account's insurance regime** (bank vs brokerage raw cash) and are inherently per-account: they are the ENTIRE residual gap.

**Why:** PRD §2.2 text does NOT promise per-account cash classification (§2.2.1's assignment grammar is per-symbol + per-manual-asset only), so one-bucket-cash under-uses the seed without violating §2.2. The exposure is §3.3's §2.2 parity test: strict equality on full Sub-Cat enumeration (so NEVER prune seed rows) + numeric tolerance on every aggregated cell — fails only if the incumbent fixture foots raw cash into ≥2 cash rows simultaneously. Finance_Report_2026_04.pdf is not in-repo; F/CTO page-4 inspection is the ground truth.

**How to apply:** PM recommendation delivered 2026-08-16 = option (a) "instrument-routed cash" (accept one raw-cash bucket, route CD/T-Bill through assets, amend nothing unless the fixture inspection forces it); fallback ladder = (c) render-time FDIC/SPIC derivation by account type (Architect feasibility, not PM design) before conceding a §3.3 carve-out; (b) per-account cash classification stays V2. Any §3.3/§2.2 text amendment is F/CTO-only. Check status before drafting SELF-238/240 ACs — the "Unsorted"/cash rows in those tables depend on this ruling.
