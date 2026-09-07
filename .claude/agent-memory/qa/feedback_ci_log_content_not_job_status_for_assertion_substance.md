---
name: ci-log-content-not-job-status-for-assertion-substance
description: A green CI job status proves the process exited 0, not that a specific assertion's VALUE was what you claimed — read the actual log for the leg's own line (or its absence from the failure report) before asserting "the gap computed to 5 in CI" or similar substance claims.
metadata:
  type: feedback
---

Sec's review of the 115 `_get()` qualification fix (SELF-362, 2026-09-07) required: "'Fixed'
means green in CI AND the asserted gap still exactly 5 there — read the CI log for the leg's own
output after the push, not just the job status." I would have been tempted to report "CI passed"
from `gh run view --json conclusion` alone — that proves the pgTAP job exited 0, not that the
SPECIFIC watcher assertion evaluated to the claimed value.

**What actually settled it**: pulled the full job log (`gh run view <id> --log`) and searched for
two things — (1) the target file's own summary line (`115_fn_finalize_monthly_report_rls.sql
... ok`, with no "planned X but ran Y" note, unlike neighboring files that DO carry their own
known notes), and (2) the ABSENCE of "Test Summary Report" / "Failed" / "Dubious" / "not ok"
ANYWHERE in the whole log. pg_prove only prints a Test Summary Report entry for a file that had a
failed subtest or a genuine plan mismatch; its total absence across 2903 tests is stronger,
positive evidence than the file's own clean dot-line alone — a wrong watcher value would have
produced a `not ok` for that specific assertion number and landed 115 in that report. Neither
happened, so the gap genuinely computed to 5 in CI, not just "the job didn't crash."

**How to apply**: whenever a claim is about a specific assertion's VALUE or a specific
leg's SUBSTANCE (not just "did the suite pass"), pull the actual CI log text and grep for the
leg's own line plus the harness's failure-reporting markers, don't stop at
`conclusion: success`. This generalizes [[feedback_verifying_a_measurement_is_not_verifying_a_claim]]
to the CI-log domain specifically.
