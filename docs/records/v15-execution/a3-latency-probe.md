# A3 latency probe — `fn_nav_composition` + §2.1–§2.3 readers + `fn_compute_tax_liability`

*BACKLOG §7.34 item 1. Gates the A1+A2+A3 design unit before SELF-347's signature is finalized. Backend, 2026-09-05.*

## Environment

- Repo sha: `30ac2cc` (main tip at dispatch). Branch: `meta/v15-a3-latency-probe`.
- Local Supabase Docker Postgres, container `supabase_db_mosko-fintech`, `postgresql://postgres:postgres@127.0.0.1:54322/postgres`.
- **PostgreSQL 17.6** (aarch64, Supabase local image).
- Local `schema_migrations` was at **104** at probe start; **105 (`nav_composition_tax_flip`) and 106 (`owner_identification`) were pending** and are **not applied for this measurement** — `supabase migration up` was blocked by the Claude Code auto-mode classifier as a mutating command requiring F/CTO confirmation (requested from team-lead; not yet granted as of this writing). Every `fn_nav_composition` number below is therefore the **PRE-105 shape** (§2.1.5 buildup with the two tax rows still hardcoded `0::numeric`, no call to `fn_compute_tax_liability` inside it). See "What changes post-105" below for the reasoned projection, and re-run item 1 once 105 is applied to confirm it.
- Method: `psql \timing`, session set to `role='authenticated'` + `request.jwt.claims` (`sub=<tenant-uuid>`) via `set_config`, matching the pgTAP fixture idiom (`supabase/tests/_fixtures/rls_verbs.psql`) — never as `postgres`, so RLS cost is included. Everything wrapped `begin…rollback`; zero writes.

## Tenant data: no single tenant matches the brief's premise

The dispatch named "the seeded tenant with the SELF-217 NAV seeding data and the V1.4 tax seed" as the one production-shaped tenant. **That tenant does not exist on this DB.** Two different fixtures cover the two halves, and neither is production-scale:

| Tenant (`users_id`) | accounts | `account_trans` | `nav_daily` | `posting_prototype` | Notes |
|---|---|---|---|---|---|
| `b1aa21a2-…-cd2c` (SELF-217 seed, no `auth.users.email`) | **0** | 0 | **128** (2015-12-31 → 2026-07-31, monthly) | 0 | Real production-shaped **time span** (~11yr monthly checkpoints), but zero accounts/transactions — useless for `fn_nav_composition`/cashflow/tax. |
| `bf3eb3f4-…-c112b4` (`qa-self332-walk@example.com`) | 2 | **22** (2026-08-22 → 2026-08-26, 5-day span) | 0 | 30 | Largest real-ledger fixture on the DB. Still a walkthrough smoke fixture, not a production tenant. |

Used **tenant B** (`b1aa21a2…`) for the §2.1.2–2.1.4 NAV-performance readers (they read `nav_daily` directly, not accounts) and **tenant A** (`bf3eb3f4…`) for everything that composes on live accounts/transactions (`fn_nav_composition`, `fn_subcat_market_value`, `planning_target`, the §2.3 cashflow readers, `fn_compute_tax_liability`). Global `account_balance_checkpoint` and `holdings_checkpoint` are **both empty (0 rows) across every tenant on this DB** — this turns out to be the load-bearing fact of the whole probe; see "Why these numbers don't tell you what production will cost" below.

## What was measured (call graph enumerated from SELF-347 AC #4 + the file headers)

- **Account Holdings**: `pfin.fn_nav_composition(p_as_of)` — `051`, superseded by `105` (not applied here).
- **NAV Performance (§2.1.2–§2.1.4)**: `pfin.fn_nav_series` (`062`) + `pfin.fn_nav_series_inflation_adjusted` (`067`) [§2.1.2] · `pfin.fn_nav_delta_panel()` (`072`, latest signature) [§2.1.3] · `pfin.fn_nav_reference_dates()` (`073`) [§2.1.4].
- **Asset Allocation (§2.2)**: `pfin.fn_subcat_market_value(p_as_of)` (`076`/`081`) + `pfin.planning_target` (`074`, plain table read — no reader function).
- **Cash Flow (§2.3)**: `pfin.fn_cashflow_items(p_as_of)` + `pfin.fn_cashflow_cross_account_rollup(p_as_of)` (`093`) + `pfin.fn_historical_expenditures(p_as_of)` (`096`).
- **Estimated Taxes**: `pfin.fn_compute_tax_liability(p_as_of)` (`104`).
- Not measured: `fn_subcat_contributors` (`086`) / `fn_cashflow_contributors` (`099`) — per-row staleness-tinting drill-downs, not part of the composed render per SELF-347 AC #4.

## Measurements (10 runs each, warm cache, ms)

| Function | p50 | p95 | max |
|---|---|---|---|
| `fn_nav_series` (§2.1.2, monthly, 11yr range) — tenant B | 4.69 | 5.14 | 5.14 |
| `fn_nav_series_inflation_adjusted` (§2.1.2.c) — tenant B | 7.50 | 8.56 | 8.56 |
| `fn_nav_delta_panel` (§2.1.3) — tenant B | 1.10 | 2.72 | 2.72 |
| `fn_nav_reference_dates` (§2.1.4) — tenant B | 0.87 | 1.90 | 1.90 |
| `fn_subcat_market_value` (§2.2) — tenant A | 6.04 | 6.94 | 6.94 |
| `planning_target` read (§2.2) — tenant A | 0.67 | 1.07 | 1.07 |
| `fn_cashflow_items` (§2.3) — tenant A | 4.63 | 5.01 | 5.01 |
| `fn_cashflow_cross_account_rollup` (§2.3) — tenant A | 5.43 | 6.14 | 6.14 |
| `fn_historical_expenditures` (§2.3) — tenant A | 5.65 | 5.91 | 5.91 |
| **`fn_nav_composition`, PRE-105 shape** — tenant A | **79.48** | **82.22** | 82.22 |
| **`fn_compute_tax_liability` (104) alone** — tenant A | **43.99** | **45.04** | 45.04 |
| **Full composed set, back-to-back, one transaction** (nav_composition + tax_liability + subcat + planning_target + 3 cashflow readers; pre-105, i.e. excludes 105's internal materialized tax call) — tenant A | **142.6** | **145.4** | 145.4 |

Consistency check: the sum of the individually-measured pieces (≈145.3ms) matches the measured full-composed-set p50 (142.6ms) to within noise — no hidden transaction-wrapping overhead.

## EXPLAIN highlights

`fn_nav_composition`, `fn_compute_tax_liability`, `fn_cashflow_items` and `fn_subcat_market_value` are all `language sql`, single-statement, called as scalar/set expressions — Postgres does not descend into their body under `EXPLAIN`, so each shows as one opaque `Result`/`Function Scan` node. The numbers that matter are `Buffers: shared hit`:

- `fn_nav_composition` (pre-105): **780 buffer hits**, 74.9ms execution.
- `fn_compute_tax_liability`: **465 buffer hits**, 40.9ms execution.
- `fn_nav_series` / `fn_nav_delta_panel` / `fn_nav_reference_dates`: 52–150 buffer hits each, sub-ms to low-single-digit-ms execution.

Every `pfin` table on this DB totals under 250KB (`eod_price` 248KB/1 row, `account_trans` 168KB/28 rows, `tax_bracket_row` 96KB/224 rows — nothing here is large). 780 and 465 buffer hits against tables this small mean the same small set of pages is being **revisited many times**, not that a lot of distinct data is being scanned — i.e. the cost is structural (repeated correlated-subquery/per-row lookups), not data-volume-driven at this fixture's scale. That structural shape is exactly what turns into a real production-scale cost below.

## Why these numbers don't tell you what production will cost

`pfin.account_balance_checkpoint` and `pfin.holdings_checkpoint` are **empty on every tenant on this DB** (0 rows each). `fn_account_cash_as_of` (`056`, the leaf substrate under `fn_nav_composition` via `049`) is checkpoint-bounded by design — it sums `account_trans` only **since the account's last checkpoint**, falling back to `'-infinity'` when none exists. With zero checkpoints seeded anywhere, **every measurement above exercises the unbounded fallback path**, scanning an account's entire transaction history from account-open to `as_of` on every call. `fn_cashflow_items` (`093`) has the identical shape: its `txn` CTE filters `transaction_date <= p_as_of` with **no lower bound** — also a full-history scan, not a windowed one.

Tenant A has 5 days and 22 transactions of history, so "full history" and "since last checkpoint" are indistinguishable here. A real account after months or years of activity has thousands of transactions with **no checkpoint** to bound the scan (checkpoints are an optimization path that nothing in the current pipeline populates), so `fn_nav_composition`, `fn_compute_tax_liability`, and `fn_cashflow_items` all scale **linearly in the account's all-time transaction count**, not in a bounded recent window. **The ~80ms and ~44ms figures above are a floor for a brand-new account, not an estimate for a production tenant** — they measure fixed per-call overhead (bracket-schedule walk, per-account correlated subqueries), and say nothing about the linear term's slope because the fixture has no volume to expose it.

## What changes post-105 (not yet measured — migration pending)

`105` makes `fn_nav_composition` call `fn_compute_tax_liability` **once** internally (the `materialized` CTE fix — Sec's N-1 4×-call regression is already fixed on the file, confirmed by reading the migration; not re-verified live here since 105 isn't applied). Composing the pre-105 numbers: `fn_nav_composition` (≈79ms) + one `fn_compute_tax_liability` call (≈44ms) → **projected ≈123ms post-105**, fixture-scale. This needs a live re-measurement once `supabase migration up` is authorized; flagged as a follow-up, not asserted as fact.

**Independent of that number**, SELF-347 AC #4 composes **Estimated Taxes ← `fn_compute_tax_liability` (104)** as its own section, separate from Account Holdings ← `fn_nav_composition`. Once 105 lands, that is **a second, separate call to the same ≈44ms function in the same render** — `fn_nav_composition` already paid for one internally. Unless SELF-347 is written to reuse `fn_nav_composition`'s `buildups.realized_tax_liab` / `buildups.unrealized_tax_liab` envelopes for its own Estimated Taxes section instead of re-invoking `fn_compute_tax_liability`, A3 pays the ~44ms tax cost **twice per render** — at fixture scale that's the difference between a projected ≈161ms composed total (reuse) and ≈205ms (two calls). This is worth a signature note in SELF-347 regardless of the render-budget outcome below.

## Recommendation

**Cannot certify an inline render budget from this data — the checkpoint gap makes today's numbers non-representative of production cost, and the composition-shape question (one tax call or two) isn't settled yet.** With that caveat stated up front, here is the threshold logic to apply once both are resolved:

1. **In-app draft view** (rendered on every visit to the pending report, not just once) is the more latency-sensitive path — it wants sub-200ms if it's to feel synchronous with a page load. At fixture scale, even the pessimistic two-tax-call total (≈205ms) is borderline; at real production transaction volume (once checkpoints are either populated or the scan is bounded another way), the unbounded-scan finding above means this could be materially higher for a tenant with years of history. **Recommend: do not commit to inline-on-draft-view until (a) a checkpoint-population path exists (or the scan is otherwise bounded) and (b) it's re-measured against a tenant with realistic transaction volume (hundreds–thousands of rows, multi-year span).**
2. **On-demand generation (A10)** is a one-shot user-triggered action, not a per-visit render — a few hundred ms to low seconds is tolerable synchronously the way a "generate PDF" click already implies waiting. **Recommend: on-demand generation stays synchronous (no async/job-queue shape needed) even under the pessimistic projection**, provided a firm upper bound (e.g. p95 ≤ 1500ms) is confirmed once checkpoint/volume-realistic data exists — nothing measured here comes close to a multi-second cost at fixture scale, and the linear term would have to be very steep to cross that bar even at real volume.
3. **The losing side of recommendation 2**: if the population-scaled measurement later shows the unbounded transaction scan actually does blow past a ~1.5s budget for a realistic tenant (plausible if a tenant accumulates years of dense transaction history with never a checkpoint), the fix is almost certainly **populate `account_balance_checkpoint`/`holdings_checkpoint` periodically** (bounding the scan the way the code already assumes) rather than making on-demand generation async — async papers over a cost that has a cheaper, already-designed-for fix sitting unused.

**Bottom line for A1+A2+A3 dispatch:** proceed with SELF-347's signature and the audit-helper design (nothing here blocks those), but do not lock the render-budget number in SELF-347 AC #11 until (a) 105 is applied and re-measured, (b) SELF-347 decides one-tax-call vs. two, and (c) a checkpoint-populated or otherwise-bounded measurement replaces the fixture-scale numbers above for the linear term.
