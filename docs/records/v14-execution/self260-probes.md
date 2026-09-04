# SELF-260 / `103` — verification probe record

Branch `feature/self-260`. Re-run in full against the post-E23 bytes (the §17043 tenth
California bracket), on a scratch DB rebuilt from empty immediately beforehand.

**Harness.** Scratch DB `scratch260` in container `supabase_db_mosko-fintech`, REBUILT FROM
EMPTY for this run — `rollback` does not reset sequences, so a re-used scratch hides a whole
failure class. Build: `create database` → `extensions` schema + uuid-ossp / pgcrypto /
supabase_vault / pgtap → container-side `pg_dump --schema=auth` of the local dev DB, loaded as
`supabase_admin` **without** `--no-privileges` (a permissive load drops the REVOKEs too and
makes probe 5 vacuous) → migrations `001`…`099` then `101`, in `sort` order, one file per
`psql -v ON_ERROR_STOP=1` invocation → then `103`. `100` and `102` are skipped: they live on
sibling branches and touch neither bracket table. The banned local-reset CLI path was not
used, and `pfin_tmpl` was not used (cross-branch stale). Chain result: every file OK,
"CHAIN COMPLETE"; `103` first apply exit 0, no errors.

`auth.users` on the scratch carries **6 pre-existing users**, which is what makes the AC 7
reach assertion falsifiable rather than vacuous — on an empty `auth.users` every count below
would be 0 and the leg would pass while observing nothing.

**What each probe can and cannot see** — stated because several of these look stronger than
they are:
- Probe 1 observes the seeded VALUES and the reach arithmetic. It cannot observe whether the
  fence judged them; probe 3 does that.
- Probe 2's control leg is load-bearing: `set local` outside a transaction is a silent no-op,
  and the whole probe would then run as `supabase_admin` with every leg passing. The
  `current_user` / `rolbypassrls` row is what rules that out.
- Probe 3's monotone control is what makes the rejection legs evidence: a fence that rejects
  everything is not a fence. The ORDER of events is the finding, not the rejection.
- Probe 4 distinguishes "idempotent" from "no second apply was attempted" — `INSERT 0 0` is
  the load-bearing line.
- Probe 5 reads the CATALOG, not the file. A `revoke` that failed to parse would still leave
  the file looking correct.

## PROBE 1 — reach + per-schedule shape (AC 7, AC 1, AC 2, E23)

CA rows are now **10**, not 9 — the §17043 bracket. Expected totals: 6 users × 3 schedules
= 18 schedules; 6 × (7 + 3 + 10) = 120 rows.
```
 users | schedules | reach_3x | bracket_rows 
-------+-----------+----------+--------------
     6 |        18 | t        |          120
(1 row)

    schedule_type    | tax_year | standard_deduction | rows 
---------------------+----------+--------------------+------
 federal_ordinary    |     2026 |         16100.0000 |    7
 federal_lt_cg       |     2026 |             0.0000 |    3
 california_ordinary |     2025 |          5706.0000 |   10
(3 rows)

    schedule_type    | bracket_floor | bracket_rate 
---------------------+---------------+--------------
 federal_ordinary    |        0.0000 |   0.10000000
 federal_ordinary    |    12400.0000 |   0.12000000
 federal_ordinary    |    50400.0000 |   0.22000000
 federal_ordinary    |   105700.0000 |   0.24000000
 federal_ordinary    |   201775.0000 |   0.32000000
 federal_ordinary    |   256225.0000 |   0.35000000
 federal_ordinary    |   640600.0000 |   0.37000000
 federal_lt_cg       |        0.0000 |   0.00000000
 federal_lt_cg       |    49450.0000 |   0.15000000
 federal_lt_cg       |   545500.0000 |   0.20000000
 california_ordinary |        0.0000 |   0.01000000
 california_ordinary |    11079.0000 |   0.02000000
 california_ordinary |    26264.0000 |   0.04000000
 california_ordinary |    41452.0000 |   0.06000000
 california_ordinary |    57542.0000 |   0.08000000
 california_ordinary |    72724.0000 |   0.09300000
 california_ordinary |   371479.0000 |   0.10300000
 california_ordinary |   445771.0000 |   0.11300000
 california_ordinary |   742953.0000 |   0.12300000
 california_ordinary |  1000000.0000 |   0.13300000
(20 rows)

```

## PROBE 2 — a NEW authenticated user provisions; the second call is a no-op

The `current_user` / `bypasses_rls` row is the CONTROL: without it, nothing below is evidence.
```
INSERT 0 1
BEGIN
SET
SET
 current_user  |               auth_uid               | bypasses_rls 
---------------+--------------------------------------+--------------
 authenticated | cccccccc-0000-4000-8000-00000000260c | f
(1 row)

 call_1_schedules_created 
--------------------------
                        3
(1 row)

 call_2_schedules_created 
--------------------------
                        0
(1 row)

 my_schedules_rls_scoped 
-------------------------
                       3
(1 row)

 my_rows_rls_scoped 
--------------------
                 20
(1 row)

    schedule_type    | tax_year | standard_deduction 
---------------------+----------+--------------------
 federal_ordinary    |     2026 |         16100.0000
 federal_lt_cg       |     2026 |             0.0000
 california_ordinary |     2025 |          5706.0000
(3 rows)

COMMIT
 total_schedules_migration_role | total_rows_migration_role 
--------------------------------+---------------------------
                             21 |                       140
(1 row)

DELETE 1
 after_probe_user_removed 
--------------------------
                       18
(1 row)

```

## PROBE 3 — AC 3: first exercise of `101`'s deferred set fence on a MULTI-ROW batch

**3a** asserts the SEEDED California set — the one that actually committed at apply time,
now ten rows through 0.133 — is monotone with a zero floor, i.e. that the fence accepted a
real batch rather than merely rejecting synthetic ones. **3b/3c/3d** are the falsifying
legs. The load-bearing observation in 3c/3d is the ORDER of events: the bad multi-row
INSERT **returns successfully** (`INSERT 0 N`) and the fence raises at COMMIT — a BEFORE ROW
fence would have produced the identical successful INSERT and then committed.
```
    schedule_type    | rows | lowest_floor | rates_non_decreasing |  top_rate  
---------------------+------+--------------+----------------------+------------
 federal_ordinary    |    7 |       0.0000 | t                    | 0.37000000
 federal_lt_cg       |    3 |       0.0000 | t                    | 0.20000000
 california_ordinary |   10 |       0.0000 | t                    | 0.13300000
(3 rows)

  ^^ 3a: the SEEDED sets the deferred fence ACCEPTED at apply time. CA = 10 rows, top 0.133.
BEGIN
INSERT 0 1
INSERT 0 3
COMMIT
  ^^ 3b CONTROL: monotone 3-row batch, one statement -> COMMITTED (the leg can pass).
BEGIN
DELETE 3
INSERT 0 3
  ^^ 3c NON-MONOTONE 3-row batch: the INSERT SUCCEEDED. Now COMMIT ->
ERROR:  tax bracket schedule 25 rejected: the bracket at floor 200.0000 carries rate 0.05000000, below the preceding bracket's rate 0.20000000 — bracket_rate must be non-decreasing in ascending bracket_floor order (SELF-259 set fence, leg B rate monotonicity)
CONTEXT:  PL/pgSQL function pfin.fn_tax_bracket_row_schedule_invariants() line 86 at RAISE
WARNING:  there is no transaction in progress
ROLLBACK
BEGIN
DELETE 3
INSERT 0 3
  ^^ 3d leg A: fully MONOTONE but lowest floor 500, not 0. INSERT SUCCEEDED. Now COMMIT ->
ERROR:  tax bracket schedule 25 rejected: its lowest bracket_floor is 500.0000, not 0 — a schedule that does not start at zero silently taxes the first 500.0000 of income at no rate, and monotonicity cannot observe that (SELF-259 set fence, leg A zero-floor)
CONTEXT:  PL/pgSQL function pfin.fn_tax_bracket_row_schedule_invariants() line 65 at RAISE
WARNING:  there is no transaction in progress
ROLLBACK
DELETE 1
 seed_intact_schedules | seed_intact_rows 
-----------------------+------------------
                    18 |              120
(1 row)

```

## PROBE 4 — second apply of `103` is a true no-op

The load-bearing line is the backfill statement reporting `INSERT 0 0`.
```
 before_schedules | before_rows 
------------------+-------------
               18 |         120
(1 row)

psql exit=0
COMMENT
CREATE FUNCTION
REVOKE
GRANT
COMMENT
INSERT 0 0
 after_schedules | after_rows 
-----------------+------------
              18 |        120
(1 row)

```

## PROBE 5 — posture / ACL of both new functions, read from the CATALOG
```
           proname            | security_definer | volatility |      proconfig       | public_exec | authenticated_exec | anon_exec | service_role_exec 
------------------------------+------------------+------------+----------------------+-------------+--------------------+-----------+-------------------
 fn_provision_tax_brackets    | f                | volatile   | {"search_path=\"\""} | f           | t                  | f         | f
 fn_tax_bracket_seed_template | f                | immutable  | {"search_path=\"\""} | f           | t                  | f         | f
(2 rows)

                     every_prosecdef_function_in_pfin                      
---------------------------------------------------------------------------
 fn_grant_creator_access, fn_reclass_history_insert, fn_refresh_updated_at
(1 row)

             signature_backend_wires              
--------------------------------------------------
 pfin.fn_provision_tax_brackets() returns integer
(1 row)

```
