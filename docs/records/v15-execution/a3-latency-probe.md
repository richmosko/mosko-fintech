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

`pfin.account_balance_checkpoint` and `pfin.holdings_checkpoint` are **empty for every tenant on the dev DB** (nothing in the current pipeline populates them). To test whether that's actually the cost driver — not just assume it, per team-lead's re-route — tenant C was measured **twice** in the same scratch DB: once as generated (checkpoints empty), then again after populating both checkpoint tables at 24 monthly month-ends (`temp/a3_synth_checkpoints_gen.sql`, not committed): 480 `account_balance_checkpoint` rows (one per account per month) and 864 `holdings_checkpoint` rows (per account/security/month, investment+retirement only). The result corrects the previous version of this record — see "Checkpoint-bounded vs. unbounded" below.

## What was measured (call graph enumerated from SELF-347 AC #4 + the file headers)

- **Account Holdings**: `pfin.fn_nav_composition(p_as_of)` — `051`, superseded by `105` (POST-105 shape on tenant C; PRE-105 on tenant A, see note).
- **NAV Performance (§2.1.2–§2.1.4)**: `pfin.fn_nav_series` (`062`) + `pfin.fn_nav_series_inflation_adjusted` (`067`) [§2.1.2] · `pfin.fn_nav_delta_panel()` (`072`, latest signature) [§2.1.3] · `pfin.fn_nav_reference_dates()` (`073`) [§2.1.4].
- **Asset Allocation (§2.2)**: `pfin.fn_subcat_market_value(p_as_of)` (`076`/`081`) + `pfin.planning_target` (`074`, plain table read — no reader function).
- **Cash Flow (§2.3)**: `pfin.fn_cashflow_items(p_as_of)` + `pfin.fn_cashflow_cross_account_rollup(p_as_of)` (`093`) + `pfin.fn_historical_expenditures(p_as_of)` (`096`).
- **Estimated Taxes**: `pfin.fn_compute_tax_liability(p_as_of)` (`104`).
- Not measured: `fn_subcat_contributors` (`086`) / `fn_cashflow_contributors` (`099`) — per-row staleness-tinting drill-downs, not part of the composed render per SELF-347 AC #4.

## Measurements (10 runs each, warm cache, ms — p50/p95)

| Function | Tenant A (fixture, 22 txns) | Tenant C, checkpoints EMPTY | Tenant C, checkpoints POPULATED |
|---|---|---|---|
| `fn_nav_series` (§2.1.2) — tenant B, 11yr monthly | 4.69 / 5.14 | *(O(`nav_daily` rows), not O(transactions) — not re-run)* | *(same)* |
| `fn_nav_series_inflation_adjusted` (§2.1.2.c) — tenant B | 7.50 / 8.56 | *(same)* | *(same)* |
| `fn_nav_delta_panel` (§2.1.3) — tenant B | 1.10 / 2.72 | *(same)* | *(same)* |
| `fn_nav_reference_dates` (§2.1.4) — tenant B | 0.87 / 1.90 | *(same)* | *(same)* |
| `fn_subcat_market_value` (§2.2) | 6.04 / 6.94 | 8.8 / 9.2 | 9.4 / 9.9 |
| `fn_cashflow_items` (§2.3) | 4.63 / 5.01 | 33.4 / 34.2 | 47.9 / 49.0 |
| `fn_cashflow_cross_account_rollup` (§2.3) | 5.43 / 6.14 | 35.2 / 38.3 | 49.1 / 50.0 |
| `fn_historical_expenditures` (§2.3) | 5.65 / 5.91 | 42.7 / 43.9 | 50.0 / 51.9 |
| **`fn_nav_composition`** (PRE-105 on tenant A; POST-105, one internal tax call, on tenant C) | 79.48 / 82.22 | **259.3 / 266.8** | **279.0 / 283.6** |
| **`fn_compute_tax_liability` (104) alone** | 43.99 / 45.04 | **164.7 / 166.5** | **183.0 / 187.3** |
| **Full composed set** (nav_composition + subcat + 3 cashflow readers + a **second, separate** tax_liability call for Estimated Taxes) | 142.6 / 145.4 *(pre-105 — only one tax evaluation total)* | **548.8 / 555.8** | **615.2 / 622.0** |

**Populating the checkpoint tables did not reduce cost — if anything the checkpoint-populated run measured 8–45% higher across every function, including ones that don't touch either checkpoint table at all** (`fn_subcat_market_value`, `fn_cashflow_items`). That rules out "checkpoints help but only a little" — a real per-row win would show up as a *reduction*, not a uniform-ish increase. The `EXPLAIN` evidence below confirms this isn't noise-shaped alone: `fn_nav_composition`'s buffer-hit count went **up** (170,435 → 189,193) with checkpoints in place, the opposite of what a scan-bounding optimization would produce. The increase across unrelated functions is attributed to background load from other teammates' concurrent activity on the same shared Postgres container during the second run (confirmed in `docker logs supabase_db_mosko-fintech`, which shows other sessions creating/dropping their own scratch DBs — `scratch_self353b`, `pfin_walk_p7` — in the same window), not to the checkpoint rows themselves.

## Why checkpoint population didn't move the number: it isn't wired into the expensive paths

Read `fn_account_cash_as_of` (`056`) again with this result in hand: it genuinely does query `pfin.account_balance_checkpoint` to bound its cash-balance sum, and that mechanism does work as designed. But **it was never the dominant cost** — the previous version of this record assumed populating checkpoints would flatten `fn_nav_composition` and `fn_compute_tax_liability`'s cost; that assumption is now measured wrong, and the reason is in the code, checked directly:

- **`pfin.holdings_checkpoint` has no reader in the 049/056/093/104/105 read-composition chain at all.** `grep -rl "from pfin.holdings_checkpoint\|join pfin.holdings_checkpoint" supabase/migrations/*.sql` returns only `018` (provider-sync write path), `019`, and `058` (account closure) — none of the functions this probe measures. The 864 rows populated for tenant C are **structurally inert** for this measurement; nothing reads them. The table exists for the reconciliation/provider-import family, not as a read-time bound on the securities leg.
- **`fn_gl_entries` (`035`) — the engine behind the securities/holdings leg of `fn_account_unrealized_gl` (`049`), and therefore of both `fn_nav_composition` and `fn_compute_tax_liability`'s unrealized computation — has zero checkpoint awareness of any kind.** Confirmed by grep against its defining migration: no reference to either checkpoint table. It always walks the full `account_trans`/annotation history for GL/trade-position classification, regardless of tenant age.
- **`fn_cashflow_items` (`093`) has no lower bound and no checkpoint concept in its contract at all** — it takes only `p_as_of`, no start date, by design (every §2.3 surface composes on it for YTD/quarterly figures that need the current tax year's transactions classified). There's no "since-checkpoint" alternative form to switch to.

So the one bounded path that exists (`account_balance_checkpoint` via `fn_account_cash_as_of`) is real but was never the expensive part; the actually-expensive parts (GL/trade-position classification, cash-flow item classification) have **no bounded alternative in the schema today, checkpoint tables or not**. This is a materially different, and more useful, finding than "populate the checkpoints" — it says the fix has to be a **new** mechanism (a periodic classified-income/GL rollup, not the existing balance/holdings checkpoints), which is an Architect-level design call, not something to prescribe here.

## The tax-liability-called-twice cost, confirmed at both checkpoint states

`105` makes `fn_nav_composition` call `fn_compute_tax_liability` **once** internally (materialized). Separately, SELF-347 AC #4 composes **Estimated Taxes ← `fn_compute_tax_liability` (104)** as its own section. Unless SELF-347 is written to reuse `fn_nav_composition`'s `buildups.realized_tax_liab` / `buildups.unrealized_tax_liab` envelopes instead of re-invoking `fn_compute_tax_liability`, **A3 pays the tax-computation cost twice per render** — holds at both measured states: dropping the second evaluation would cut the composed total from 548.8ms → ~384ms (checkpoints empty) or 615.2ms → ~432ms (checkpoints populated), roughly a **30% cut either way**, for a pure reuse fix with no schema change. This is worth a signature note in SELF-347 independent of the render-budget outcome below.

## Recommendation

The number to reason from is the **checkpoints-empty** column — that's the DB's actual current state on every tenant, dev and (per the finding above) effectively production too, since nothing populates these tables today: **549ms measured** (two tax evaluations, AC #4's literal composition) or **≈385ms** (one evaluation, tax-envelope reuse) at a *moderate* production tenant (20 accounts, ~5,000 transactions across 2 years). The checkpoints-populated column is stated as a control, not a better-case: it shows the proposed fix doesn't apply to the functions that matter, so it isn't a valid "best case" to plan around.

1. **In-app draft view** (rendered on every visit, not once): **do not render this inline.** Even the optimistic ≈385ms figure is well past what a synchronous page-load composition should cost, and it climbs with tenant tenure with no ceiling in the current design. The data says no, not "re-measure and see."
2. **On-demand generation (A10)**: **stays synchronous**, with headroom. ~549–615ms (unoptimized) is comfortably under a ~1.5–2s budget for a one-shot, user-triggered action at this tenant size. The risk is purely the unbounded scaling: a tenant with 3× this transaction volume (a plausible multi-year active user) extrapolates to roughly 3× the transaction-scaling components — call it ~1.4–1.8s composed — which starts to bite. **Recommend p95 ≤ 2000ms for on-demand generation**, revisited once a real bounding mechanism exists (see below), not a tighter number the unbounded scan could blow through for the more active tenants.
3. **The fix is a new mechanism, not populating the existing checkpoint tables** — that idea is now directly falsified by measurement, not just untested. `fn_subcat_market_value` (9ms) and the §2.1.2–2.1.4 NAV-performance readers (sub-10ms over an 11-year history) prove a genuinely bounded read stays cheap regardless of tenant age; the expensive functions (`fn_gl_entries`'s trade-position walk, `fn_cashflow_items`'s classification scan) simply have no bounded form in the schema today. **Recommend Architect scope a periodic classified-rollup mechanism** (e.g., a monthly materialized GL/income summary analogous to what `nav_daily` already does for NAV) as the durable fix, rather than extending `account_balance_checkpoint`/`holdings_checkpoint` further. **Losing side**: this is new design work with no owner or estimate today: if it doesn't land before a tenant's real data reaches the scale where 2s stops being enough, the on-demand path needs the async shape as an interim measure — don't treat "async isn't needed" as permanent independent of that work landing.

**Bottom line for A1+A2+A3 dispatch:** SELF-347 AC #11 can state a real number — **on-demand generation p95 ≤ 2000ms, synchronous; in-app draft view does NOT compose live** (reads the stored `final`/`draft` payload only, per R1 (A), which the AC family already assumes). Two follow-ups worth booking, neither blocking: (a) SELF-347 should specify tax-envelope reuse rather than a second `fn_compute_tax_liability` call — cheap, ~30% of the composed cost, no schema change; (b) route "what bounds the GL/cashflow classification scan as tenants age" to Architect as a new BACKLOG item — **not** framed as "populate the checkpoint tables," which this probe now shows doesn't help.

## Appendix — scratch DB reproduction

- Clone: `scripts/db-template-clone.sh pfin_probe_a3` (requires `pfin_tmpl` current — `scripts/db-template-build.sh` if stale).
- Fixture data: `pg_dump -U postgres -d postgres --data-only --schema=pfin --schema=auth --table=<list>` off the dev DB (read-only), loaded into the clone; `pfin.nav_daily`'s write-tenant fence (`app.nav_computed_for`) needs `set_config` before that one table's `COPY`; four migration-seeded global tables (`asset`, `taxonomy_default`, `tax_character`, `posting_prototype_default`) needed their template-seeded rows deleted first to avoid PK collisions with the dump.
- Synthetic tenant: `temp/a3_synth_tenant_gen.sql` (not committed — throwaway, scratch-DB-only). `pfin.account_trans`'s append-only trigger (`account_trans_block_mutation`) had to be disabled/re-enabled around one corrective `UPDATE` (backfilling `cost_basis` on the synthetic BTO rows) — safe only because this is a disposable scratch DB, never do this against `postgres`.
- Checkpoint population: `temp/a3_synth_checkpoints_gen.sql` (not committed) — 24 monthly `account_balance_checkpoint` rows per account + `holdings_checkpoint` rows per (account, security, month) for investment/retirement accounts, run against the same clone after the first (checkpoints-empty) measurement pass, before the second.
- The full sequence (clone → load fixtures → generate synthetic tenant → measure → populate checkpoints → measure again → drop) was run twice across two dispatch messages that crossed in flight; both scratch DBs were dropped, confirmed empty, before moving on.
