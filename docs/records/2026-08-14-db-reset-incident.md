# 2026-08-14 — shared local dev DB data wipe (`supabase db reset --db-url`)

Tracked-safe incident record (no dollar figures, no credentials). Full command-level
log was written by QA to `temp/qa-incident-db-reset.md` (gitignored session buffer);
this file is the surviving record. Related: the seeding-run record this incident
destroyed the data of — [`self217-nav-seeding-run.md`](self217-nav-seeding-run.md).

## What happened

During SELF-222's Sec-review cycle, QA needed a clean migrations-only scratch DB
and ran `supabase db reset --db-url "postgresql://…@127.0.0.1:54322/qa_scratch_clean" --no-seed`
against a scratch database it had created **inside the same Postgres container**
as the shared local dev DB. The `--db-url` flag **does not scope the reset**: the
command restarted the shared container and reset the default local project
database. The scratch target itself was destroyed too.

- **Lost (data only):** all rows in `auth.users`, `pfin.nav_daily` (the 129-row
  SELF-217 seeding-run result, tenant prefix `b1aa21a2`), `pfin.cpi_u_index`,
  `pfin.account`, `pfin.linked_source`, `pfin.user_settings`.
- **Survived:** the full schema (migrations intact, verified at head `071` at
  incident time; later advanced normally), `pfin_etl`'s fail-closed NOLOGIN
  posture (`055`'s inert-by-construction shape held through the reset), and all
  on-disk session artifacts.

## Root cause

An assumed flag scope, unverified on a throwaway target before running against
populated shared state — QA's own report names this plainly. The standing prose
prohibition ("`supabase db reset` is PROHIBITED — destroys F/CTO's active local
test data") was written in the two most-read places (migration headers, battery
headers) and did not hold: **a prohibition that lives only in prose is an
assertion with no watcher.**

## Response (same session)

1. QA self-reported immediately, took no further mutating action, and wrote the
   command-level log.
2. Damage verified independently by team-lead (from the DB) and Architect
   (read-only), not from the report.
3. **Recovery assets preserved and dual-verified** (sha256 by team-lead, then
   independently by Architect), originally at
   `~/Projects/mosko-fintech-recovery/nav-history-20260814/` — **relocated
   2026-08-22 into this repo at
   [`nav-history-20260814/`](nav-history-20260814/) (F/CTO order; sha256
   re-verified identical at the move: CSV `36eb6873…`, log `a684eea5…`; the
   out-of-repo directory was then deleted)** — `nav_backfill_run.log`
   (complete per-row record incl. the 2026-08-10 cron checkpoint) and
   `baseline_nav.csv`. **Corrected 2026-08-14, same day:** this
   record originally described the CSV as "NOT the run's input — it ends
   2025-09-30". That was false against the file: `baseline_nav.csv` **is** the
   run's exact input, complete `2015-12-31..2026-07-31` (2025-09-30 is an
   interior row, not the last), sha256-identical to
   `temp/nav-history/baseline_nav.csv` — the path the run log's own header line
   names as its input. Either preserved file therefore suffices for a faithful
   re-run; no reconstruction from the log is needed.
4. **`supabase db reset` is banned outright for all agents, any flags** —
   effective immediately, permanent. Scratch DBs are hand-built: `createdb` +
   `psql -f` per migration file (or a same-cluster schema dump), never a CLI
   reset/restart verb.
5. A mechanical guard (Sec recommends a permission-settings deny rule; DevOps
   executes) is a **pending F/CTO ruling** — the ban itself is another prose
   control and is not the fix.

## Recovery path (F/CTO-gated, open at record time)

`supabase/seed.sql` re-seeds `auth.users` + taxonomy; CPI re-pulls from BLS via
the ETL; NAV history re-runs via `workers/etl/run_nav_backfill.py` per the
ADR-053 contract (F/CTO executes: `--ack-delta` judgment and `pfin_etl` arming
are theirs). The pre-incident 2026-08-10 cron checkpoint value is plausibly in
the run log; a fresh checkpoint also regenerates on the next local cron run.

## Recovery completed (2026-08-14, same day — F/CTO option (b): supervised run)

Backend executed the recovery path with F/CTO personally holding the two
ADR-053-reserved gates (`pfin_etl` arming; `--ack-delta`, ratified at −100.00%
— larger than the original −99.40% because the computed-NAV comparand's
`pfin.account`/`linked_source` tables are empty post-wipe, a structural cause
verified from the DB before ratify). End state, all team-lead-verified from the
database:

- `auth.users` = 2 — the `seed.sql` dev stub plus the tenant recreated as a
  **bare-id stub on the exact original uuid** (F/CTO option (a), preserving
  every recorded `b1aa21a2` reference; auth fields can be layered onto the same
  row later — see BACKLOG §7.17).
- `pfin.user_taxonomy` = 63; `pfin.cpi_u_index` = 138 (2015-01..2026-07) plus
  one recorded nonpublication (2025-10, a real BLS gap).
- `pfin.nav_daily` = 128 rows, 2015-12-31..2026-07-31, **byte-identical
  per-row to the preserved run log**. The 129th pre-incident row (the
  2026-08-10 cron checkpoint) regenerates on the next local cron run.
- `pfin_etl` re-disarmed (`rolcanlogin = f`, password retained), matching the
  original run's close.

Two findings from the recovery itself: **(1)** the first committed attempt
failed clean (all-or-nothing held, zero rows) because nothing in the recovery
path recreated the tenant's `auth.users` row and preflight had checked row
*count*, not *identity* — an identity-aware preflight is the durable fix shape;
**(2)** this record's original description of `baseline_nav.csv` was false
against the file (corrected in place above, PR #458) and was inherited verbatim
by the recovery run's operator before being refuted from the file — the same
no-watcher lesson as the ban itself.

## The lesson in one line

`--db-url` on `supabase db reset` names a connection string, not a blast
radius. Verify a destructive tool's scope on a target with nothing at stake, or
do not use the tool.
