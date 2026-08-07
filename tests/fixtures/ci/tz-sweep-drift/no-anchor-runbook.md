# GOLDEN FIXTURE — no anchor (the extraction-guard case)

Not a real runbook. Consumed only by the `tz-sweep-identical` extraction-guard step in
`.github/workflows/security-scan.yml`.

**This file deliberately contains no `psql "$PROD_DB_URL" -Atc \` anchor and no sweep
query.** It proves the fence FAILS CLOSED (exit 1) when it cannot locate the text it
compares, rather than comparing nothing to nothing and reporting green — which is the
precise defect class this whole surface exists to remove.

It is a purpose-built fixture rather than some incidental repo file for a reason worth
recording: the first version of that CI step pointed at `README.md`, which **does not
exist in this repo**. The step would have exited 2 (environment error) instead of 1
(fail-closed), failing the fence's own job on its first run and, worse, doing so for a
reason unrelated to the property being guarded. A guard whose target can disappear
underneath it is not a guard. This file cannot disappear without the fence's own diff
showing it.
