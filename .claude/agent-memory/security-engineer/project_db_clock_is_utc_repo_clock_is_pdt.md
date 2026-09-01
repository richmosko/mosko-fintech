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
Related: [[a-preference-reads-as-a-ruling-and-a-caveat-sets-the-axis]] (a true fact on the wrong axis).
