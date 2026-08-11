# Repro: a pgTAP file can lose assertions and still exit 0 under `psql`

**Author:** QA · **Measured:** 2026-08-10 · **Status:** ⚠ ONE ROUTE ONLY — needs independent re-run

This note exists because a refutation of a standing belief gets re-run by a different route
**before** anything is changed on its strength. It records a measurement and, just as
importantly, **the boundary of what that measurement establishes.** Do not act on the headline
without reading "What this does NOT establish".

---

## The standing belief this bears on

Our standing note says pgTAP is immune to the `pytest.skip`-style silent-loss problem
**because it has a plan count**, where pytest does not. That is the belief under test.

**The measurement refines it rather than overturning it:** the plan count is *emitted*, but
under `psql` it does **not** reach the process exit code. Whether it reaches CI depends
entirely on which harness reads the output — and that is the part still unmeasured.

---

## Repro A — the real case (the 064 battery against migration 066)

The battery as it stood at `77e5146`, run against a database with `066` applied (which widened
the helper's return from 6 to 8 columns).

```
psql -h 127.0.0.1 -p 54322 -U postgres -d <db> -X \
     -f supabase/tests/rls/064_fn_cpi_u_index_for_period_rls.sql
echo $?
```

**Result:**

```
 not ok 15 - (E4) ...
 not ok 37 - (V5-FUNCTION-RESTORED-AND-PLAN-COUNTER-REARMED) ...
                    finish
----------------------------------------------
 # Looks like you planned 44 tests but ran 37
(1 row)
ROLLBACK
```

```
psql exit code: 0
```

- 35 passed · **2 failed** · **7 assertions never ran** · **5 hard aborts** · **exit 0**
- Cause: `create or replace function` cannot change a return type, and `returns table` **is**
  the return type. Five `(V)` legs rebuild the function at the old 6-column shape; each raised
  `ERROR: cannot change return type of existing function`, which **aborts the transaction** and
  cascades every following statement into `current transaction is aborted`.

⚠ **Repro A is NOT the decisive case,** and reading it as such is the trap. It contains two
genuine `not ok` lines, so *any* TAP-aware harness fails it on those alone, entirely
independently of the plan shortfall. Repro A shows the loss is possible; it does not show the
loss is *invisible*.

## Repro B — the decisive isolation (plan shortfall, **zero** failures)

This is the case that actually matters: assertions are lost and **nothing prints `not ok`**.

```sql
begin;
select plan(3);
select ok(true, 'leg 1 — passes');
select ok(true, 'leg 2 — passes');
-- leg 3 never runs: stands in for the abort-cascade / early-return class of loss.
select * from finish();
rollback;
```

**Result:**

```
 ok 1 - leg 1 — passes
 ok 2 - leg 2 — passes
 # Looks like you planned 3 tests but ran 2
```

```
psql exit code: 0
not ok lines: 0
```

The shortfall is reported **only** as a TAP diagnostic comment (a `#` line). Under `psql`
there is no failing assertion, no error, and no non-zero exit — nothing a shell `&&` or an
exit-code check would notice.

---

## What this establishes

Under **`psql`**, a pgTAP file can silently lose an arbitrary share of its assertions and still
exit `0`. This is a **real and current hazard for local verification** — running these files
with plain `psql` is exactly what a developer does when debugging, and it is what produced this
finding. A green local run is not evidence the battery ran.

## ⚠ What this does NOT establish

**It does not show that CI is blind, and I want that stated plainly rather than inferred.**

- CI does **not** run `psql`. Per `.github/workflows/db-tests.yml`, it runs
  `supabase test db`, which invokes **`pg_prove`**.
- `pg_prove` is a TAP consumer (Perl `TAP::Harness`), and **TAP semantics treat a plan mismatch
  as a failure.** So the most likely outcome is that `pg_prove` *does* catch Repro B and exits
  non-zero. I could not verify this locally: `pg_prove` is not installed on this machine, and
  `supabase test db` runs against the linked local stack, which does not have `063`/`066`
  applied — so it would fail for an unrelated reason and prove nothing.
- Therefore: **"a battery can lose a fifth of its assertions and still report success to CI"
  is NOT supported by this measurement.** It is supported only for `psql`. Anyone repeating
  the stronger claim is generalizing past the evidence.

## The one open question, and how to settle it

> Does `supabase test db` (i.e. `pg_prove`) exit **non-zero** on Repro B — a plan shortfall
> with zero failing assertions?

Decisive test, cheap to run, **DevOps-owned** (CI harness is not QA's authoring surface):

1. Drop Repro B into a scratch `supabase/tests/` tree as a `.sql` file.
2. `supabase test db` against a throwaway stack.
3. Read `echo $?`.

- **Non-zero** → CI is fine, the standing pgTAP note stands as written, and the correct fix is
  a narrower one: *never verify a battery locally with bare `psql`; the exit code lies.*
- **Zero** → this outranks everything else and becomes a CI-fence gap: a required context that
  can report success on a battery that did not run. That would need a DevOps fence
  (e.g. assert the printed plan against the printed test count) and a Sec look.

⚠ Do **not** rewrite the standing pgTAP-immunity note until step 3 has been run by someone
other than me, on a route other than `psql`. That is the whole reason this note stops here
instead of concluding.

---

## Why it stayed hidden until now

The battery's own header already documented this hazard **for a different mechanism** — a
*dropped column* aborting the transaction at the `(E)`/`(B)` leg boundary — and the fix applied
then was a leg **reordering**. A reordering cannot help here, because the abort now comes from a
*changed return type* in the `(V)` block. The rule generalizes past the fix that was applied to
it, which is why the extended battery states the general form: **any** future change to this
function's return shape must update all five `(V)` mutants in the same PR.

The mitigation that does survive is structural: `(V5)` sits outside every savepoint and runs
last, so a plan shortfall still gets *printed*. Printing is not exiting — that is the gap.
