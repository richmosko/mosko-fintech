---
name: pgtap-isnt-passes-on-null
description: pgTAP's isnt() is IS DISTINCT FROM, so isnt(NULL, x) PASSES — a negative assertion over a subquery is fail-OPEN unless the NULL is guarded; ok() fails on NULL
metadata:
  type: reference
---

**Measured on a scratch DB with pgTAP, 2026-08-14 (not read from docs):**

| expression | result |
|---|---|
| `isnt(NULL::numeric, 690000::numeric, …)` | **ok** — passes |
| `isnt(8267000, 690000, …)` | ok — passes |
| `isnt(690000, 690000, …)` | not ok — fails |
| `ok(NULL::boolean, …)` | **not ok** — fails |
| `ok((select false where 1=0), …)` | **not ok** — fails (empty subquery → NULL) |

`isnt()` is `IS DISTINCT FROM`, so **NULL is "distinct from" everything and the
assertion passes.** `ok()` treats NULL as failure. So a negative assertion of the
shape `isnt((select … limit 1), <value>)` is **fail-OPEN**: if the subquery returns
no row, the leg goes green having observed nothing.

**Why this matters beyond trivia:** it landed in `(LEAK1)`, the leak-canary leg whose
entire purpose is proving the battery is not blind to a broken RLS policy — its own
assertion text reads *"green here would mean this battery is blind."* The bare
`isnt()` form reintroduced a vacuous green **inside the leg that exists to rule
vacuous greens out.** Sec's fix was to require the guard **written out** rather than
relied upon: `ok(<subquery> is not null and <subquery> <> <value>, …)`.

**How to apply:** any pgTAP negative assertion over a subquery — `isnt`, `isnt_empty`
adjacents, `doesnt_match` — ask *what does this do when the query returns no row?* and
prove the answer by running it in three states: **empty (must fail), the
not-yet-detected case (must fail), the detected case (must pass).** Three states, not
one; a single happy-path run cannot distinguish fail-closed from fail-open.

Related: [[watcher-not-fence-for-by-construction-properties]] ·
[[diff-of-two-outputs-proves-nothing-until-nonempty]] — same family: an instrument
that accepts "nothing" as a valid observation and reports success.
