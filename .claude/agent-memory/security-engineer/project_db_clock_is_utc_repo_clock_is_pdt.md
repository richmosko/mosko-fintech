---
name: db-clock-is-utc-repo-clock-is-pdt
description: pfin.fn_server_today() is current_date under a UTC-pinned session, so the DATABASE's "today" is up to 7h ahead of the repo/commit local clock — a past-tense date claim in an artifact can be TRUE for the DB and look false against git dates
metadata:
  type: project
---

**`pfin.fn_server_today()` is `select current_date`** (migration `070`, `language sql stable security invoker
set search_path = ''`). `current_date` evaluates in the **session TimeZone**, which `061` pins to UTC and
which [[verify-the-stated-correctness-mechanism]]-style deploy gating (runbook §10 TZ-1, ADR-043's E1
standing precondition) requires be UTC **from `source = database`**. The repo/commit clock is **local
PDT (-0700)**.

**Consequence, and it is the reusable half: for seven hours of every day the DB's "today" is the NEXT
calendar day from the repo's.** An artifact authored on a repo-local 2026-08-30 evening can correctly
assert, in the **past tense**, that something *"fired on the 2026-08-31 wall clock"* — because the only
clock the function reads had already rolled over. Measured 2026-08-30 at the SELF-344 review: local
`18:43 PDT`, UTC `01:43 on the 31st`, commits dated `2026-08-30 -0700`.

**Why:** I read `097`/ADR-065's *"fired on the 2026-08-31 wall clock"* as a false past-tense claim and
began drafting it as a finding, because every git date on the branch said the 30th. Running `date` and
`date -u` in the same turn showed it correct. **A month-end-sensitive defect was live in production at
review time and the artifacts said so accurately.**

**How to apply:** on any date-sensitive review — anchors, as-of windows, month-ends, retention, coverage
edges — **run `date; date -u` before grading a date claim, and ask WHICH CLOCK the claim is about.**
Never grade a date assertion against `git log` timestamps alone; those are local. The good artifacts on
this repo name the clock (`071`'s battery says *"the container's own 2026-08-31"*) and the weaker ones
say *"the wall clock"* — naming it is the cheap fix worth requesting, not a correction to the date.
⚠ **THE TRAP THIS MEMORY ITSELF SETS, disarmed here: `date default current_date` on a reader is NOT a
divergence from `fn_server_today()`.** At the SELF-262 review I was asked to check `104`'s
`p_data_as_of date default current_date` against "Lock 15 as-of discipline vs `fn_server_today()`", and
the shape of *this* memory primed me to find two clocks. There is one: **`fn_server_today()` IS
`select current_date`** (the first line above), evaluated in the caller's own session, so the default
and the threaded value are the **same expression**, not two. It is also the sibling convention —
`049` `051` `056` `076` `078` `081` `084` `086` `102` all carry `date default current_date`. Measured
2026-09-04. The real residual is different and smaller: a caller that invokes `fn_compute_tax_liability()`
and `fn_compute_nav(fn_server_today())` as **two statements** can straddle midnight, which is why the
Seam-C obligation is *one value threaded to both*, not *a particular default*. **A memory naming a
clock hazard makes every clock expression look like an instance; re-read what the named function
actually evaluates before grading a default.**

Related: [[a-preference-reads-as-a-ruling-and-a-caveat-sets-the-axis]] (a true fact on the wrong axis) ·
[[verify-the-stated-correctness-mechanism]].
