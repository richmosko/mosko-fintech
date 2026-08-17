---
name: cash-bucket-granularity
description: FULLY LANDED 2026-08-17 — option (a) instrument-routed cash; label F/CTO-fixed as "Cash Balances" (not 'Cash', not 'Cash Equivalents'); §3.3 label-mapping footnote ratified+landed; seed delta (§7.20) still owed by Architect
metadata:
  type: project
---

**FULLY LANDED — F/CTO ruling 2026-08-17 (verbatim):** "Cash granularity = option (a), instrument-routed cash. Raw cash classifies once per currency into a bucket that must be labeled 'Cash' (or equivalent) — never FDIC/SPIC, because those names assert an insurance regime a catch-all doesn't honor. CD/T-Bill fill per-asset. Seed rows stay fillable, none pruned. (b) per-account classification stays V2." The "(or equivalent)" was then **fixed as "Cash Balances"** (F/CTO, same day): PM's `'Cash'` default was superseded; "Cash Equivalents" was rejected because the accounting term denotes exactly the instruments this bucket EXCLUDES (T-Bills/CDs/MMFs) — the ruling's own no-misleading-label rationale applied to the label discussion itself.

Fixture ground truth: F/CTO inspected `Finance_Report_2026_04.pdf` p. 4 — the incumbent foots raw cash into ONE row, so §3.3 got a **label-mapping footnote** (ratified + landed 2026-08-17, after the §2.2 parity test's Tolerance-class list), not a numeric carve-out. The footnote's "permitted superset row" clause is **load-bearing** (team-lead cross-check): the seed delta itself would otherwise break §3.3's full-Sub-Cat-enumeration strict clause.

**Why:** 076 L1 gives one raw-cash classification per user per currency via the 022 junction on the global currency-asset; the 041 seed had no raw-cash catch-all row and V1 is seed-only (009 write-dormant; 041's INSERT is the provisioning bootstrap only) — so the bucket must come from a **seed delta** (BACKLOG §7.20 item 1, Architect authors; 041's existence-guard means already-provisioned users need a backfill decision).

**How to apply:** PRD §2.2.1 (ruling + fixed label) / §2.2.2 (Cash Cat-group composition) / §3.3 (footnote) all landed on `meta/l1-cash-ruling` 2026-08-17. Still open: the Architect seed-delta migration (`sub_cat='Cash Balances'`; land before §2.2 parity is asserted). SELF-238/240 AC drafting unblocked — §2.2.2 Cash group = "Cash Balances" row (raw cash) + FDIC/SPIC/T-Bill/CD (per-asset only) + derived `Unsorted`; §2.2.3 has no cash rows. Side-product: **Chart of Accounts booked as §5.7 V2+ candidate** (motivated by the Cash/Cash-Balances awkwardness), cross-ref §7.13 design question. See [[v12-manual-bucket-rehome]] for the still-pending manual-bucket A-vs-B ruling on §2.2.1's other clause.
