# Repro: a pgTAP file can lose assertions and still exit 0 under `psql`

**Author:** QA · **Measured:** 2026-08-10 · **Status:** ✅ **RESOLVED** — re-run independently by
DevOps on two non-`psql` routes. **The alarming branch is CLOSED: CI is not blind.**

This note exists because a refutation of a standing belief gets re-run by a different route
**before** anything is changed on its strength. It records a measurement and, just as
importantly, **the boundary of what that measurement establishes.** Do not act on the headline
without reading "What this does NOT establish".

**What survives, in one line:** *never verify a battery locally with bare `psql` — the exit code
lies.* The plan count enforces only through a TAP-aware consumer; `pg_prove` is one and `psql`
is not. **`supabase test db` exits `1` on Repro B**, so a required CI context cannot report
success on a battery that did not run. See "How it was settled" below.

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
  was NOT supported by this measurement.** It was supported only for `psql`. Anyone repeating
  the stronger claim was generalizing past the evidence — and the re-run below confirmed the
  stronger claim is **false**.

## How it was settled

The question this note originally left open was:

> Does `supabase test db` (i.e. `pg_prove`) exit **non-zero** on Repro B — a plan shortfall
> with zero failing assertions?

**Answered by DevOps, 2026-08-10, on two independent non-`psql` routes** — `pg_prove` invoked
directly inside the CLI's own image, and the literal `supabase test db` — each run with **pass
*and* fail controls** so a uniform result could not be mistaken for a measurement.

**Result: `supabase test db` exits `1` on Repro B.** Reported tail:

```
Failed: 0 … Parse errors: Bad plan. You planned 3 tests but ran 2
```

Note the shape: **zero failed assertions, and a non-zero exit anyway** — the harness fails the
run on the *plan mismatch itself*, which is exactly the property `psql` lacks.

⚠ **The controls were load-bearing, not ceremony.** Mid-measurement, all three cases returned
exit `1` because of an unrelated connection error. Without a passing control that result would
have been reported as the right answer on false evidence — the correct conclusion reached by a
procedure that could not have distinguished it from the wrong one.

**Consequences:**

- **The alarming branch is closed.** A required CI context *cannot* report success on a battery
  that did not run. No DevOps fence is needed, and there is nothing here for Sec.
- **The narrow finding stands and is the durable half:** *never verify a battery locally with
  bare `psql`.* The plan count enforces only through a TAP-aware consumer.
- The standing pgTAP-immunity note has been updated to carry that scope: pgTAP's plan count is a
  real fence, but it is a fence **in the harness**, not in the SQL — so which harness reads the
  output decides whether it fences anything.

## ⚠ Why this note went stale, and the reusable half

Between being written and being read, this file was **false**. It said the question was open
after it had been answered, and it carried a `Zero →` branch predicting a CI-fence gap that had
been measured not to exist — the alarming branch left standing as a live possibility, which is
the worst of the four stale claims and is why it was deleted outright rather than annotated.

The mechanism is worth more than the instance: **the note carried a conditional, the condition
was discharged by someone else's measurement, and nothing in the file watched for that.** The
instruction "do not rewrite the standing note until step 3 has been run" was correct when
written and became satisfied-and-misleading the moment DevOps ran it — a claim with no watcher
on the event that falsifies it.

**The rule:** a note that opens a question must say **who closes it and where the answer lands**,
so the answer has a defined destination instead of depending on the author noticing. This file
now names DevOps as the owner and this section as the destination. Had it done so originally,
the staleness would have been a routing step rather than a catch.

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
