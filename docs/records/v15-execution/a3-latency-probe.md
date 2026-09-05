# A3 latency probe — `fn_nav_composition` + §2.1–§2.3 readers + `fn_compute_tax_liability`

*BACKLOG §7.34 item 1. Gates the A1+A2+A3 design unit before SELF-347's signature is finalized. Backend, 2026-09-05.*

## Environment

- Repo sha: `30ac2cc` (main tip at dispatch). Branch: `meta/v15-a3-latency-probe`.
- **PostgreSQL 17.6** (aarch64, Supabase local image).
- Two databases used, both against the same Docker container (`supabase_db_mosko-fintech`, `127.0.0.1:54322`):
  - `postgres` (the shared local dev DB) — read-only, for the fixture-scale tenants. `supabase migration up` against it was requested and **explicitly refused**: it holds F/CTO's test data and verification runs never touch it, additive or not. It was at migration **104** for the whole probe (105/106 never applied there).
  - `pfin_probe_a3` — a disposable **scratch DB** cloned from the `pfin_tmpl` template (`scripts/db-template-clone.sh`, schema at **106**, includes 105's tax-flip). Populated by a **read-only** `pg_dump --data-only` of the fixture tenants' `pfin`/`auth.users` rows off `postgres`, plus one throwaway synthetic tenant generated directly in the scratch DB (`temp/a3_synth_tenant_gen.sql`, not committed). Dropped after this probe.
- Method: `psql \timing`, session set to `role='authenticated'` + `request.jwt.claims` (`sub=<tenant-uuid>`) via `set_config`, matching the pgTAP fixture idiom (`supabase/tests/_fixtures/rls_verbs.psql`) — never as `postgres`, so RLS cost is included. Everything wrapped `begin…rollback`; zero writes against the dev DB; the scratch DB is disposable.

## Tenant data

The dispatch named "the seeded tenant with the SELF-217 NAV seeding data and the V1.4 tax seed" as the one production-shaped tenant on the dev DB. **That tenant doesn't exist** — two different fixtures cover the two halves, and neither is production-scale:

| Tenant | accounts | `account_trans` | `nav_daily` | Notes |
|---|---|---|---|---|
| **B** `b1aa21a2-…-cd2c` (SELF-217 seed) | 0 | 0 | **128** (2015-12-31 → 2026-07-31, monthly) | Real production-shaped **time span**, zero accounts — used only for the §2.1.2–2.1.4 NAV-performance readers (they read `nav_daily` directly). |
| **A** `bf3eb3f4-…-c112b4` (`qa-self332-walk@example.com`) | 2 | 22 (5-day span) | 0 | Largest real-ledger fixture on the dev DB — a walkthrough smoke fixture, not production scale. |

Since a fixture-scale tenant can't answer the render-budget question (see below), a third tenant was synthesized directly in the scratch DB:

| Tenant | accounts | `account_trans` | tax jurisdictions | Notes |
|---|---|---|---|---|
| **C** `a3000000-…-00a3a3` (synthetic) | **20** (7 depository, 1 liability, 6 investment, 3 retirement, 2 real_estate, 1 crypto) | **4,903**, spread over 24 months | Federal (`irs`) + California (`ftb`) both designated, with copied bracket schedules | Generator: `temp/a3_synth_tenant_gen.sql`. Investment/retirement accounts carry real BTO lots (quantity/cost_basis/price) against 4 synthetic equities with a current `eod_price` each. `fn_nav_composition`/`fn_compute_tax_liability` both return fully **`"computed"`** (non-`unavailable`) results against it — verified live, not assumed. |

`pfin.account_balance_checkpoint` and `pfin.holdings_checkpoint` are **empty for every tenant, including the synthetic one** (the generator doesn't populate them — nothing in the current pipeline does, on any tenant). This turns out to be the load-bearing fact of the whole probe: see "Why cost scales the way it does" below.

## What was measured (call graph enumerated from SELF-347 AC #4 + the file headers)

- **Account Holdings**: `pfin.fn_nav_composition(p_as_of)` — `051`, superseded by `105` (POST-105 shape on tenant C; PRE-105 on tenant A, see note).
- **NAV Performance (§2.1.2–§2.1.4)**: `pfin.fn_nav_series` (`062`) + `pfin.fn_nav_series_inflation_adjusted` (`067`) [§2.1.2] · `pfin.fn_nav_delta_panel()` (`072`, latest signature) [§2.1.3] · `pfin.fn_nav_reference_dates()` (`073`) [§2.1.4].
- **Asset Allocation (§2.2)**: `pfin.fn_subcat_market_value(p_as_of)` (`076`/`081`) + `pfin.planning_target` (`074`, plain table read — no reader function).
- **Cash Flow (§2.3)**: `pfin.fn_cashflow_items(p_as_of)` + `pfin.fn_cashflow_cross_account_rollup(p_as_of)` (`093`) + `pfin.fn_historical_expenditures(p_as_of)` (`096`).
- **Estimated Taxes**: `pfin.fn_compute_tax_liability(p_as_of)` (`104`).
- Not measured: `fn_subcat_contributors` (`086`) / `fn_cashflow_contributors` (`099`) — per-row staleness-tinting drill-downs, not part of the composed render per SELF-347 AC #4.

## Measurements (10 runs each, warm cache, ms)

| Function | Tenant A (fixture, 22 txns) | Tenant C (synthetic, 4,903 txns) |
|---|---|---|
| `fn_nav_series` (§2.1.2) — tenant B, 11yr monthly | 4.69 / 5.14 *(p50/p95)* | *(not re-run; O(`nav_daily` rows), not O(transactions) — see below)* |
| `fn_nav_series_inflation_adjusted` (§2.1.2.c) — tenant B | 7.50 / 8.56 | *(same)* |
| `fn_nav_delta_panel` (§2.1.3) — tenant B | 1.10 / 2.72 | *(same)* |
| `fn_nav_reference_dates` (§2.1.4) — tenant B | 0.87 / 1.90 | *(same)* |
| `fn_subcat_market_value` (§2.2) | 6.04 / 6.94 | **9.3 / 10.4** |
| `planning_target` read (§2.2) | 0.67 / 1.07 | *(0 rows on tenant C — negligible)* |
| `fn_cashflow_items` (§2.3) | 4.63 / 5.01 | **48.4 / 49.8** |
| `fn_cashflow_cross_account_rollup` (§2.3) | 5.43 / 6.14 | **50.3 / 51.8** |
| `fn_historical_expenditures` (§2.3) | 5.65 / 5.91 | **57.4 / 58.4** |
| **`fn_nav_composition`** | 79.48 / 82.22 *(PRE-105 — no internal tax call)* | **288.0 / 293.5** *(POST-105 — includes one internal `fn_compute_tax_liability` call)* |
| **`fn_compute_tax_liability` (104) alone** | 43.99 / 45.04 | **186.6 / 190.8** |
| **Full composed set, back-to-back, one transaction** (nav_composition + subcat + planning_target + 3 cashflow readers + a **second, separate** `fn_compute_tax_liability` call for Estimated Taxes) | 142.6 / 145.4 *(pre-105 shape — only ONE tax evaluation total, since nav_composition didn't yet call it)* | **637.3 / 647.7** *(post-105 shape — TWO tax evaluations, one inside nav_composition + one standalone — this is the realistic AC #4 composition)* |

Consistency check on tenant A: the sum of the individually-measured pieces (≈145.3ms) matches the measured full-composed-set p50 (142.6ms) to within noise. On tenant C: 288 (nav, incl. 1 tax call) + 9.3 + 48.4 + 50.3 + 57.4 + 186.6 (second, standalone tax call) ≈ 640ms, matching the measured 637.3ms — same consistency, confirming no hidden transaction-wrapping overhead at either scale.

## EXPLAIN highlights and why cost scales the way it does

`fn_nav_composition`, `fn_compute_tax_liability`, `fn_cashflow_items` and `fn_subcat_market_value` are `language sql`, single-statement, called as scalar/set expressions — Postgres doesn't descend into their body under `EXPLAIN`, so each shows as one opaque `Result`/`Function Scan` node. `Buffers: shared hit` is the number that matters, and it moves in lockstep with transaction count:

| Function | Tenant A (22 txns) | Tenant C (4,903 txns) | Ratio |
|---|---|---|---|
| `fn_nav_composition` | 780 buffer hits, 74.9ms | **187,424 buffer hits, 284.2ms** | **240×** buffers for a 223× transaction increase — essentially linear |
| `fn_compute_tax_liability` | 465 buffer hits, 40.9ms | **126,296 buffer hits, 181.2ms** | **271×** buffers for 223× — also essentially linear |

This is the direct, measured consequence of the checkpoint gap: `fn_account_cash_as_of` (`056`, the leaf substrate under `fn_nav_composition` via `049`) is checkpoint-bounded **by design** — it sums `account_trans` only since the account's last `account_balance_checkpoint` row, falling back to `'-infinity'` when none exists. `fn_cashflow_items` (`093`) has the identical shape: its `txn` CTE filters `transaction_date <= p_as_of` with **no lower bound**. With zero checkpoints on any tenant, every measurement here — fixture and synthetic alike — exercises the unbounded fallback path: a full scan of the tenant's entire transaction history on every call, not a bounded recent window. The near-perfect linearity between the two measured points is empirical confirmation, not just an inference from reading the code: **cost is currently O(all-time transaction count) with no ceiling**, so it will keep climbing for a tenant who accumulates more history than this synthetic tenant's 24 months, with no built-in check to prevent it.

## The tax-liability-called-twice cost, now measured rather than projected

`105` makes `fn_nav_composition` call `fn_compute_tax_liability` **once** internally (materialized — confirmed live: tenant C's `fn_nav_composition` (288ms) ≈ its own leaf/holdings work (~101ms, extrapolated from tenant A's 79ms pre-105 baseline) + one internal tax evaluation (~187ms), which foots correctly). Separately, SELF-347 AC #4 composes **Estimated Taxes ← `fn_compute_tax_liability` (104)** as its own section. Unless SELF-347 is written to reuse `fn_nav_composition`'s `buildups.realized_tax_liab` / `buildups.unrealized_tax_liab` envelopes instead of re-invoking `fn_compute_tax_liability`, **A3 pays the tax-computation cost twice per render** — measured directly on tenant C: **637ms with two calls vs. a projected ≈450ms with one** (dropping the second ≈187ms evaluation). That's a 29% cut in the composed total from a pure reuse fix, no query optimization required. This is worth a signature note in SELF-347 independent of the render-budget outcome below.

## Recommendation

**637ms measured** (two tax evaluations, AC #4's literal composition) or **≈450ms** (one evaluation, if SELF-347 reuses nav_composition's tax envelopes) is the number to reason from — at a *moderate* production tenant (20 accounts, ~5,000 transactions across 2 years). A longer-tenured or more active tenant will cost more, close to linearly, because nothing bounds the scan yet.

1. **In-app draft view** (rendered on every visit, not once): **do not render this inline.** Even the optimistic ≈450ms figure is well past what a synchronous page-load composition should cost, before accounting for network/render overhead on top, and it only grows with tenant tenure. This isn't a "re-measure and see" caveat anymore — the data says no.
2. **On-demand generation (A10)**: **stays synchronous**, with headroom. 637ms (worst case, unoptimized) is comfortably under a ~1.5s budget for a one-shot user-triggered action at this tenant size. The risk is the unbounded scaling: a tenant with, say, 3× this transaction volume (still a plausible multi-year active user) would extrapolate to roughly 3× the transaction-scaling components — call it ~1.5–1.9s composed — which starts to bite. **Recommend a p95 ≤ 2000ms budget for on-demand generation, revisited if/when checkpoint population ships**, rather than a tighter number that the unbounded scan could blow through for the DB's more active users.
3. **The actual fix, not a workaround**: the render-budget problem here is not "the read composition is inherently slow" — `fn_subcat_market_value` (9ms) and the §2.1.2–2.1.4 NAV-performance readers (sub-10ms even over an 11-year history) show that a **bounded** read stays cheap regardless of tenant age. The expensive functions are exactly the ones with a designed-but-unused checkpoint-bounding path. **Populating `account_balance_checkpoint`/`holdings_checkpoint`** (e.g. at month-end, the same cadence `nav_daily` already checkpoints) would flatten `fn_nav_composition` and `fn_compute_tax_liability`'s cost to near-constant regardless of account age, which is a cheaper and more durable fix than pushing the on-demand path to an async/job-queue shape. **Losing side of this recommendation**: it's a real backlog item (checkpoint population has no owner today, per BACKLOG.md) — if it doesn't land before a tenant's data actually reaches the scale where 2s stops being enough, the on-demand path needs the async shape as an interim measure. Do not treat "async isn't needed" as a permanent conclusion independent of that work landing.

**Bottom line for A1+A2+A3 dispatch:** SELF-347 AC #11 can now state a real number — **on-demand generation p95 ≤ 2000ms, synchronous; in-app draft view does NOT compose live (reads the stored `final`/`draft` payload only, per R1 (A), which the AC family already assumes)**. Two follow-ups worth booking, neither blocking: (a) SELF-347 should specify tax-envelope reuse rather than a second `fn_compute_tax_liability` call — cheap, ~29% of the composed cost, no schema change; (b) checkpoint population for `account_balance_checkpoint`/`holdings_checkpoint` should get a BACKLOG entry and an owner — it's the actual fix for the unbounded-scan risk, not a nice-to-have.

## Appendix — scratch DB reproduction

- Clone: `scripts/db-template-clone.sh pfin_probe_a3` (requires `pfin_tmpl` current — `scripts/db-template-build.sh` if stale).
- Fixture data: `pg_dump -U postgres -d postgres --data-only --schema=pfin --schema=auth --table=<list>` off the dev DB (read-only), loaded into the clone; `pfin.nav_daily`'s write-tenant fence (`app.nav_computed_for`) needs `set_config` before that one table's `COPY`; four migration-seeded global tables (`asset`, `taxonomy_default`, `tax_character`, `posting_prototype_default`) needed their template-seeded rows deleted first to avoid PK collisions with the dump.
- Synthetic tenant: `temp/a3_synth_tenant_gen.sql` (not committed — throwaway, scratch-DB-only). `pfin.account_trans`'s append-only trigger (`account_trans_block_mutation`) had to be disabled/re-enabled around one corrective `UPDATE` (backfilling `cost_basis` on the synthetic BTO rows) — safe only because this is a disposable scratch DB, never do this against `postgres`.
- Scratch DB dropped after this probe.
